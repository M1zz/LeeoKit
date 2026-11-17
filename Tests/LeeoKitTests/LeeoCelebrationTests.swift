//
//  LeeoCelebrationTests.swift
//  LeeoKitTests
//
//  축하 · 감사: 방금 유료가 되면 축하, 이미 유료면 등급마다 한 번 감사, 무료면 한 번 인사. 같은 일로 두 번 띄우지 않는다.
//

import XCTest
@testable import LeeoKit

@MainActor
final class LeeoCelebrationTests: XCTestCase {

    private func make() -> LeeoCelebration {
        let name = "celebration.\(UUID().uuidString)"
        return LeeoCelebration(defaults: UserDefaults(suiteName: name)!)
    }

    func test_방금_유료가_되면_축하한다_한_실행에_한_번() {
        let c = make()
        c.noteOwned(tierID: "pro", tierName: "Pro", justNow: true)
        XCTAssertEqual(c.current, .upgraded(tier: "Pro"))
        c.dismiss()
        // 앱의 다른 스토어가 같은 결제를 또 알려도 다시 띄우지 않는다
        c.noteOwned(tierID: "pro", tierName: "Pro", justNow: true)
        XCTAssertNil(c.current)
    }

    func test_이미_유료면_등급마다_한_번_감사한다() {
        let c = make()
        c.noteOwned(tierID: "plus", tierName: "Plus", justNow: false)
        XCTAssertEqual(c.current, .paidThanks(tier: "Plus"))
        c.dismiss()
        c.noteOwned(tierID: "plus", tierName: "Plus", justNow: false)
        XCTAssertNil(c.current)
        // Pro 로 오르면 그건 새 일이다
        c.noteOwned(tierID: "pro", tierName: "Pro", justNow: true)
        XCTAssertEqual(c.current, .upgraded(tier: "Pro"))
    }

    func test_축하가_감사보다_앞선다() {
        let c = make()
        c.noteOwned(tierID: "pro", tierName: "Pro", justNow: true)
        c.noteOwned(tierID: "plus", tierName: "Plus", justNow: false)
        XCTAssertEqual(c.current, .upgraded(tier: "Pro"))
    }

    func test_무료_사용자는_한_번_인사한다() {
        let c = make()
        c.welcomeOnce(appName: "골드위크", firstTime: true)
        XCTAssertEqual(c.current, .welcome(appName: "골드위크", firstTime: true))
        c.dismiss()
        c.welcomeOnce(appName: "골드위크", firstTime: true)
        XCTAssertNil(c.current)
    }

    func test_유료_감사를_받은_사람에게는_인사를_건너뛴다() {
        let c = make()
        c.noteOwned(tierID: "pro", tierName: "Pro", justNow: false)
        c.dismiss()
        c.welcomeOnce(appName: "골드위크", firstTime: false)
        XCTAssertNil(c.current)
    }

    func test_문구에_등급_이름이_들어간다() {
        XCTAssertTrue(LeeoCelebrationMoment.upgraded(tier: "Pro").lines[0].contains("Pro"))
        XCTAssertTrue(LeeoCelebrationMoment.paidThanks(tier: "Plus").lines[0].contains("Plus"))
        XCTAssertTrue(LeeoCelebrationMoment.welcome(appName: "골드위크", firstTime: true).lines[0].contains("골드위크"))
    }
}
