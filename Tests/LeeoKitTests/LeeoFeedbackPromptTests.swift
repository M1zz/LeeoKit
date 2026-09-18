//
//  LeeoFeedbackPromptTests.swift
//  LeeoKitTests
//
//  나눠 묻고 한 글로 조립하는 규칙을 못박는다.
//  받는 쪽은 `message` 한 필드뿐이라, 조립이 깨지면 무엇을 물었는지가 사라진다.
//

import XCTest
@testable import LeeoKit

final class LeeoFeedbackPromptTests: XCTestCase {

    func testBugAsksWhenAndSymptom() {
        let ids = LeeoFeedbackType.bug.prompts.map(\.id)
        XCTAssertEqual(ids, ["when", "symptom", "expected"])
        // 언제·증상은 반드시, 기대한 결과는 선택.
        XCTAssertEqual(LeeoFeedbackType.bug.prompts.filter(\.isRequired).map(\.id), ["when", "symptom"])
    }

    func testFeatureAsksForUseCase() {
        XCTAssertTrue(LeeoFeedbackType.feature.prompts.contains { $0.id == "usecase" })
        XCTAssertTrue(LeeoFeedbackType.improvement.prompts.contains { $0.id == "usecase" })
    }

    func testQuestionKeepsFreeFormOnly() {
        XCTAssertTrue(LeeoFeedbackType.question.prompts.isEmpty)
        XCTAssertTrue(LeeoFeedbackType.other.prompts.isEmpty)
    }

    func testCannotSendUntilRequiredAnswered() {
        XCTAssertFalse(LeeoFeedbackComposer.canSend(type: .bug, answers: [:], note: ""))
        // 자유 입력만 채워도 버그는 못 보낸다 - 그게 지금까지 한 줄만 오던 이유다.
        XCTAssertFalse(LeeoFeedbackComposer.canSend(type: .bug, answers: [:], note: "안 돼요"))
        XCTAssertTrue(LeeoFeedbackComposer.canSend(
            type: .bug, answers: ["when": "아침", "symptom": "앱이 닫혀요"], note: ""))
    }

    func testQuestionSendsWithNoteAlone() {
        XCTAssertFalse(LeeoFeedbackComposer.canSend(type: .question, answers: [:], note: "  "))
        XCTAssertTrue(LeeoFeedbackComposer.canSend(type: .question, answers: [:], note: "어떻게 쓰나요"))
    }

    func testComposeKeepsLabelsWithAnswers() {
        let text = LeeoFeedbackComposer.compose(
            type: .bug,
            answers: ["when": "오늘 아침", "symptom": "앱이 닫혔어요", "expected": "  "],
            note: "급해요")
        XCTAssertTrue(text.contains(LeeoFeedbackType.bug.prompts[0].label))
        XCTAssertTrue(text.contains("오늘 아침"))
        XCTAssertTrue(text.contains("앱이 닫혔어요"))
        // 빈 칸은 꼬리표도 남기지 않는다.
        XCTAssertFalse(text.contains(LeeoFeedbackType.bug.prompts[2].label))
        XCTAssertTrue(text.contains("급해요"))
    }

    /// 유형을 옮겨 다녀도 그 유형의 칸만 나간다. 남아 있는 답이 섞이면 받는 쪽이 헷갈린다.
    func testComposeReadsOnlyCurrentTypeAnswers() {
        let text = LeeoFeedbackComposer.compose(
            type: .question,
            answers: ["when": "아침", "symptom": "닫혀요"],
            note: "이건 질문이에요")
        XCTAssertEqual(text, "이건 질문이에요")
    }

    func testScreenshotInvitationByType() {
        XCTAssertTrue(LeeoFeedbackType.bug.invitesScreenshot)
        XCTAssertTrue(LeeoFeedbackType.improvement.invitesScreenshot)
        XCTAssertFalse(LeeoFeedbackType.question.invitesScreenshot)
    }

    /// 사진 필드는 앱이 받기로 한 경우에만 쓴다. 안 그러면 Production 에서 레코드가 거부된다.
    func testScreenshotFieldsOnlyWhenAccepted() throws {
        let shot = try XCTUnwrap(LeeoFeedbackService.writeTemporary([Data([0xFF, 0xD8, 0xFF])]).first)
        defer { try? FileManager.default.removeItem(at: shot) }

        let off = LeeoFeedbackConfig(containerIdentifier: "iCloud.test", acceptsScreenshots: false)
        let recordOff = LeeoFeedbackService.makeRecord(
            config: off, type: "bug", message: "m", deviceInfo: "d", screenshots: [shot])
        XCTAssertNil(recordOff["screenshot1"])

        let on = LeeoFeedbackConfig(containerIdentifier: "iCloud.test", acceptsScreenshots: true)
        let recordOn = LeeoFeedbackService.makeRecord(
            config: on, type: "bug", message: "m", deviceInfo: "d", screenshots: [shot])
        XCTAssertNotNil(recordOn["screenshot1"])
        XCTAssertNil(recordOn["screenshot2"])
    }
}
