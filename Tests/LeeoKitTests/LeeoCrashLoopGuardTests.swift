//
//  LeeoCrashLoopGuardTests.swift
//  LeeoKitTests
//
//  크래시 루프 가드: 순수 전이 규칙과, 저장소를 붙였을 때 "프로세스가 바뀌며 죽는" 흐름.
//  서로 다른 프로세스는 세션 값을 바꿔 흉내 낸다. 각 테스트는 고유 suite 를 쓴다.
//

import XCTest
@testable import LeeoKit

final class LeeoCrashLoopGuardTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "leeo.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// 새 프로세스 하나 = 새 세션 값을 가진 가드 하나.
    private func process(_ session: String, threshold: Int = 2) -> LeeoCrashLoopGuard {
        LeeoCrashLoopGuard(name: "keyboard", defaults: defaults,
                           threshold: threshold, survivalDelay: 0, session: session)
    }

    // MARK: - 순수 규칙

    func testPolicyCountsOnlyAnotherSessionsMarker() {
        var s = LeeoCrashLoopState()
        var r = LeeoCrashLoopPolicy.begin(s, session: "A", threshold: 2)
        XCTAssertFalse(r.safeMode)
        XCTAssertEqual(r.state.consecutiveIncomplete, 0, "첫 실행은 셀 것이 없다")
        s = r.state

        r = LeeoCrashLoopPolicy.begin(s, session: "A", threshold: 2)
        XCTAssertEqual(r.state.consecutiveIncomplete, 0, "같은 프로세스의 재호출은 죽음이 아니다")

        r = LeeoCrashLoopPolicy.begin(s, session: "B", threshold: 2)
        XCTAssertEqual(r.state.consecutiveIncomplete, 1, "다른 세션의 표식이 남았다 = 직전 실행이 못 끝났다")
        XCTAssertEqual(r.state.unreportedIncomplete, 1)
        XCTAssertEqual(r.state.inFlightSession, "B")
    }

    func testPolicySucceedClearsStreakButKeepsUnreported() {
        let s = LeeoCrashLoopState(inFlightSession: "B", consecutiveIncomplete: 3, unreportedIncomplete: 3)
        let n = LeeoCrashLoopPolicy.succeed(s, session: "B")
        XCTAssertNil(n.inFlightSession)
        XCTAssertEqual(n.consecutiveIncomplete, 0)
        XCTAssertEqual(n.unreportedIncomplete, 3, "보고 몫은 보낼 때만 준다")
    }

    func testPolicySucceedLeavesOtherSessionsMarker() {
        let s = LeeoCrashLoopState(inFlightSession: "C", consecutiveIncomplete: 1)
        let n = LeeoCrashLoopPolicy.succeed(s, session: "B")
        XCTAssertEqual(n.inFlightSession, "C", "그 사이 켜는 중인 다른 프로세스의 표식은 남긴다")
        XCTAssertEqual(n.consecutiveIncomplete, 0)
    }

    // MARK: - 저장소를 붙인 흐름

    func testConsecutiveFailuresEnterSafeMode() {
        XCTAssertFalse(process("1").beginLaunch())            // 죽음 (표식 남김)
        XCTAssertFalse(process("2").beginLaunch(), "한 번은 사고일 수 있다")  // 또 죽음
        let third = process("3")
        XCTAssertTrue(third.beginLaunch(), "연속 2회면 세이프 모드")
        XCTAssertTrue(third.isInSafeMode)
        XCTAssertEqual(third.consecutiveIncompleteLaunches, 2)
        XCTAssertEqual(third.unreportedIncompleteLaunches, 2)
    }

    func testSuccessClearsAndSafeModeExpiresNextLaunch() {
        process("1").beginLaunch()
        process("2").beginLaunch()
        let safe = process("3")
        XCTAssertTrue(safe.beginLaunch())
        safe.markLaunchSucceeded()
        XCTAssertTrue(safe.isInSafeMode, "이 프로세스 안에서는 화면을 도중에 바꾸지 않는다")
        XCTAssertEqual(safe.consecutiveIncompleteLaunches, 0)

        let next = process("4")
        XCTAssertFalse(next.beginLaunch(), "세이프 모드로 무사히 떴으면 다음은 평소대로")
        XCTAssertFalse(next.isInSafeMode)
    }

    func testNormalLaunchesNeverCount() {
        for i in 0..<5 {
            let g = process("\(i)")
            XCTAssertFalse(g.beginLaunch())
            g.markLaunchSucceeded()
        }
        XCTAssertEqual(process("x").consecutiveIncompleteLaunches, 0)
        XCTAssertEqual(process("x").unreportedIncompleteLaunches, 0)
    }

    func testThresholdIsConfigurable() {
        XCTAssertFalse(process("1", threshold: 1).beginLaunch())
        XCTAssertTrue(process("2", threshold: 1).beginLaunch(), "문턱 1 이면 한 번 죽고 바로 세이프 모드")

        let other = UserDefaults(suiteName: suite + ".3")!
        defer { other.removePersistentDomain(forName: suite + ".3") }
        func p(_ s: String) -> LeeoCrashLoopGuard {
            LeeoCrashLoopGuard(name: "share", defaults: other, threshold: 3, survivalDelay: 0, session: s)
        }
        XCTAssertFalse(p("1").beginLaunch())
        XCTAssertFalse(p("2").beginLaunch())
        XCTAssertFalse(p("3").beginLaunch())
        XCTAssertTrue(p("4").beginLaunch(), "문턱 3 이면 세 번째 실패 뒤에 세이프 모드")
    }

    func testNamesAreIsolated() {
        LeeoCrashLoopGuard(name: "keyboard", defaults: defaults, threshold: 2, survivalDelay: 0, session: "1").beginLaunch()
        let share = LeeoCrashLoopGuard(name: "share", defaults: defaults, threshold: 2, survivalDelay: 0, session: "2")
        share.beginLaunch()
        XCTAssertEqual(share.consecutiveIncompleteLaunches, 0, "다른 이름의 표식은 내 실패가 아니다")
    }

    func testTakeUnreportedAndReset() {
        process("1").beginLaunch()
        let g = process("2")
        g.beginLaunch()
        XCTAssertEqual(g.takeUnreportedIncompleteLaunches(), 1)
        XCTAssertEqual(g.unreportedIncompleteLaunches, 0)
        XCTAssertEqual(g.consecutiveIncompleteLaunches, 1, "가져가도 연속 횟수는 그대로")

        process("3").beginLaunch()
        g.reset()
        XCTAssertEqual(g.consecutiveIncompleteLaunches, 0)
        XCTAssertFalse(g.isInSafeMode)
        XCTAssertFalse(process("4").beginLaunch(), "초기화 뒤에는 표식도 없다")
    }
}
