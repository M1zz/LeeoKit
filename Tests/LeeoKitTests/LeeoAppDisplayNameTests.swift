//
//  LeeoAppDisplayNameTests.swift
//  LeeoKitTests
//
//  화면용 앱 이름(LeeoAppSpec.displayName) 기본값 검증.
//  appName 은 기록을 묶는 식별 값이라 그대로 두고, 화면에는 번들의 (현지화된) 표시 이름이 나와야 한다.
//  가짜 번들을 임시 폴더에 만들어 Info.plist · InfoPlist.strings 조합별로 본다.
//

import XCTest
@testable import LeeoKit

private enum PlainSpec: LeeoAppSpec {
    static let appName = "두번알림"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.Plain")
    static let legal = LeeoLegalConfig(privacyURL: URL(string: "https://ysoup.io/privacy")!,
                                       supportURL: URL(string: "https://ysoup.io/support")!)
    static let monetization = LeeoMonetization.free
}

private enum OverridingSpec: LeeoAppSpec {
    static let appName = "두번알림"
    static let displayName = "Rereminder"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.Override")
    static let legal = LeeoLegalConfig(privacyURL: URL(string: "https://ysoup.io/privacy")!,
                                       supportURL: URL(string: "https://ysoup.io/support")!)
    static let monetization = LeeoMonetization.free
}

final class LeeoAppDisplayNameTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("leeo.displayname.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// macOS 번들 모양(Contents/Info.plist, Contents/Resources/<lang>.lproj)으로 가짜 번들을 만든다.
    private func makeBundle(info: [String: String]?, localized: [String: String]? = nil) throws -> Bundle {
        let root = dir.appendingPathComponent("Fake\(UUID().uuidString.prefix(6)).bundle")
        let contents = root.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        if let info {
            var plist: [String: String] = ["CFBundleIdentifier": "com.ysoup.test.\(UUID().uuidString)",
                                           "CFBundleDevelopmentRegion": "en"]
            plist.merge(info) { $1 }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        if let localized {
            let lproj = resources.appendingPathComponent("en.lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            let body = localized.map { "\"\($0.key)\" = \"\($0.value)\";" }.joined(separator: "\n")
            try body.write(to: lproj.appendingPathComponent("InfoPlist.strings"), atomically: true, encoding: .utf8)
        }
        return try XCTUnwrap(Bundle(url: root))
    }

    func testFallsBackToAppNameWhenBundleHasNoName() throws {
        let bundle = try makeBundle(info: nil)
        XCTAssertEqual(LeeoAppDisplayName.resolve(in: bundle, fallback: "두번알림"), "두번알림")
    }

    func testPrefersDisplayNameOverBundleName() throws {
        let bundle = try makeBundle(info: ["CFBundleName": "Rereminder",
                                           "CFBundleDisplayName": "Rereminder Timer"])
        XCTAssertEqual(LeeoAppDisplayName.resolve(in: bundle, fallback: "두번알림"), "Rereminder Timer")
    }

    func testUsesBundleNameWhenNoDisplayName() throws {
        let bundle = try makeBundle(info: ["CFBundleName": "Rereminder"])
        XCTAssertEqual(LeeoAppDisplayName.resolve(in: bundle, fallback: "두번알림"), "Rereminder")
    }

    func testBlankDisplayNameIsSkipped() throws {
        let bundle = try makeBundle(info: ["CFBundleName": "Rereminder", "CFBundleDisplayName": "  "])
        XCTAssertEqual(LeeoAppDisplayName.resolve(in: bundle, fallback: "두번알림"), "Rereminder")
    }

    func testLocalizedInfoPlistWins() throws {
        let bundle = try makeBundle(info: ["CFBundleName": "Rereminder", "CFBundleDisplayName": "Rereminder"],
                                    localized: ["CFBundleDisplayName": "Rereminder EN"])
        XCTAssertEqual(LeeoAppDisplayName.resolve(in: bundle, fallback: "두번알림"), "Rereminder EN")
    }

    /// 프로토콜 기본값은 메인 번들을 보고, 앱이 선언하면 그 값이 이긴다. appName 은 그대로다.
    func testSpecDefaultAndOverride() {
        XCTAssertEqual(PlainSpec.displayName, LeeoAppDisplayName.resolve(in: .main, fallback: "두번알림"))
        XCTAssertEqual(OverridingSpec.displayName, "Rereminder")
        XCTAssertEqual(OverridingSpec.appName, "두번알림")
        XCTAssertEqual(genericDisplayName(OverridingSpec.self), "Rereminder", "제네릭 경로에서도 덮어쓴 값이 보여야 한다")
    }

    private func genericDisplayName<Spec: LeeoAppSpec>(_: Spec.Type) -> String { Spec.displayName }
}
