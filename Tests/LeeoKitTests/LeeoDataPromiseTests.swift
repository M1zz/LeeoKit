//
//  LeeoDataPromiseTests.swift
//  LeeoKitTests
//
//  **말과 코드가 같다.** '앱을 더 좋게 만들 데이터 보내기' 를 끄면 정말로 아무것도 나가지 않는다.
//  전송은 CloudKit 이라, 끈 상태에서는 iCloud 를 묻기도 전에 돌아오는지(false)를 본다.
//

import XCTest
@testable import LeeoKit

final class LeeoDataPromiseTests: XCTestCase {
    private var saved: Any?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.object(forKey: LeeoImprovementData.key)
        UserDefaults.standard.removeObject(forKey: LeeoImprovementData.key)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: LeeoImprovementData.key) }
        else { UserDefaults.standard.removeObject(forKey: LeeoImprovementData.key) }
        super.tearDown()
    }

    func test_처음엔_켜져_있다() {
        XCTAssertTrue(LeeoImprovementData.isOn)
    }

    func test_끄면_꺼진_채로_남는다() {
        LeeoImprovementData.isOn = false
        XCTAssertFalse(LeeoImprovementData.isOn)
        XCTAssertEqual(UserDefaults.standard.object(forKey: LeeoImprovementData.key) as? Bool, false)
    }

    func test_끄면_사용_기록을_보내지_않는다() async {
        LeeoImprovementData.isOn = false
        let suite = "leeo.test.\(UUID().uuidString)"
        let reporter = LeeoUsageReporter(
            config: LeeoFeedbackConfig(containerIdentifier: "iCloud.test", appIdentifier: "test"),
            appName: "Test", defaults: UserDefaults(suiteName: suite)!)
        let sent = await reporter.logEvent("merge")
        XCTAssertFalse(sent)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func test_앱이_적지_않으면_빈_약속이다() {
        let promise = LeeoDataPromise()
        XCTAssertTrue(promise.onDevice.isEmpty)
        XCTAssertTrue(promise.inICloud.isEmpty)
        XCTAssertFalse(promise.worksOffline)
    }
}
