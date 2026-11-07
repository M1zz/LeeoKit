//
//  LeeoTipJarTests.swift
//  LeeoKitTests
//
//  팁(응원): 같은 결제를 두 번 세지 않는다 · 칸 이름이 순서로 붙는다 · 팁이 권한을 열지 않는다.
//

import XCTest
@testable import LeeoKit

private let tipPrivacy = URL(string: "https://example.com/privacy")!
private let tipSupport = URL(string: "https://example.com/support")!
private let tipIDs = ["com.example.tip.small", "com.example.tip.medium", "com.example.tip.large"]

private enum TipSpec: LeeoAppSpec {
    static let appName = "TipApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.example.TipApp")
    static let legal = LeeoLegalConfig(privacyURL: tipPrivacy, supportURL: tipSupport)
    static let monetization = LeeoMonetization.freemium(
        LeeoPurchaseConfig(productIDs: ["com.example.pro"],
                           gate: LeeoGatePolicy(proOnly: ["export"]),
                           tipJar: LeeoTipJarConfig(productIDs: tipIDs)))
}

/// 팁 상품을 판매 목록에도 넣은 계약. 팁을 낸 사람이 Pro 가 된다.
private enum TipSellsProSpec: LeeoAppSpec {
    static let appName = "TipBroken"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.example.TipBroken")
    static let legal = LeeoLegalConfig(privacyURL: tipPrivacy, supportURL: tipSupport)
    static let monetization = LeeoMonetization.freemium(
        LeeoPurchaseConfig(productIDs: ["com.example.pro", tipIDs[0]],
                           gate: LeeoGatePolicy(proOnly: ["export"]),
                           tipJar: LeeoTipJarConfig(productIDs: tipIDs)))
}

@MainActor
final class LeeoTipJarTests: XCTestCase {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "leeo.test.tip.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func test_같은_결제는_한_번만_센다_그리고_다시_켜도_남는다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults)
        XCTAssertFalse(jar.hasTipped)

        XCTAssertTrue(jar.record(transactionID: "1001"))
        XCTAssertFalse(jar.record(transactionID: "1001"), "구매 응답과 updates 가 같은 결제를 줘도 한 번이다")
        XCTAssertTrue(jar.record(transactionID: "1002"))
        XCTAssertEqual(jar.tipCount, 2)

        let reopened = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults)
        XCTAssertEqual(reopened.tipCount, 2)
        XCTAssertFalse(reopened.record(transactionID: "1002"))
    }

    func test_칸_이름은_순서로_붙는다() {
        XCTAssertEqual([0, 1, 2].map { LeeoTipTier(index: $0, of: 3).size }, [.small, .medium, .large])
        XCTAssertEqual([0, 1].map { LeeoTipTier(index: $0, of: 2).size }, [.small, .large])
        XCTAssertEqual(LeeoTipTier(index: 0, of: 1).size, .small)
        XCTAssertEqual(Set([0, 1, 2].map { LeeoTipTier(index: $0, of: 3).title }).count, 3)
    }

    func test_팁은_권한을_열지_않는다() {
        let config = TipSpec.paywall
        XCTAssertEqual(config?.tipJar?.productIDs, tipIDs, "계약의 팁이 페이월 구성까지 와야 한다")
        XCTAssertTrue(config?.entitlementIDs.isDisjoint(with: tipIDs) ?? false)
        XCTAssertTrue(LeeoPreflight.audit(TipSpec.self).isReleasable)

        let codes = Set(LeeoPreflight.audit(TipSellsProSpec.self).map(\.code))
        XCTAssertTrue(codes.contains("tip.sellsPro"))
    }

    func test_고마운_사람들_자리는_앱이_줄_때만_있다() {
        XCTAssertNil(LeeoTipJarConfig(productIDs: tipIDs).thanksPage, "주지 않으면 이름 올리기 칸을 그리지 않는다")
        let page = URL(string: "https://m1zz.github.io/Rereminder/#leeo-thanks")!
        let config = LeeoTipJarConfig(productIDs: tipIDs, thanksPage: page)
        XCTAssertEqual(config.thanksPage, page)
        XCTAssertNotEqual(config, LeeoTipJarConfig(productIDs: tipIDs), "자리가 다르면 다른 구성이다")
    }

    func test_부탁은_드물게_한다() {
        let day: TimeInterval = 24 * 60 * 60
        let now = Date()
        let big = LeeoTipMoment(id: "saved.5h", message: "5시간")
        let small = LeeoTipMoment(id: "saved.1h", message: "1시간")
        func pick(seen: Set<String> = [], asked: Date? = nil, tipped: Date? = nil, laters: Int = 0) -> String? {
            LeeoTipAskPolicy.pick(reached: [big, small], seen: seen, lastAskedAt: asked, lastTipAt: tipped,
                                  laters: laters, now: now)?.id
        }
        XCTAssertEqual(pick(), "saved.5h", "인상적인 것부터")
        XCTAssertEqual(pick(seen: ["saved.5h"]), "saved.1h")
        XCTAssertNil(pick(seen: ["saved.5h", "saved.1h"]), "같은 순간은 한 번만")
        XCTAssertNil(pick(asked: now.addingTimeInterval(-59 * day)), "물은 뒤 60일은 쉰다")
        XCTAssertNotNil(pick(asked: now.addingTimeInterval(-61 * day)))
        XCTAssertNil(pick(tipped: now.addingTimeInterval(-179 * day)), "낸 사람에게는 180일 묻지 않는다")
        XCTAssertNil(pick(laters: 3), "'다음에' 세 번이면 끝")
        XCTAssertNil(LeeoTipAskPolicy.pick(reached: [big], seen: [], lastAskedAt: nil, lastTipAt: nil,
                                           laters: 0, optedOut: true, now: now), "'다시 보지 않기' 를 누르면 끝")
    }

    func test_다시_보지_않기를_누르면_다시는_묻지_않는다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults)
        XCTAssertFalse(jar.optedOutOfAsks)
        jar.optOutOfAsks()
        XCTAssertTrue(jar.optedOutOfAsks)
        XCTAssertTrue(LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults).optedOutOfAsks,
                      "앱을 다시 열어도 남는다")
    }

    func test_보여_준_카드는_함께_넘은_작은_순간까지_쓴다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults)
        let reached = [LeeoTipMoment(id: "saved.5h", message: ""), LeeoTipMoment(id: "saved.1h", message: "")]
        jar.markAsked(covering: reached)
        XCTAssertEqual(jar.askSeen, ["saved.5h", "saved.1h"])
        XCTAssertNotNil(jar.lastAskedAt)
        jar.declineAsk(); jar.declineAsk()
        XCTAssertEqual(jar.askLaters, 2)
        jar.record(transactionID: "9")
        XCTAssertNotNil(jar.lastTipAt)
    }

    func test_상품이_하나씩_나와도_칸_이름은_계약의_자리를_따른다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults)
        // small · medium 만 나와 있을 때 (불러온 순서 0, 1)
        XCTAssertEqual(jar.tier(for: tipIDs[0], fallbackIndex: 0).size, .small)
        XCTAssertEqual(jar.tier(for: tipIDs[1], fallbackIndex: 1).size, .medium, "medium 이 '큰 것' 이름을 달면 안 된다")
        // large 만 따로 나와 있을 때
        XCTAssertEqual(jar.tier(for: tipIDs[2], fallbackIndex: 0).size, .large)
    }

    // MARK: 후원 보상

    func test_낸_칸이_곧_단계다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults, bundleID: "com.example.a")
        XCTAssertNil(jar.level, "내기 전에는 단계가 없다")
        jar.record(transactionID: "1", productID: tipIDs[0])
        XCTAssertEqual(jar.level, .supporter, "커피 한 잔이면 응원자")

        let (d2, s2) = makeDefaults()
        defer { d2.removePersistentDomain(forName: s2) }
        let snack = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: d2, bundleID: "com.example.a")
        snack.record(transactionID: "1", productID: tipIDs[1])
        XCTAssertEqual(snack.level, .regular, "간식 한 번이면 바로 단골이다(골드위크 피드백: 3점 칸을 내고 응원자에 머물렀다)")

        let (d3, s3) = makeDefaults()
        defer { d3.removePersistentDomain(forName: s3) }
        let meal = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: d3, bundleID: "com.example.a")
        meal.record(transactionID: "1", productID: tipIDs[2])
        XCTAssertEqual(meal.level, .patron, "든든한 한 끼면 바로 후견인")
        XCTAssertEqual(LeeoSupporterLevel.patron.next, .companion, "후견인 위로도 쌓여서 오른다")
        XCTAssertNil(LeeoSupporterLevel.honorary.next)

        let reopened = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: d3, bundleID: "com.example.a")
        XCTAssertEqual(reopened.level, .patron, "다시 켜도 단계가 남는다")
    }

    func test_작은_칸도_쌓여서_오른다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults, bundleID: "com.example.a")
        jar.record(transactionID: "1", productID: tipIDs[0])
        jar.record(transactionID: "2", productID: tipIDs[0])
        XCTAssertEqual(jar.level, .supporter)
        jar.record(transactionID: "3", productID: tipIDs[0])
        XCTAssertEqual(jar.level, .regular, "커피 세 잔은 간식 한 번과 같다")
    }

    func test_단계마다_이르는_칸이_하나씩이다() {
        XCTAssertEqual(LeeoSupporterLevel.allCases.map(\.tip), [.small, .medium, .large, nil, nil],
                       "위 두 단계는 팁 한 칸으로 닿지 않는다")
        for size in [LeeoTipTier.Size.small, .medium, .large] {
            let tier = LeeoTipTier(size: size)
            XCTAssertEqual(LeeoSupporterLevel.of(points: LeeoSupporterLedger.points(for: size)), tier.level,
                           "칸 옆에 적은 단계와 그 칸을 내고 받는 단계가 같다")
        }
    }

    func test_팁이_아닌_결제는_값을_커피_잔으로_쌓고_팁_횟수에는_넣지_않는다() {
        XCTAssertEqual(LeeoSupporterLedger.cups(price: 39000, unit: 1100), 35, "평생 Pro 는 커피 35잔")
        XCTAssertEqual(LeeoSupporterLedger.cups(price: 500, unit: 1100), 1, "커피 값에 못 미쳐도 낸 결제는 한 잔")
        XCTAssertEqual(LeeoSupporterLedger.cups(price: 0, unit: 1100), 0, "체험 · 오퍼 코드는 세지 않는다")

        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = [LeeoSupporterLedger.entry(bundleID: "com.example.a", transactionID: "paid.7", points: 35)]
        defaults.set(shared, forKey: "leeo.tips.shared")
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults, bundleID: "com.example.a")
        jar.record(transactionID: "1", productID: tipIDs[0])
        XCTAssertEqual(jar.points, 36)
        XCTAssertEqual(jar.level, .companion, "평생 구매와 팁 하나면 동반자")
        XCTAssertEqual(jar.tipCount, 1, "팁 횟수는 팁만 센다")
        XCTAssertFalse(LeeoSupporterLedger.isTip(shared[0]))
    }

    func test_장부가_생기기_전에_센_팁은_작은_칸으로_옮긴다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(4, forKey: "leeo.tips.count." + tipIDs[0])
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults, bundleID: "com.example.a")
        XCTAssertEqual(jar.tipCount, 4)
        XCTAssertEqual(jar.points, 4, "칸을 모르는 옛 팁은 1점씩")
        XCTAssertEqual(LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults).points, 4, "한 번만 옮긴다")
    }

    func test_앱이_따로_세던_옛_후원은_한_번만_옮긴다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults, bundleID: "com.example.mart")
        jar.adoptLegacyTips(3)
        jar.adoptLegacyTips(3)
        XCTAssertEqual(jar.points, 3, "다시 불러도 두 번 세지 않는다")
        XCTAssertEqual(jar.tipCount, 3)
        XCTAssertTrue(jar.hasTipped)
    }

    func test_다른_기기_다른_앱의_장부를_합친다() {
        let mine = [LeeoSupporterLedger.entry(bundleID: "a", transactionID: "1", points: 3)]
        let cloud = [LeeoSupporterLedger.entry(bundleID: "a", transactionID: "1", points: 3),
                     LeeoSupporterLedger.entry(bundleID: "a", transactionID: "2", points: 1),
                     LeeoSupporterLedger.entry(bundleID: "b", transactionID: "1", points: 10),
                     "모양이 틀린 줄"]
        let merged = LeeoSupporterLedger.merge(cloud, mine)
        XCTAssertEqual(merged.count, 3, "같은 결제는 한 줄, 다른 앱의 같은 번호는 다른 결제")
        XCTAssertEqual(LeeoSupporterLedger.total(merged), 14)
        XCTAssertEqual(LeeoSupporterLedger.lines(merged, of: "a").count, 2)
    }

    func test_후원_뒤_업그레이드_배너는_30일_쉰다() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let jar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: tipIDs), defaults: defaults)
        XCTAssertFalse(jar.tippedRecently())
        jar.record(transactionID: "1", at: Date().addingTimeInterval(-29 * 24 * 60 * 60))
        XCTAssertTrue(jar.tippedRecently())
        XCTAssertFalse(jar.tippedRecently(now: Date().addingTimeInterval(2 * 24 * 60 * 60)))
    }

    func test_보상_자리는_앱이_줄_때만_있다() {
        let config = LeeoTipJarConfig(productIDs: tipIDs)
        XCTAssertNil(config.supporterIcon)
        XCTAssertNil(config.betaURL)
        XCTAssertEqual(LeeoTipJarConfig(productIDs: tipIDs, supporterIcon: "SupporterIcon").supporterIcon, "SupporterIcon")
    }
}
