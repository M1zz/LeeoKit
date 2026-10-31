//
//  LeeoLadderTests.swift
//  LeeoKitTests
//
//  세 칸 요금제의 공통 규칙: 구독 졸업 때 · "연 구독 N년치" · 언제나 패스가 무엇을 믿는가.
//

import XCTest
@testable import LeeoKit

final class LeeoLadderTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: 구독 졸업

    func test_졸업가는_6개월째와_갱신_7일_전에_한_번씩() {
        let sub = LeeoGraduation.Subscription(productID: "p", since: day(2026, 1, 1),
                                              renewsAt: day(2027, 1, 1), willRenew: true)
        XCTAssertFalse(LeeoGraduation.isDue(sub, now: day(2026, 6, 30), lastOffered: nil, calendar: cal), "6개월 전에는 없다")
        XCTAssertTrue(LeeoGraduation.isDue(sub, now: day(2026, 7, 2), lastOffered: nil, calendar: cal))
        XCTAssertFalse(LeeoGraduation.isDue(sub, now: day(2026, 8, 1), lastOffered: day(2026, 7, 2), calendar: cal), "한 창에 한 번")
        XCTAssertTrue(LeeoGraduation.isDue(sub, now: day(2026, 12, 26), lastOffered: day(2026, 7, 2), calendar: cal), "갱신 7일 전 창")
    }

    func test_해지한_구독에는_갱신_앞_제안을_하지_않는다() {
        let sub = LeeoGraduation.Subscription(productID: "p", since: day(2026, 1, 1),
                                              renewsAt: day(2027, 1, 1), willRenew: false)
        XCTAssertFalse(LeeoGraduation.isDue(sub, now: day(2026, 12, 26), lastOffered: day(2026, 7, 2), calendar: cal))
    }

    // MARK: 평생은 연 구독 몇 년치

    func test_평생은_연_구독_몇_년치인지_말한다() {
        XCTAssertEqual(LeeoLadderText.yearsCovered(yearly: 13000, lifetime: 39000), 3)
        XCTAssertEqual(LeeoLadderText.yearsCovered(yearly: 17000, lifetime: 52000), 3)
        XCTAssertNil(LeeoLadderText.yearsCovered(yearly: 13000, lifetime: 17000), "2년치가 안 되면 말하지 않는다")
        XCTAssertNil(LeeoLadderText.yearsCovered(yearly: nil, lifetime: 39000))
    }

    // MARK: 언제나 패스

    private func tx(bundle: String = "com.xa.toki", product: String = "com.xa.toki.forever",
                    environment: String = "Production", revoked: Date? = nil, expires: Date? = nil) -> LeeoSignedGiftTransaction {
        LeeoSignedGiftTransaction(transactionID: "1", originalTransactionID: "1", bundleID: bundle, productID: product,
                                  type: "Non-Consumable", environment: environment, signedDate: nil,
                                  revocationDate: revoked, expiresDate: expires)
    }

    func test_패스는_우리_앱의_패스_상품만_믿는다() {
        XCTAssertTrue(LeeoForeverPassRule.opens(tx(), acceptsSandbox: false))
        XCTAssertTrue(LeeoForeverPassRule.opens(tx(product: "com.xa.toki.forever.graduate"), acceptsSandbox: false))
        XCTAssertFalse(LeeoForeverPassRule.opens(tx(product: "com.xa.toki.pro"), acceptsSandbox: false), "패스가 아닌 상품")
        XCTAssertFalse(LeeoForeverPassRule.opens(tx(bundle: "com.other.app", product: "com.other.app.forever"),
                                                 acceptsSandbox: false), "다른 개발자의 앱")
    }

    func test_환불_만료_시험결제는_열지_않는다() {
        XCTAssertFalse(LeeoForeverPassRule.opens(tx(revoked: Date()), acceptsSandbox: false))
        XCTAssertFalse(LeeoForeverPassRule.opens(tx(product: "com.xa.toki.forever.yearly", expires: Date().addingTimeInterval(-60)),
                                                 acceptsSandbox: false))
        XCTAssertTrue(LeeoForeverPassRule.opens(tx(product: "com.xa.toki.forever.yearly", expires: Date().addingTimeInterval(3600)),
                                                acceptsSandbox: false))
        XCTAssertFalse(LeeoForeverPassRule.opens(tx(environment: "Sandbox"), acceptsSandbox: false), "출시 빌드는 시험 결제를 믿지 않는다")
        XCTAssertTrue(LeeoForeverPassRule.opens(tx(environment: "Sandbox"), acceptsSandbox: true))
    }

    func test_다섯_앱이_패스_가족에_있다() {
        for bundle in ["com.Ysoup.TokenMemo", "com.xa.toki", "com.Ysoup.LeaveWise",
                       "com.example.ScheduleDensityApp", "com.devkoan.ScheduleDensityApp"] {
            XCTAssertTrue(LeeoForeverPassRule.family.contains(bundle), bundle)
        }
    }
}

// MARK: - 패스로 열리는 앱 목록

final class LeeoForeverPassAppsTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "LeeoForeverPassAppsTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    private func entry(id: String = "goldweek", bundleID: String = "com.Ysoup.LeaveWise",
                       storeID: String = "6755983135", intro: String = "https://example.com/en/",
                       icon: String? = nil) -> [String: Any] {
        var item: [String: Any] = ["id": id, "bundleID": bundleID, "appStoreID": storeID,
                                   "name": ["ko": "이름", "en": "Name"], "tagline": ["en": "Line"],
                                   "intro": ["ko": "https://example.com/ko/", "en": intro], "platforms": ["iPhone"]]
        if let icon { item["icon"] = icon }
        return item
    }

    private func payload(_ entries: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "apps": entries])
    }

    func test_내장_목록은_모두_로고와_소개_페이지가_있고_패스가_믿는_앱이다() {
        let apps = LeeoForeverPassApps.embedded
        XCTAssertEqual(apps.map(\.id), ["clipkeyboard", "goldweek", "rainbow-ios"])
        for app in apps {
            XCTAssertFalse(app.iconPNGData.isEmpty, app.id)
            XCTAssertTrue(LeeoForeverPassRule.family.contains(app.bundleID), app.id)
            XCTAssertEqual(app.introURL.scheme, "https", app.id)
            XCTAssertNotEqual(app.introURL.host, "apps.apple.com", app.id)
        }
    }

    func test_지금_쓰는_앱은_빠지고_개수에는_한_번만_든다() {
        let store = defaults()
        let others = LeeoForeverPassApps.others(than: "com.Ysoup.TokenMemo", defaults: store)
        XCTAssertFalse(others.contains { $0.bundleID == "com.Ysoup.TokenMemo" })
        XCTAssertEqual(LeeoForeverPassApps.unlockedCount(bundleID: "com.Ysoup.TokenMemo", defaults: store), 3)
        XCTAssertEqual(LeeoForeverPassApps.unlockedCount(bundleID: "com.xa.toki", defaults: store), 4)
    }

    func test_받은_목록은_패스가_모르는_앱_이상한_ID_로고_없는_앱을_뺀다() throws {
        let data = try payload([
            entry(),
            entry(id: "stranger", bundleID: "com.someone.else"),
            entry(id: "bad-id", storeID: "abc"),
            entry(id: "no-logo", bundleID: "com.xa.toki"),
            entry(id: "http", intro: "http://example.com"),
        ])
        XCTAssertEqual(LeeoForeverPassApps.decode(data, language: "en")?.map(\.id), ["goldweek"])
    }

    func test_받은_앱은_함께_온_로고로_설_수_있다() throws {
        let icon = Data([1, 2, 3]).base64EncodedString()
        let data = try payload([entry(id: "new-app", bundleID: "com.xa.toki", icon: icon)])
        XCTAssertEqual(LeeoForeverPassApps.decode(data, language: "en")?.first?.iconPNGData, Data([1, 2, 3]))
    }

    func test_없는_언어는_영어_소개_페이지로_간다() throws {
        let data = try payload([entry()])
        XCTAssertEqual(LeeoForeverPassApps.decode(data, language: "de")?.first?.introURL.absoluteString, "https://example.com/en/")
        XCTAssertEqual(LeeoForeverPassApps.decode(data, language: "ko")?.first?.introURL.absoluteString, "https://example.com/ko/")
    }

    func test_공개_목록_파일이_앱에서_읽힌다() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("pass-apps.json")
        let apps = try XCTUnwrap(LeeoForeverPassApps.decode(Data(contentsOf: url), language: "ko"))
        XCTAssertEqual(apps.map(\.id), LeeoForeverPassApps.embedded.map(\.id))
    }
}
