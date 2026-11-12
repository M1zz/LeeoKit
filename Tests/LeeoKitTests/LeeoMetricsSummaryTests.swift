//
//  LeeoMetricsSummaryTests.swift
//  LeeoKitTests
//
//  성능 묶음을 한 줄로 줄이는 것 — 허브가 이 줄을 읽어 버전을 견준다.
//

import XCTest
@testable import LeeoKit

final class LeeoMetricsSummaryTests: XCTestCase {

    typealias B = LeeoMetricsSummary.Bucket

    func test_네_값이_한_줄로_나온다() {
        let line = LeeoMetricsSummary.line(
            launchMilliseconds: [B(start: 0, end: 200, count: 1), B(start: 400, end: 600, count: 3)],
            hangSeconds: [B(start: 0.25, end: 0.75, count: 2)],   // 가운데 0.5초 × 2 = 1초
            foregroundSeconds: 1800,                              // 30분 → 한 시간에 2초
            peakMemoryMB: 180.4)
        XCTAssertEqual(line, "launch_ms=500 hang_s_per_h=2.00 peak_mb=180 fg_min=30")
    }

    func test_모르는_값은_적지_않는다() {
        let line = LeeoMetricsSummary.line(launchMilliseconds: [], hangSeconds: [],
                                           foregroundSeconds: 600, peakMemoryMB: 90)
        XCTAssertEqual(line, "hang_s_per_h=0.00 peak_mb=90 fg_min=10")
        XCTAssertFalse(line!.contains("launch_ms"))
    }

    func test_떠_있던_시간뿐이면_올리지_않는다() {
        XCTAssertNil(LeeoMetricsSummary.line(launchMilliseconds: [], hangSeconds: [],
                                             foregroundSeconds: 30, peakMemoryMB: nil))
    }

    func test_가운데_값은_드문_긴_실행에_끌려가지_않는다() {
        let median = LeeoMetricsSummary.median([B(start: 300, end: 500, count: 9), B(start: 9000, end: 11000, count: 1)])
        XCTAssertEqual(median, 400)
    }
}
