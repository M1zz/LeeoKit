//
//  LeeoShortcutsTests.swift
//  LeeoKitTests
//
//  Siri와 단축어: 앱에 묶인 단축어를 읽고, 단축어가 없거나 이름 번역이 앱에 안 묶였으면 사전 점검이 잡는다.
//

import XCTest
@testable import LeeoKit

final class LeeoShortcutsTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 맥 모양 앱 번들을 만든다. `strings` 는 언어 → Localizable 표.
    private func makeApp(shortcuts: Bool, strings: [String: [String: String]]) throws -> Bundle {
        let app = root.appendingPathComponent("Fake.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        let fm = FileManager.default
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.fake", "CFBundlePackageType": "APPL",
                                   "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))

        let meta = resources.appendingPathComponent("Metadata.appintents")
        try fm.createDirectory(at: meta, withIntermediateDirectories: true)
        let auto: [[String: Any]] = shortcuts ? [[
            "actionIdentifier": "RemainingLeaveIntent",
            "phraseTemplates": [["alternatives": [], "key": "${applicationName} remaining leave"]],
            "shortTitle": ["alternatives": [], "key": "Remaining Leave"],
            "systemImageName": "calendar.badge.clock"
        ]] : []
        try JSONSerialization.data(withJSONObject: ["autoShortcuts": auto, "version": 1])
            .write(to: meta.appendingPathComponent("extract.actionsdata"))

        for (lang, table) in strings {
            let lproj = resources.appendingPathComponent("\(lang).lproj")
            try fm.createDirectory(at: lproj, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
                .write(to: lproj.appendingPathComponent("Localizable.strings"))
            try PropertyListSerialization.data(fromPropertyList: ["${applicationName} remaining leave": "${applicationName} \(lang)"],
                                               format: .binary, options: 0)
                .write(to: lproj.appendingPathComponent("AppShortcuts.strings"))
        }
        return try XCTUnwrap(Bundle(url: app))
    }

    func test_앱에_묶인_단축어를_읽는다() throws {
        let bundle = try makeApp(shortcuts: true, strings: ["en": ["Remaining Leave": "Remaining Leave"]])
        let list = LeeoShortcuts.load(from: bundle)
        XCTAssertEqual(list, [LeeoAppShortcut(id: "RemainingLeaveIntent", titleKey: "Remaining Leave",
                                              phraseKeys: ["${applicationName} remaining leave"],
                                              systemImageName: "calendar.badge.clock")])
        XCTAssertEqual(LeeoShortcuts.phrase(list[0], appName: "Goldweek", in: bundle), "Goldweek en")
    }

    func test_단축어가_없으면_사전_점검이_잡는다() throws {
        let bundle = try makeApp(shortcuts: false, strings: [:])
        XCTAssertEqual(LeeoPreflight.shortcutIssues(in: bundle).map(\.code), ["shortcuts.missing"])
    }

    func test_번역이_앱에_묶이지_않으면_잡는다() throws {
        // 번역 표가 위젯에만 묶여 앱에는 단축어 이름이 없는 경우 — 모든 언어가 빠진다.
        let bundle = try makeApp(shortcuts: true, strings: ["en": [:], "ko": [:], "ja": [:]])
        XCTAssertEqual(LeeoShortcuts.untranslatedTitles(in: bundle), ["Remaining Leave": ["en", "ja", "ko"]])
        XCTAssertEqual(LeeoPreflight.shortcutIssues(in: bundle).map(\.code), ["shortcuts.untranslated"])
    }

    func test_기준_언어_하나만_빠진_건_통과한다() throws {
        // 기준 언어로만 쓴 문장은 빌드가 표에 넣지 않는다.
        let bundle = try makeApp(shortcuts: true, strings: [
            "en": [:], "ko": ["Remaining Leave": "남은 연차"], "ja": ["Remaining Leave": "残りの有給"]
        ])
        XCTAssertTrue(LeeoPreflight.shortcutIssues(in: bundle).isEmpty)
    }

    func test_앱_번들이_아니면_건너뛴다() {
        // 패키지 테스트 실행기 자체는 .app 이 아니다.
        XCTAssertTrue(LeeoPreflight.shortcutIssues(in: .main).isEmpty)
    }
}
