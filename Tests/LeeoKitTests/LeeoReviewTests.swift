//
//  LeeoReviewTests.swift
//  LeeoKitTests
//
//  사용량 트래커(LeeoEngagement)와 리뷰 게이팅(LeeoReviewRequest.shouldRequest) 로직 검증.
//  각 테스트는 고유 suite 를 써서 .standard 를 오염시키지 않는다.
//

import XCTest
@testable import LeeoKit

final class LeeoReviewTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var eng: LeeoEngagement!

    override func setUp() {
        super.setUp()
        suite = "leeo.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        eng = LeeoEngagement(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testLaunchAndEventCounting() {
        XCTAssertEqual(eng.launchCount, 0)
        XCTAssertEqual(eng.registerLaunch(), 1)
        XCTAssertEqual(eng.registerLaunch(), 2)
        XCTAssertEqual(eng.launchCount, 2)
        XCTAssertEqual(eng.registerSignificantEvent(), 1)
        XCTAssertEqual(eng.significantEventCount, 1)
    }

    func testShouldRequestBlocksUntilThresholdsMet() {
        let policy = LeeoReviewPolicy(minLaunches: 3, minDaysSinceInstall: 0,
                                      minSignificantEvents: 1, cooldownDays: 120)
        eng.registerSignificantEvent()
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: policy, engagement: eng),
                       "실행 횟수 미달이면 요청하지 않아야 한다")
        eng.registerLaunch(); eng.registerLaunch(); eng.registerLaunch()
        XCTAssertTrue(LeeoReviewRequest.shouldRequest(policy: policy, engagement: eng),
                      "조건을 모두 만족하면 요청 가능해야 한다")
    }

    func testDaysSinceInstallGate() {
        let policy = LeeoReviewPolicy(minLaunches: 0, minDaysSinceInstall: 5, minSignificantEvents: 0)
        _ = eng.installDate   // 오늘로 설치 시각 고정
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: policy, engagement: eng),
                       "설치 직후에는 경과일 조건으로 막혀야 한다")
        // 설치일을 10일 전으로 되돌린다 (내부 키에 직접 기록)
        let past = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        defaults.set(past, forKey: "leeo.engagement.installDate")
        XCTAssertTrue(LeeoReviewRequest.shouldRequest(policy: policy, engagement: eng),
                      "설치 후 충분히 지나면 요청 가능해야 한다")
    }

    func testOncePerVersionAndCooldownAfterMarkRequested() {
        let policy = LeeoReviewPolicy(minLaunches: 0, minDaysSinceInstall: 0,
                                      minSignificantEvents: 0, cooldownDays: 120, oncePerVersion: true)
        XCTAssertTrue(LeeoReviewRequest.shouldRequest(policy: policy, engagement: eng))
        LeeoReviewRequest.markRequested(engagement: eng)
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: policy, engagement: eng),
                       "한 번 요청했으면 같은 버전/쿨다운 안에서는 다시 묻지 않아야 한다")
    }

    // MARK: - "나중에"

    private let openPolicy = LeeoReviewPolicy(minLaunches: 0, minDaysSinceInstall: 0, minSignificantEvents: 0,
                                              cooldownDays: 120, oncePerVersion: true,
                                              laterDays: 7, maxLaterPerVersion: 3)

    /// 미룬 시각을 과거로 돌린다 (내부 키에 직접 기록)
    private func ageLater(days: Int) {
        let past = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        defaults.set(past, forKey: "leeo.engagement.lastLater.review")
    }

    func testLaterDoesNotBurnVersionOrCooldown() {
        // 띄우는 순간 기록 → 사용자가 "나중에"
        LeeoReviewRequest.markRequested(engagement: eng)
        LeeoReviewRequest.markLater(policy: openPolicy, engagement: eng)
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: openPolicy, engagement: eng),
                       "미룬 직후에는 다시 묻지 않아야 한다")
        ageLater(days: 8)
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: openPolicy, engagement: eng),
                       "미룬 뒤 새로 해낸 일이 없으면 기간이 지나도 묻지 않아야 한다")
        eng.registerSignificantEvent()
        XCTAssertTrue(LeeoReviewRequest.shouldRequest(policy: openPolicy, engagement: eng),
                      "기간이 지나고 새 긍정 행동이 있으면 같은 버전에서도 다시 물을 수 있어야 한다")
    }

    func testLaterWaitsForLaterDays() {
        LeeoReviewRequest.markLater(policy: openPolicy, engagement: eng)
        eng.registerSignificantEvent()
        ageLater(days: 3)
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: openPolicy, engagement: eng),
                       "laterDays 가 지나기 전에는 묻지 않아야 한다")
    }

    func testTooManyLatersEndsTheVersion() {
        for _ in 0..<3 {
            LeeoReviewRequest.markRequested(engagement: eng)
            LeeoReviewRequest.markLater(policy: openPolicy, engagement: eng)
            ageLater(days: 8)
            eng.registerSignificantEvent()
        }
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: openPolicy, engagement: eng),
                       "한 버전에서 maxLaterPerVersion 번 미루면 그 버전에선 더 묻지 않아야 한다")
    }

    func testAnsweringStillBlocksForVersionAndCooldown() {
        LeeoReviewRequest.markLater(policy: openPolicy, engagement: eng)
        ageLater(days: 8)
        eng.registerSignificantEvent()
        LeeoReviewRequest.markRequested(engagement: eng)   // 이번엔 답했다
        XCTAssertFalse(LeeoReviewRequest.shouldRequest(policy: openPolicy, engagement: eng),
                       "답한 뒤에는 기존처럼 버전·쿨다운으로 막혀야 한다")
    }

    func testResetClearsAllCounters() {
        eng.registerLaunch(); eng.registerSignificantEvent()
        eng.reset()
        XCTAssertEqual(eng.launchCount, 0)
        XCTAssertEqual(eng.significantEventCount, 0)
    }
}
