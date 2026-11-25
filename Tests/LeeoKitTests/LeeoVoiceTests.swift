//
//  LeeoVoiceTests.swift
//  LeeoKitTests
//
//  한 문장 의견을 언제 누구에게 묻는가. 너무 자주 묻는 버그는 모든 앱 사용자를 동시에 귀찮게 한다.
//

import XCTest
@testable import LeeoKit

final class LeeoVoiceTests: XCTestCase {

    private var suite: String!
    private var engagement: LeeoEngagement!
    private let day: TimeInterval = 86_400

    override func setUp() {
        suite = "leeo.voice.tests.\(UUID().uuidString)"
        engagement = LeeoEngagement(suiteName: suite)
        // 열흘 전에 설치했다.
        UserDefaults(suiteName: suite)!.set(Date().addingTimeInterval(-10 * day), forKey: "leeo.engagement.installDate")
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func use(launches: Int, events: Int) {
        for _ in 0..<launches { engagement.registerLaunch() }
        for _ in 0..<events { engagement.registerSignificantEvent() }
    }

    func testNewUserIsNotAsked() {
        use(launches: 2, events: 5)
        XCTAssertNil(LeeoVoice.nextQuestion(engagement: engagement))
    }

    func testEngagedUserGetsUsefulFirst() {
        use(launches: 5, events: 3)
        XCTAssertEqual(LeeoVoice.nextQuestion(engagement: engagement), .useful)
    }

    func testAppWithoutEventsAsksAfterManyLaunches() {
        use(launches: 9, events: 0)
        XCTAssertNil(LeeoVoice.nextQuestion(engagement: engagement))
        use(launches: 1, events: 0)
        XCTAssertEqual(LeeoVoice.nextQuestion(engagement: engagement), .useful)
    }

    func testWaitsDaysAndNewEventsThenRotates() {
        use(launches: 5, events: 3)
        let now = Date()
        LeeoVoice.markShown(.useful, engagement: engagement, now: now)
        // 바로 다음에는 묻지 않는다.
        XCTAssertNil(LeeoVoice.nextQuestion(engagement: engagement, now: now.addingTimeInterval(day)))
        // 닷새가 지나도 새로 해낸 일이 없으면 묻지 않는다.
        let later = now.addingTimeInterval(6 * day)
        XCTAssertNil(LeeoVoice.nextQuestion(engagement: engagement, now: later))
        use(launches: 0, events: 2)
        XCTAssertEqual(LeeoVoice.nextQuestion(engagement: engagement, now: later), .unmet)
        LeeoVoice.markShown(.unmet, engagement: engagement, now: later)
        use(launches: 0, events: 2)
        XCTAssertEqual(LeeoVoice.nextQuestion(engagement: engagement, now: later.addingTimeInterval(6 * day)), .wish)
    }

    func testNotRightAfterReviewPrompt() {
        use(launches: 5, events: 3)
        LeeoReviewRequest.markRequested(engagement: engagement)
        XCTAssertNil(LeeoVoice.nextQuestion(engagement: engagement))
        XCTAssertEqual(LeeoVoice.nextQuestion(engagement: engagement, now: Date().addingTimeInterval(3 * day)), .useful)
    }

    func testRepeatedSkipsGoQuietForAMonth() {
        use(launches: 5, events: 3)
        let now = Date()
        for _ in 0..<3 { LeeoVoice.markSkipped(engagement: engagement, now: now) }
        XCTAssertNil(LeeoVoice.nextQuestion(engagement: engagement, now: now.addingTimeInterval(20 * day)))
        XCTAssertNotNil(LeeoVoice.nextQuestion(engagement: engagement, now: now.addingTimeInterval(31 * day)))
    }

    func testQuestionTypesStayStable() {
        // 허브가 이 값으로 묶는다 — 바뀌면 지난 답과 새 답이 갈라진다.
        XCTAssertEqual(LeeoVoiceQuestion.allCases.map(\.rawValue), ["voice.useful", "voice.unmet", "voice.wish"])
    }

    // MARK: - 함께 보내는 사정 (허브가 이 줄 이름을 읽는다)

    func testUsefulAnswerCarriesLevelInstallDaysAndPaid() {
        let lines = LeeoVoice.contextLines(question: .useful, usefulness: 3, daysSinceInstall: 12, isPaid: true)
        XCTAssertEqual(lines, ["질문: useful", "쓸모: 3/3", "설치: 12일", "유료: 예"])
    }

    func testOtherQuestionsNeverCarryUsefulness() {
        let lines = LeeoVoice.contextLines(question: .wish, usefulness: 2, daysSinceInstall: 0, isPaid: false)
        XCTAssertEqual(lines, ["질문: wish", "설치: 0일", "유료: 아니오"])
    }

    func testNoPaywallMeansNoPaidLineAndBadLevelIsDropped() {
        let lines = LeeoVoice.contextLines(question: .useful, usefulness: 7, daysSinceInstall: -3, isPaid: nil)
        XCTAssertEqual(lines, ["질문: useful", "설치: 0일"])
    }
}
