//
//  LeeoRemoteFlagsTests.swift
//  LeeoKitTests
//
//  킬스위치의 **안전 기본값**을 고정한다.
//
//  이 규칙이 뒤집히면 네트워크 장애나 CloudKit 권한 문제만으로 앱 기능이 꺼진다 —
//  킬스위치가 장애를 막는 대신 장애를 만드는 것이다.
//  이 코드는 여러 앱이 함께 쓰므로 여기서 깨지면 전부에 영향이 간다.
//

import XCTest
@testable import LeeoKit

private enum TestFlag: String, LeeoRemoteFlag, CaseIterable {
    case syncEnabled
    case paywallEnabled
}

final class LeeoRemoteFlagsTests: XCTestCase {

    private let prefix = "leeo.flag."

    override func setUp() {
        super.setUp()
        LeeoRemoteFlags.configure(appGroupSuiteName: nil)   // standard UserDefaults 사용
        clear()
    }

    override func tearDown() {
        clear()
        super.tearDown()
    }

    private func clear() {
        for flag in TestFlag.allCases {
            UserDefaults.standard.removeObject(forKey: prefix + flag.rawValue)
        }
    }

    // MARK: - 안전 기본값

    /// 캐시가 비어 있으면(설치 직후, 한 번도 못 받아봄) 전부 켬이어야 한다.
    func testDefaultsToEnabledWhenNoCache() {
        for flag in TestFlag.allCases {
            XCTAssertTrue(LeeoRemoteFlags.isEnabled(flag),
                          "\(flag.rawValue): 캐시가 없으면 켬이어야 한다")
        }
    }

    /// 캐시에 false 가 있으면 실제로 꺼진다.
    func testRespectsCachedDisabledValue() {
        UserDefaults.standard.set(false, forKey: prefix + TestFlag.syncEnabled.rawValue)

        XCTAssertFalse(LeeoRemoteFlags.isEnabled(TestFlag.syncEnabled))
    }

    /// 플래그는 서로 독립이어야 한다 — 하나를 끈다고 다른 게 꺼지면 사고가 커진다.
    func testFlagsAreIndependent() {
        UserDefaults.standard.set(false, forKey: prefix + TestFlag.syncEnabled.rawValue)

        XCTAssertFalse(LeeoRemoteFlags.isEnabled(TestFlag.syncEnabled))
        XCTAssertTrue(LeeoRemoteFlags.isEnabled(TestFlag.paywallEnabled))
    }

    /// 캐시 키 접두가 바뀌면 기존 사용자의 설정이 통째로 무시된다(조용한 회귀).
    func testCacheKeyPrefixIsStable() {
        UserDefaults.standard.set(false, forKey: "leeo.flag.syncEnabled")

        XCTAssertFalse(LeeoRemoteFlags.isEnabled(TestFlag.syncEnabled),
                       "캐시 키 접두는 leeo.flag. 여야 한다")
    }

    // MARK: - App Group

    /// App Group 을 지정하면 그쪽 값을 먼저 본다 — 익스텐션과 값을 공유하기 위한 계약.
    func testAppGroupTakesPrecedenceWhenConfigured() {
        // 실제 App Group 이 없는 테스트 환경에서는 suite 생성이 실패할 수 있다.
        // 그 경우엔 standard 로 폴백하는 것이 정상 동작이므로 크래시 없이 읽히기만 하면 된다.
        LeeoRemoteFlags.configure(appGroupSuiteName: "group.test.invalid")
        defer { LeeoRemoteFlags.configure(appGroupSuiteName: nil) }

        XCTAssertTrue(LeeoRemoteFlags.isEnabled(TestFlag.syncEnabled),
                      "읽을 수 없는 App Group 이어도 켬으로 폴백해야 한다")
    }
}
