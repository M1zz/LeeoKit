import XCTest
@testable import LeeoKit

@MainActor
final class LeeoSaleTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private let campaign = LeeoSaleCampaign(id: "bf", kind: "blackFriday", announce: "2026-11-24",
                                            start: "2026-11-27", end: "2026-12-04", percent: 80,
                                            apps: ["com.leeo.sunflower"])

    func testPhases() {
        XCTAssertNil(campaign.phase(on: date(2026, 11, 23, 23), calendar: calendar))
        XCTAssertEqual(campaign.phase(on: date(2026, 11, 24, 0), calendar: calendar), .upcoming)
        XCTAssertEqual(campaign.phase(on: date(2026, 11, 26, 23), calendar: calendar), .upcoming)
        XCTAssertEqual(campaign.phase(on: date(2026, 11, 27, 0), calendar: calendar), .live)
        XCTAssertEqual(campaign.phase(on: date(2026, 12, 4, 23), calendar: calendar), .live)
        XCTAssertNil(campaign.phase(on: date(2026, 12, 5, 0), calendar: calendar))
    }

    func testWithoutAnnounceStartsOnStartDay() {
        var c = campaign
        c.announce = nil
        XCTAssertNil(c.phase(on: date(2026, 11, 26), calendar: calendar))
        XCTAssertEqual(c.phase(on: date(2026, 11, 27), calendar: calendar), .live)
    }

    func testDaysLeft() {
        XCTAssertEqual(campaign.daysLeft(on: date(2026, 11, 27), calendar: calendar), 7)
        XCTAssertEqual(campaign.daysLeft(on: date(2026, 12, 4, 22), calendar: calendar), 0)
    }

    func testOnlyListedApps() {
        let schedule = LeeoSaleSchedule(campaigns: [campaign])
        XCTAssertNotNil(LeeoSale.current(in: schedule, bundleID: "COM.leeo.Sunflower", now: date(2026, 11, 28)))
        XCTAssertNil(LeeoSale.current(in: schedule, bundleID: "com.leeo.sunflower", now: date(2026, 12, 20)))
        XCTAssertNil(LeeoSale.current(in: schedule, bundleID: "com.leeo.other", now: date(2026, 11, 28)))
        XCTAssertNil(LeeoSale.current(in: schedule, bundleID: nil, now: date(2026, 11, 28)))
    }

    func testOncePerDayAndSnooze() {
        let defaults = UserDefaults(suiteName: "LeeoSaleTests.\(UUID().uuidString)")!
        let now = date(2026, 11, 27, 9)
        XCTAssertTrue(LeeoSale.isDue(now: now, defaults: defaults, calendar: calendar))
        LeeoSale.markShown(now: now, defaults: defaults)
        XCTAssertFalse(LeeoSale.isDue(now: date(2026, 11, 27, 20), defaults: defaults, calendar: calendar))
        XCTAssertTrue(LeeoSale.isDue(now: date(2026, 11, 28, 9), defaults: defaults, calendar: calendar))

        LeeoSale.snooze(days: 3, now: now, defaults: defaults)
        XCTAssertFalse(LeeoSale.isDue(now: date(2026, 11, 29, 9), defaults: defaults, calendar: calendar))
        XCTAssertTrue(LeeoSale.isDue(now: date(2026, 11, 30, 10), defaults: defaults, calendar: calendar))
    }

    func testPercentOff() {
        XCTAssertEqual(LeeoSale.percentOff(regular: 3300, offer: 660), 80)
        XCTAssertEqual(LeeoSale.percentOff(regular: Decimal(string: "0.99")!, offer: Decimal(string: "0.29")!), 70)
        XCTAssertNil(LeeoSale.percentOff(regular: 2200, offer: 5000))
        XCTAssertNil(LeeoSale.percentOff(regular: 0, offer: 0))
    }

    func testBuiltInMatchesRepoFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sale.json")
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(LeeoSaleSchedule.self, from: data)
        XCTAssertEqual(file, LeeoSale.builtIn, "sale.json 과 LeeoSale.builtIn 이 어긋났습니다")
    }
}
