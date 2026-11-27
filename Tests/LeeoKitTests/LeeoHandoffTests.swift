import XCTest
@testable import LeeoKit

final class LeeoHandoffTests: XCTestCase {

    func testRereminderTimerDeepLinkCarriesValuesAndSource() throws {
        let handoff = LeeoHandoff.rereminderTimer(minutes: 10, title: "계좌번호 보내기")
        let url = try XCTUnwrap(handoff.deepLink(from: "com.Ysoup.TokenMemo"))
        XCTAssertEqual(url.scheme, "com.xa.toki")
        XCTAssertEqual(url.host, "timer")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "minutes" }?.value, "10")
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "계좌번호 보내기")
        XCTAssertEqual(items.first { $0.name == "from" }?.value, "com.Ysoup.TokenMemo")
    }

    func testMinutesAreClampedAndBlankTitleDropped() {
        XCTAssertEqual(LeeoHandoff.rereminderTimer(minutes: 0).parameters["minutes"], "1")
        XCTAssertEqual(LeeoHandoff.rereminderTimer(minutes: 99_999).parameters["minutes"], "1440")
        XCTAssertNil(LeeoHandoff.rereminderTimer(minutes: 5, title: "   ").parameters["title"])
    }

    func testUnknownActionIsRefused() {
        XCTAssertNil(LeeoHandoff(target: .rereminder, action: "alarm"))
    }

    func testReceiverReadsWhatSenderWrote() throws {
        let sent = LeeoHandoff.rereminderTimer(minutes: 25, title: "Focus & rest")
        let url = try XCTUnwrap(sent.deepLink(from: "com.Ysoup.TokenMemo"))
        let request = try XCTUnwrap(LeeoHandoffRequest(url: url, for: .rereminder, track: false))
        XCTAssertEqual(request.action, "timer")
        XCTAssertEqual(request.int("minutes"), 25)
        XCTAssertEqual(request.parameters["title"], "Focus & rest")
        XCTAssertEqual(request.source, "com.Ysoup.TokenMemo")
        XCTAssertNil(request.parameters["from"], "보낸 앱은 값이 아니라 source 로만")
    }

    func testReceiverIgnoresOtherSchemesAndUnknownActions() {
        XCTAssertNil(LeeoHandoffRequest(url: URL(string: "clipkeyboard://timer?minutes=5")!, for: .rereminder, track: false))
        XCTAssertNil(LeeoHandoffRequest(url: URL(string: "com.xa.toki://paywall")!, for: .rereminder, track: false))
    }

    func testClipLinkCarriesActionAndIsReadBack() throws {
        let target = LeeoHandoffTarget(familyID: "rereminder", scheme: "com.xa.toki",
                                       appClipURL: URL(string: "https://example.com/clip/"), actions: ["timer"])
        let handoff = try XCTUnwrap(LeeoHandoff(target: target, action: "timer", parameters: ["minutes": "3"]))
        let url = try XCTUnwrap(handoff.clipLink(from: "x"))
        XCTAssertEqual(url.host, "example.com")
        let request = try XCTUnwrap(LeeoHandoffRequest(url: url, for: target, track: false))
        XCTAssertEqual(request.action, "timer")
        XCTAssertEqual(request.int("minutes"), 3)
        XCTAssertNil(request.parameters["action"])
    }

    func testNoClipMeansNoClipLink() {
        XCTAssertNil(LeeoHandoff.rereminderTimer(minutes: 5).clipLink())
    }

    func testRoute() {
        XCTAssertEqual(LeeoHandoffRoute.decide(installed: true, hasClip: true), .app)
        XCTAssertEqual(LeeoHandoffRoute.decide(installed: false, hasClip: true), .appClip)
        XCTAssertEqual(LeeoHandoffRoute.decide(installed: false, hasClip: false), .store)
    }

    func testEveryTargetIsInTheFamilyCatalog() {
        for target in LeeoHandoffTarget.all {
            XCTAssertNotNil(target.app, "\(target.familyID) 가 LeeoFamilyCatalog 에 없다")
            XCTAssertNotNil(target.storeURL)
            XCTAssertFalse(target.actions.isEmpty)
        }
    }
}
