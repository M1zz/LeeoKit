//
//  LeeoReplyNoticeTests.swift
//  LeeoKitTests
//
//  답장 알림 규칙.
//
//  잠그는 계약:
//  1. 안 읽은 답장만 알린다. 읽은 것 · 답장 없는 것은 알리지 않는다.
//  2. 같은 답장으로 두 번 알리지 않는다. 답장 글이 바뀌면 다시 알린다.
//  3. 설정에 새 답장 배지가 있으면 앱 안 시트는 뜬다 — 로컬 알림으로 이미 알렸어도.
//  4. 앞으로 올 때마다 서버를 읽지 않는다 — 10분이 지나야 다시.
//

import XCTest
@testable import LeeoKit

final class LeeoReplyNoticeTests: XCTestCase {

    private func item(_ id: String, reply: String?, seen: Bool = false) -> LeeoSentFeedback {
        LeeoSentFeedback(id: id, type: "bug", excerpt: "e", sentAt: Date(),
                         reply: reply, repliedAt: reply == nil ? nil : Date(), replySeen: seen)
    }

    func testOnlyUnreadRepliesAreAnnounced() {
        let list = [item("a", reply: "고쳤어요"), item("b", reply: "확인", seen: true), item("c", reply: nil)]
        XCTAssertEqual(LeeoReplyNoticePolicy.unnotified(list, notified: [:]).map(\.id), ["a"])
    }

    func testSameReplyIsNotAnnouncedTwiceButEditedReplyIs() {
        let list = [item("a", reply: "고쳤어요")]
        XCTAssertTrue(LeeoReplyNoticePolicy.unnotified(list, notified: ["a": "고쳤어요"]).isEmpty)
        XCTAssertEqual(LeeoReplyNoticePolicy.unnotified(list, notified: ["a": "옛 답장"]).map(\.id), ["a"])
    }

    func testSheetFollowsSettingsBadgeEvenAfterLocalNotification() {
        let list = [item("a", reply: "고쳤어요"), item("b", reply: "확인", seen: true)]
        // 백그라운드 알림으로 a 를 이미 알렸어도, 아직 안 읽었으면 시트는 a 를 띄운다.
        XCTAssertTrue(LeeoReplyNoticePolicy.unnotified(list, notified: ["a": "고쳤어요"]).isEmpty)
        XCTAssertEqual(LeeoReplyNoticePolicy.presentable(list).map(\.id), ["a"])
    }

    func testForegroundCheckIsThrottled() {
        let now = Date()
        XCTAssertTrue(LeeoReplyNoticePolicy.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(LeeoReplyNoticePolicy.isDue(lastCheck: now.addingTimeInterval(-5 * 60), now: now))
        XCTAssertTrue(LeeoReplyNoticePolicy.isDue(lastCheck: now.addingTimeInterval(-11 * 60), now: now))
    }
}
