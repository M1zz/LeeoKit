//
//  LeeoFeedbackRepliesTests.swift
//  LeeoKitTests
//
//  보낸 의견 장부와 답장 합치기, 자동 첨부 정보 조립.
//
//  잠그는 계약:
//  1. 답장 레코드 이름은 `reply-<피드백 recordName>`. 바꾸면 이미 쓴 답장을 못 찾는다.
//  2. 같은 답장을 다시 읽어도 안 읽음으로 되살아나지 않는다(배지를 믿게 하려면).
//  3. 제안의 세 번째 질문은 선택이라 보내기를 막지 않는다.
//

import XCTest
@testable import LeeoKit

final class LeeoFeedbackRepliesTests: XCTestCase {

    private func item(_ id: String, daysAgo: Double = 0, reply: String? = nil, seen: Bool = false) -> LeeoSentFeedback {
        LeeoSentFeedback(id: id, type: "feature", excerpt: "e",
                         sentAt: Date().addingTimeInterval(-daysAgo * 86_400),
                         reply: reply, repliedAt: reply == nil ? nil : Date(), replySeen: seen)
    }

    func testReplyRecordNameIsStable() {
        XCTAssertEqual(LeeoFeedbackLedger.replyRecordName(forFeedback: "ABC-123"), "reply-ABC-123")
    }

    func testNewReplyIsUnread() {
        let merged = LeeoFeedbackLedger.merging(replies: ["a": ("고쳤어요", Date())], into: [item("a"), item("b")])
        XCTAssertEqual(merged.first { $0.id == "a" }?.reply, "고쳤어요")
        XCTAssertTrue(merged.first { $0.id == "a" }!.hasUnreadReply)
        XCTAssertFalse(merged.first { $0.id == "b" }!.hasUnreadReply)
    }

    func testSameReplyDoesNotResurrectBadge() {
        let seen = item("a", reply: "고쳤어요", seen: true)
        let merged = LeeoFeedbackLedger.merging(replies: ["a": ("고쳤어요", Date())], into: [seen])
        XCTAssertFalse(merged[0].hasUnreadReply)
    }

    func testEditedReplyIsUnreadAgain() {
        let seen = item("a", reply: "고쳤어요", seen: true)
        let merged = LeeoFeedbackLedger.merging(replies: ["a": ("다음 업데이트에 들어가요", Date())], into: [seen])
        XCTAssertTrue(merged[0].hasUnreadReply)
    }

    func testLedgerKeepsNewestFirstAndCapacity() {
        var list: [LeeoSentFeedback] = []
        for i in 0..<(LeeoFeedbackLedger.capacity + 5) {
            list = LeeoFeedbackLedger.inserting(item("\(i)"), into: list)
        }
        XCTAssertEqual(list.count, LeeoFeedbackLedger.capacity)
        XCTAssertEqual(list.first?.id, "\(LeeoFeedbackLedger.capacity + 4)")
    }

    func testOldFeedbackIsNotLookedUp() {
        let ids = LeeoFeedbackLedger.lookupIDs(in: [item("new", daysAgo: 3), item("old", daysAgo: 400)])
        XCTAssertEqual(ids, ["new"])
    }

    func testExcerptFlattensAndTrims() {
        let long = "어떤 기능이 있으면 좋겠나요?\n세로로 보고 싶어요\n\n" + String(repeating: "가", count: 200)
        let e = LeeoFeedbackLedger.excerpt(of: long)
        XCTAssertFalse(e.contains("\n"))
        XCTAssertTrue(e.hasSuffix("…"))
        XCTAssertEqual(e.count, 121)
    }

    // MARK: - 자동 첨부 정보

    func testDeviceInfoAppendsExtraLinesAndDropsBlanks() {
        let info = LeeoFeedbackService.composeDeviceInfo(base: "App 1.0 (3) | iPhone17,2 | iOS 26.1",
                                                         extra: ["보낸 곳: 템플릿 채우기", "  ", "Pro"])
        XCTAssertEqual(info, "App 1.0 (3) | iPhone17,2 | iOS 26.1\n보낸 곳: 템플릿 채우기\nPro")
    }

    func testHardwareIdentifierIsNotGenericModel() {
        // "iPhone" 만으로는 재현할 기기를 고를 수 없다. 식별자에는 쉼표나 숫자가 들어간다.
        let id = LeeoFeedbackService.hardwareIdentifier()
        XCTAssertFalse(id.isEmpty)
        XCTAssertNotEqual(id, "iPhone")
    }

    // MARK: - 제안의 세 번째 질문

    func testFeatureWorkaroundIsOptional() {
        let prompts = LeeoFeedbackType.feature.prompts
        XCTAssertEqual(prompts.map(\.id), ["wish", "usecase", "workaround"])
        XCTAssertLessThanOrEqual(prompts.count, 3, "칸은 셋을 넘기지 않는다")
        XCTAssertTrue(LeeoFeedbackComposer.canSend(type: .feature,
                                                   answers: ["wish": "세로 목록", "usecase": "긴 값"],
                                                   note: ""))
    }
}
