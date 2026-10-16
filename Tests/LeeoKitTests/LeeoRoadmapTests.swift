//
//  LeeoRoadmapTests.swift
//  LeeoKitTests
//
//  로드맵: 항목이 상태별로 나뉘고, 나온 것은 최근 몇 개만, 같은 id 는 사전 점검이 잡는다.
//

import XCTest
@testable import LeeoKit

private enum RoadmapSpec: LeeoAppSpec {
    static let appName = "RoadmapApp"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.example.RoadmapApp")
    static let legal = LeeoLegalConfig(privacyURL: URL(string: "https://example.com/p")!,
                                       supportURL: URL(string: "https://example.com/s")!)
    static let monetization = LeeoMonetization.free
    static var roadmap: [LeeoRoadmapItem] {[
        .init(id: "a", status: .building, title: "A"),
        .init(id: "b", status: .planned, title: "B", detail: "b"),
        .init(id: "a", status: .shipped("1.0"), title: "A again")
    ]}
}

final class LeeoRoadmapTests: XCTestCase {
    func test_상태별로_나뉜다() {
        let items = RoadmapSpec.roadmap
        XCTAssertEqual(items.building.map(\.id), ["a"])
        XCTAssertEqual(items.planned.map(\.id), ["b"])
        XCTAssertEqual(items.shipped().map(\.title), ["A again"])
        let many = (0..<8).map { LeeoRoadmapItem(id: "\($0)", status: .shipped("1.\($0)"), title: "\($0)") }
        XCTAssertEqual(many.shipped(limit: 5).count, 5)
    }

    func test_같은_id_는_사전_점검이_잡는다() {
        XCTAssertTrue(LeeoPreflight.audit(RoadmapSpec.self).contains { $0.code == "roadmap.duplicateID" })
    }
}
