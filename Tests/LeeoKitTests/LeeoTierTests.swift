import XCTest
@testable import LeeoKit

final class LeeoTierTests: XCTestCase {
    private let plus = LeeoTier(id: "plus", name: "플러스",
                                productIDs: ["plus.yearly", "plus.lifetime"],
                                features: ["groupCreate", "insights"])
    private let pro = LeeoTier(id: "pro", name: "프로",
                               productIDs: ["pro.yearly", "pro.lifetime"],
                               features: ["map"])

    private var policy: LeeoGatePolicy {
        LeeoGatePolicy(freeLimits: ["groupCreate": 1], proOnly: ["legacy"], tiers: [plus, pro])
    }

    private func gate(owning products: Set<String>) -> LeeoGate {
        let index = policy.tierIndex(owning: products)
        return LeeoGate(policy: policy, hasPro: index != nil, isTrialActive: false, tierIndex: index)
    }

    func testFreeUserGetsFreeLimitThenPlus() {
        let free = gate(owning: [])
        XCTAssertEqual(free.evaluate("groupCreate", current: 0), .allowed)
        XCTAssertEqual(free.evaluate("groupCreate", current: 1),
                       .blocked(LeeoGateReason(key: "groupCreate", kind: .limitReached(limit: 1), requiredTier: plus)))
        XCTAssertEqual(free.evaluate("map"),
                       .blocked(LeeoGateReason(key: "map", kind: .proOnlyFeature, requiredTier: pro)))
        XCTAssertFalse(free.allows("legacy"))
        XCTAssertTrue(free.allows("unrelated"))
    }

    func testPlusOpensPlusButNotPro() {
        let plusGate = gate(owning: ["plus.lifetime"])
        XCTAssertEqual(plusGate.evaluate("groupCreate", current: 5), .allowed)
        XCTAssertTrue(plusGate.allows("insights"))
        XCTAssertTrue(plusGate.allows("legacy"))   // 등급과 상관없는 프로 전용은 어느 등급이든 연다
        XCTAssertFalse(plusGate.allows("map"))
        XCTAssertFalse(plusGate.isUnlocked)
        XCTAssertNil(plusGate.remaining("groupCreate", current: 3))
    }

    func testProOpensEverythingAndWinsOverPlus() {
        let both = gate(owning: ["plus.yearly", "pro.yearly"])
        XCTAssertEqual(both.tierIndex, 1)
        XCTAssertTrue(both.isUnlocked)
        XCTAssertTrue(both.allows("map"))
        XCTAssertTrue(both.allows("insights"))
    }

    func testProWithoutTierProductIsTopTier() {
        // 그랜드파더링 · 강제 해제처럼 등급 상품 없이 프로인 경우
        let gate = LeeoGate(policy: policy, hasPro: true, isTrialActive: false)
        XCTAssertEqual(gate.tierIndex, 1)
        XCTAssertTrue(gate.allows("map"))
    }

    func testTrialOpensEveryTier() {
        let gate = LeeoGate(policy: policy, hasPro: false, isTrialActive: true)
        XCTAssertTrue(gate.allows("map"))
        XCTAssertEqual(gate.evaluate("groupCreate", current: 9), .allowed)
    }

    func testNoTiersKeepsOldBehavior() {
        let old = LeeoGatePolicy(freeLimits: ["memo": 2], proOnly: ["export"])
        XCTAssertFalse(LeeoGate(policy: old, hasPro: false, isTrialActive: false).allows("export"))
        let pro = LeeoGate(policy: old, hasPro: true, isTrialActive: false)
        XCTAssertNil(pro.tierIndex)
        XCTAssertTrue(pro.isUnlocked)
        XCTAssertEqual(pro.evaluate("memo", current: 10), .allowed)
    }

    func testRequiredTierMessageNamesTheTier() {
        let reason = LeeoGateReason(key: "map", kind: .proOnlyFeature, requiredTier: pro)
        XCTAssertTrue(reason.localizedMessage.contains("프로"))
    }
}
