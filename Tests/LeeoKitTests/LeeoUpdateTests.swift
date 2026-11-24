import XCTest
@testable import LeeoKit

@MainActor
final class LeeoUpdateTests: XCTestCase {
    private let os = OperatingSystemVersion(majorVersion: 17, minorVersion: 4, patchVersion: 0)

    private func release(_ v: String, min: String? = "16.0") -> LeeoStoreRelease {
        LeeoStoreRelease(version: v, notes: ["알림이 더 정확해졌습니다"], url: URL(string: "https://apps.apple.com/app/id1")!, minimumOS: min)
    }

    func testVersionCompare() {
        XCTAssertTrue(LeeoUpdate.isNewer("1.10.0", than: "1.9.2"))
        XCTAssertTrue(LeeoUpdate.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(LeeoUpdate.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(LeeoUpdate.isNewer("1.0.5", than: "1.0.6"))
    }

    func testOnlyNewerAndInstallable() {
        let d = UserDefaults(suiteName: "LeeoUpdateTests.\(UUID().uuidString)")!
        XCTAssertNil(LeeoUpdate.pending(release: release("1.0.5"), installed: "1.0.5", osVersion: os, defaults: d))
        XCTAssertNil(LeeoUpdate.pending(release: release("1.0.6", min: "18.0"), installed: "1.0.5", osVersion: os, defaults: d))
        XCTAssertNotNil(LeeoUpdate.pending(release: release("1.0.6"), installed: "1.0.5", osVersion: os, defaults: d))
    }

    func testOncePerVersion() {
        let d = UserDefaults(suiteName: "LeeoUpdateTests.\(UUID().uuidString)")!
        LeeoUpdate.markShown("1.0.6", defaults: d)
        XCTAssertNil(LeeoUpdate.pending(release: release("1.0.6"), installed: "1.0.5", osVersion: os, defaults: d))
        XCTAssertNotNil(LeeoUpdate.pending(release: release("1.0.7"), installed: "1.0.5", osVersion: os, defaults: d))
    }

    func testParseLookup() throws {
        let json = #"{"resultCount":1,"results":[{"version":"2.1.0","trackViewUrl":"https://apps.apple.com/kr/app/id9","minimumOsVersion":"17.0","releaseNotes":"- 위젯이 빨라졌어요\n\n• 다크 모드를 고쳤어요"}]}"#
        let r = try XCTUnwrap(LeeoStoreRelease.parse(Data(json.utf8)))
        XCTAssertEqual(r.version, "2.1.0")
        XCTAssertEqual(r.notes, ["위젯이 빨라졌어요", "다크 모드를 고쳤어요"])
        XCTAssertNil(LeeoStoreRelease.parse(Data(#"{"resultCount":0,"results":[]}"#.utf8)))
    }
}
