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
}
