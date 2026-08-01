//
//  LeeoContractTests.swift
//  LeeoKitTests
//
//  성숙도 계약 레이어(수익모델·게이트·프리플라이트·매니페스트) 검증.
//  전부 순수 로직이라 네트워크·StoreKit 없이 돌아간다.
//
//  ⚠️ LeeoKit 버그는 N개 앱을 동시에 깬다 (OPERATING_POLICY §5) — 여기에만 더 투자한다.
//

import XCTest
@testable import LeeoKit

// MARK: - 픽스처

private let privacy = URL(string: "https://ysoup.io/privacy")!
private let support = URL(string: "https://ysoup.io/support")!
private let terms = URL(string: "https://ysoup.io/terms")!

private enum FreeSpec: LeeoAppSpec {
    static let appName = "FreeApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FreeApp")
    static let legal = LeeoLegalConfig(privacyURL: privacy, supportURL: support)
    static let monetization = LeeoMonetization.free
    static let appStoreID: String? = "1234567890"
}

private enum FreemiumSpec: LeeoAppSpec {
    static let appName = "FreemiumApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FreemiumApp")
    static let legal = LeeoLegalConfig(privacyURL: privacy, supportURL: support)
    static let monetization = LeeoMonetization.freemium(
        LeeoPurchaseConfig(
            productIDs: ["com.Ysoup.FreemiumApp.pro"],
            gate: LeeoGatePolicy(freeLimits: ["memo": 10], proOnly: ["export"], warnWhenRemaining: 2)))
    static let appStoreID: String? = "1234567891"
    static let capabilities = LeeoCapabilities(
        implemented: [.darkMode, .localization],
        notApplicable: [.pushNotifications: "알림이 필요 없는 단발성 유틸리티"])
}

private enum SubscriptionSpec: LeeoAppSpec {
    static let appName = "SubApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.SubApp")
    static let legal = LeeoLegalConfig(privacyURL: privacy, supportURL: support, createsAccounts: true)
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: ["com.Ysoup.SubApp.monthly", "com.Ysoup.SubApp.yearly"],
            termsURL: terms,
            gate: LeeoGatePolicy(proOnly: ["cloud"])))
}

/// 일부러 어긋나게 만든 계약 — 프리플라이트가 잡아내야 한다.
private enum BrokenSpec: LeeoAppSpec {
    static let appName = "BrokenApp"
    static let developerEmail = "leeo-at-kakao"                      // @ 없음
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "com.Ysoup.BrokenApp")  // iCloud. 접두어 없음
    static let legal = LeeoLegalConfig(privacyURL: URL(string: "http://ysoup.io/privacy")!,  // https 아님
                                       supportURL: support)
    // 유료 상품은 파는데 무료 사용자가 페이월에 닿을 경로가 없다
    static let monetization = LeeoMonetization.freemium(
        LeeoPurchaseConfig(productIDs: ["com.Ysoup.BrokenApp.pro"]))
}

/// 무료라고 선언해놓고 페이월을 직접 붙인 모순 계약.
private enum ContradictorySpec: LeeoAppSpec {
    static let appName = "ContradictoryApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.C")
    static let legal = LeeoLegalConfig(privacyURL: privacy, supportURL: support)
    static let monetization = LeeoMonetization.free
    static let paywall: LeeoPaywallConfig? = LeeoPaywallConfig(productIDs: ["com.Ysoup.C.pro"])
}

// MARK: - 수익모델

final class LeeoMonetizationTests: XCTestCase {

    func testFreeModelHasNoPaywall() {
        XCTAssertFalse(FreeSpec.monetization.requiresPaywall)
        XCTAssertNil(FreeSpec.paywall)
        XCTAssertTrue(FreeSpec.monetization.productIDs.isEmpty)
        XCTAssertFalse(FreeSpec.monetization.requiresRestore)
    }

    func testPaidUpfrontNeedsNoPaywall() {
        let m = LeeoMonetization.paidUpfront
        XCTAssertFalse(m.requiresPaywall)
        XCTAssertFalse(m.hasFreeTier)
        XCTAssertFalse(m.requiresRestore)
    }

    func testFreemiumDerivesPaywallFromContract() throws {
        let config = try XCTUnwrap(FreemiumSpec.paywall)
        XCTAssertEqual(config.productIDs, ["com.Ysoup.FreemiumApp.pro"])
        XCTAssertEqual(config.entitlementIDs, ["com.Ysoup.FreemiumApp.pro"])
        // 개인정보 링크는 legal 에서 자동으로 온다 — 앱이 두 번 적지 않는다
        XCTAssertEqual(config.privacyURL, privacy)
        XCTAssertTrue(FreemiumSpec.monetization.requiresRestore)
    }

    func testSubscriptionCarriesItsOwnTermsURL() throws {
        let config = try XCTUnwrap(SubscriptionSpec.paywall)
        // 구독은 타입이 약관 URL 을 강제하므로 항상 존재한다
        XCTAssertEqual(config.termsURL, terms)
        XCTAssertEqual(config.privacyURL, privacy)
        XCTAssertTrue(SubscriptionSpec.monetization.sellsSubscription)
        XCTAssertNotNil(SubscriptionSpec.monetization.subscriptionTermsURL)
    }

    func testExplorerModelStrings() {
        XCTAssertEqual(FreeSpec.monetization.explorerModel, "free")
        XCTAssertEqual(FreemiumSpec.monetization.explorerModel, "freemium")
        XCTAssertEqual(SubscriptionSpec.monetization.explorerModel, "freemium-subscription")
        XCTAssertEqual(LeeoMonetization.paidUpfront.explorerModel, "paid")
    }

    func testGateFlowsFromMonetizationToSpec() {
        XCTAssertEqual(FreemiumSpec.gate.freeLimits["memo"], 10)
        XCTAssertTrue(FreemiumSpec.gate.proOnly.contains("export"))
        XCTAssertFalse(FreeSpec.gate.hasAnyGate)
    }
}

// MARK: - 게이트 판정

final class LeeoGateTests: XCTestCase {

    private func gate(hasPro: Bool = false, trial: Bool = false) -> LeeoGate {
        LeeoGate(policy: FreemiumSpec.gate, hasPro: hasPro, isTrialActive: trial)
    }

    func testUnderLimitIsAllowed() {
        XCTAssertEqual(gate().evaluate("memo", current: 0), .allowed)
        XCTAssertEqual(gate().evaluate("memo", current: 5), .allowed)
    }

    func testApproachingLimitWarnsBeforeBlocking() {
        // 한도 10, 남은 2개 이하면 경고 — 부딪히기 전에 알린다
        XCTAssertEqual(gate().evaluate("memo", current: 7), .allowedNearLimit(remaining: 2))
        XCTAssertEqual(gate().evaluate("memo", current: 9), .allowedNearLimit(remaining: 0))
    }

    func testAtLimitBlocks() {
        let decision = gate().evaluate("memo", current: 10)
        XCTAssertEqual(decision, .blocked(LeeoGateReason(key: "memo", kind: .limitReached(limit: 10))))
        XCTAssertTrue(decision.needsPaywall)
        XCTAssertFalse(decision.isAllowed)
    }

    func testAddingMultipleRespectsLimit() {
        XCTAssertTrue(gate().evaluate("memo", current: 5, adding: 5).isAllowed)
        XCTAssertFalse(gate().evaluate("memo", current: 5, adding: 6).isAllowed)
    }

    func testProOnlyFeatureBlocksRegardlessOfCount() {
        let decision = gate().evaluate("export", current: 0)
        XCTAssertEqual(decision, .blocked(LeeoGateReason(key: "export", kind: .proOnlyFeature)))
        XCTAssertFalse(gate().allows("export"))
    }

    func testUnknownKeyIsAlwaysAllowed() {
        XCTAssertEqual(gate().evaluate("somethingElse", current: 9999), .allowed)
    }

    func testProUnlocksEverything() {
        let pro = gate(hasPro: true)
        XCTAssertEqual(pro.evaluate("memo", current: 10_000), .allowed)
        XCTAssertEqual(pro.evaluate("export"), .allowed)
        XCTAssertTrue(pro.isUnlocked)
        XCTAssertNil(pro.remaining("memo", current: 3))
    }

    func testTrialUnlocksEverything() {
        let trial = gate(trial: true)
        XCTAssertEqual(trial.evaluate("export"), .allowed)
        XCTAssertTrue(trial.isUnlocked)
    }

    func testRemainingCount() {
        XCTAssertEqual(gate().remaining("memo", current: 3), 7)
        XCTAssertEqual(gate().remaining("memo", current: 30), 0)   // 음수로 새지 않는다
        XCTAssertNil(gate().remaining("export", current: 0))       // 개수 한도가 아닌 키
    }
}

// MARK: - 체험 기간

final class LeeoTrialTests: XCTestCase {
    private var suite: String!
    private var engagement: LeeoEngagement!

    override func setUp() {
        super.setUp()
        suite = "leeo.test.\(UUID().uuidString)"
        engagement = LeeoEngagement(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNoTrialIsNeverActive() {
        XCTAssertFalse(LeeoTrial.none.isActive(engagement: engagement))
        XCTAssertEqual(LeeoTrial.none.remaining(engagement: engagement), 0)
    }

    func testDayTrialActiveOnInstallDay() {
        _ = engagement.installDate   // 설치 시각 고정
        XCTAssertTrue(LeeoTrial.days(7).isActive(engagement: engagement))
        XCTAssertEqual(LeeoTrial.days(7).remaining(engagement: engagement), 7)
        XCTAssertFalse(LeeoTrial.days(0).isActive(engagement: engagement))
    }

    func testLaunchTrialCountsDown() {
        engagement.registerLaunch()   // 1회차
        XCTAssertTrue(LeeoTrial.launches(3).isActive(engagement: engagement))
        engagement.registerLaunch()
        engagement.registerLaunch()   // 3회차 — 아직 유효
        XCTAssertTrue(LeeoTrial.launches(3).isActive(engagement: engagement))
        engagement.registerLaunch()   // 4회차 — 종료
        XCTAssertFalse(LeeoTrial.launches(3).isActive(engagement: engagement))
    }
}

// MARK: - 프리플라이트

final class LeeoPreflightTests: XCTestCase {

    private func codes<Spec: LeeoAppSpec>(_ spec: Spec.Type) -> Set<String> {
        Set(LeeoPreflight.audit(spec).map(\.code))
    }

    func testSoundSpecHasNoErrors() {
        XCTAssertTrue(LeeoPreflight.audit(FreemiumSpec.self).isReleasable)
        XCTAssertTrue(LeeoPreflight.audit(SubscriptionSpec.self).errors.isEmpty
                      || LeeoPreflight.audit(SubscriptionSpec.self).errors.allSatisfy { $0.code == "legal.noDeletionPath" })
    }

    func testAccountAppWithoutDeletionPathIsAnError() {
        // SubscriptionSpec 은 createsAccounts: true 인데 dataDeletionURL 이 없다
        XCTAssertTrue(codes(SubscriptionSpec.self).contains("legal.noDeletionPath"))
    }

    func testFreeSpecIsClean() {
        let issues = LeeoPreflight.audit(FreeSpec.self)
        XCTAssertTrue(issues.isReleasable, issues.map(\.message).joined(separator: "\n"))
    }

    func testBrokenSpecIsCaught() {
        let found = codes(BrokenSpec.self)
        XCTAssertTrue(found.contains("legal.insecureURL"))
        XCTAssertTrue(found.contains("feedback.badContainer"))
        XCTAssertTrue(found.contains("feedback.badEmail"))
        // 팔 물건은 있는데 살 이유(게이트)가 없는 상태
        XCTAssertTrue(found.contains("gate.noPath"))
        XCTAssertFalse(LeeoPreflight.audit(BrokenSpec.self).isReleasable)
    }

    func testMonetizationAndPaywallDisagreementIsCaught() {
        XCTAssertTrue(codes(ContradictorySpec.self).contains("paywall.contradiction"))
    }

    func testMissingAnalyticsSinkIsWarned() {
        XCTAssertTrue(codes(FreeSpec.self).contains("analytics.noSink"))
    }

    func testIssuesAreSortedBySeverity() {
        let issues = LeeoPreflight.audit(BrokenSpec.self)
        let severities = issues.map(\.severity)
        XCTAssertEqual(severities, severities.sorted())
    }
}

// MARK: - 매니페스트

final class LeeoManifestTests: XCTestCase {

    func testDerivedCapabilitiesFillWhatLeeoKitProvides() {
        let manifest = LeeoManifest(spec: FreemiumSpec.self)
        XCTAssertEqual(manifest.state(.feedbackChannel), .providedByLeeoKit)
        XCTAssertEqual(manifest.state(.reviewPrompt), .providedByLeeoKit)
        XCTAssertEqual(manifest.state(.policyLinks), .providedByLeeoKit)
        XCTAssertEqual(manifest.state(.purchaseReliability), .providedByLeeoKit)
        XCTAssertEqual(manifest.state(.appStoreListing), .implemented)
    }

    func testAppDeclarationWinsOverDerivedValue() {
        // FreemiumSpec 은 push 를 "해당 없음"으로 선언했다 — 자동 추론이 이를 덮어쓰면 안 된다
        guard case .notApplicable = LeeoManifest(spec: FreemiumSpec.self).state(.pushNotifications) else {
            return XCTFail("앱 선언이 파생값에 밀렸다")
        }
    }

    func testFreeAppMarksPurchaseReliabilityNotApplicable() {
        guard case .notApplicable = LeeoManifest(spec: FreeSpec.self).state(.purchaseReliability) else {
            return XCTFail("파는 게 없으면 결제 안정성은 '해당 없음'이어야 한다")
        }
    }

    func testUndeclaredItemsStayUnknown() {
        // "안 한 것"과 "안 해도 되는 것"을 섞지 않는다
        XCTAssertEqual(LeeoManifest(spec: FreeSpec.self).state(.automatedTests), .unknown)
    }

    func testCompletenessExcludesUnknownAndNotApplicable() {
        let manifest = LeeoManifest(spec: FreemiumSpec.self)
        let all = LeeoCapability.allCases.map { manifest.state($0) }
        let measured = all.filter(\.isMeasured).count
        let satisfied = all.filter(\.counts).count
        XCTAssertEqual(manifest.completeness, Int((Double(satisfied) / Double(measured) * 100).rounded()))
        // 판정 대상이 전체보다 적어야 한다 (미판단 항목이 분모에서 빠졌다는 뜻)
        XCTAssertLessThan(measured, LeeoCapability.allCases.count)
    }

    func testUnknownCountShrinksAsAppDeclares() {
        XCTAssertLessThan(LeeoManifest(spec: FreemiumSpec.self).unknownCount,
                          LeeoManifest(spec: FreeSpec.self).unknownCount)
    }

    func testEveryCapabilityBelongsToExactlyOneCategory() {
        let counted = LeeoCapabilityCategory.allCases
            .map { c in LeeoCapability.allCases.filter { $0.category == c }.count }
            .reduce(0, +)
        XCTAssertEqual(counted, LeeoCapability.allCases.count)
    }

    func testCategorySummariesCoverAllItems() {
        let manifest = LeeoManifest(spec: FreemiumSpec.self)
        XCTAssertEqual(manifest.categorySummaries.map(\.total).reduce(0, +), LeeoCapability.allCases.count)
    }

    func testJSONIsSerializableAndCarriesSchema() throws {
        let json = try LeeoManifest(spec: FreemiumSpec.self).jsonString()
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["schema"] as? String, LeeoManifest.schema)

        let money = try XCTUnwrap(parsed["monetization"] as? [String: Any])
        XCTAssertEqual(money["model"] as? String, "freemium")
        XCTAssertEqual(money["requiresPaywall"] as? Bool, true)

        let caps = try XCTUnwrap(parsed["capabilities"] as? [String: Any])
        XCTAssertEqual(caps.count, LeeoCapability.allCases.count)

        // 해당 없음 항목은 이유를 반드시 싣는다
        let push = try XCTUnwrap(caps["pushNotifications"] as? [String: Any])
        XCTAssertEqual(push["state"] as? String, "not_applicable")
        XCTAssertNotNil(push["reason"])
    }
}
