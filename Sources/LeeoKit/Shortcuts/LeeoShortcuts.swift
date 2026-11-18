//
//  LeeoShortcuts.swift
//  LeeoKit
//
//  **Siri와 단축어** — 앱이 내놓은 App Shortcuts 를 사용자에게 보여 주고, 단축어 앱으로 데려간다.
//
//  원본은 앱의 `AppShortcutsProvider` 한 곳이다. 빌드가 그것을 `Metadata.appintents` 로 앱에 묶으므로
//  LeeoKit 은 그 파일을 읽기만 한다 — 앱이 따로 등록하거나 목록을 다시 적을 일이 없다.
//
//  - 설정: `LeeoSupportSection` 이 단축어가 있는 앱에 "Siri와 단축어" 줄을 저절로 단다.
//  - 사전 점검: 단축어가 없거나, 단축어 이름의 번역이 앱에 묶이지 않았으면 `LeeoPreflight` 가 오류로 잡는다.
//    (단축어 이름은 앱 번들의 `Localizable` 표에서 찾는다. 그 표가 위젯에만 묶여 있으면
//     단축어 앱에 키 — 보통 영어 — 가 그대로 나온다.)
//

import SwiftUI
#if os(iOS) || os(visionOS)
import AppIntents
#endif

// MARK: - 앱에 묶인 단축어

public struct LeeoAppShortcut: Identifiable, Equatable, Sendable {
    /// 인텐트 타입 이름(`RemainingLeaveIntent`).
    public let id: String
    /// 단축어 이름의 번역 키(`shortTitle`).
    public let titleKey: String
    /// Siri 에게 할 말의 번역 키. `${applicationName}` 자리에 앱 이름이 들어간다.
    public let phraseKeys: [String]
    public let systemImageName: String?
}

public enum LeeoShortcuts {

    /// 앱에 묶인 단축어. 빌드 결과(`Metadata.appintents`)가 없거나 비었으면 빈 배열.
    public static func load(from bundle: Bundle = .main) -> [LeeoAppShortcut] {
        guard let url = bundle.url(forResource: "Metadata", withExtension: "appintents")?
                .appendingPathComponent("extract.actionsdata"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["autoShortcuts"] as? [[String: Any]]
        else { return [] }

        func key(_ any: Any?) -> String? { (any as? [String: Any])?["key"] as? String }
        return list.compactMap { item in
            guard let id = item["actionIdentifier"] as? String, let title = key(item["shortTitle"]) else { return nil }
            let phrases = (item["phraseTemplates"] as? [Any] ?? []).compactMap(key)
            return LeeoAppShortcut(id: id, titleKey: title, phraseKeys: phrases,
                                   systemImageName: item["systemImageName"] as? String)
        }
    }

    /// 앱 실행 중 한 번만 읽는다.
    public static let current: [LeeoAppShortcut] = load()

    /// 지금 언어의 단축어 이름.
    public static func title(_ shortcut: LeeoAppShortcut, in bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: shortcut.titleKey, value: shortcut.titleKey, table: nil)
    }

    /// 지금 언어로 Siri 에게 할 첫 문장. 앱 이름을 채워 넣는다.
    public static func phrase(_ shortcut: LeeoAppShortcut, appName: String, in bundle: Bundle = .main) -> String? {
        guard let key = shortcut.phraseKeys.first else { return nil }
        return bundle.localizedString(forKey: key, value: key, table: "AppShortcuts")
            .replacingOccurrences(of: "${applicationName}", with: appName)
    }

    /// 단축어 이름의 번역이 빠진 언어. 키마다 `[언어]`.
    ///
    /// 기준 언어로만 쓴 문장은 빌드 결과의 표에 들어가지 않는다(문장 자체가 원문이라서).
    /// 그래서 한 언어가 빠진 건 기준 언어로 보고, **두 언어 이상** 빠졌을 때만 돌려준다.
    /// 번역 표가 앱에 아예 묶이지 않은 경우는 모든 언어가 빠지므로 여기에 걸린다.
    public static func untranslatedTitles(in bundle: Bundle = .main,
                                          shortcuts: [LeeoAppShortcut]? = nil) -> [String: [String]] {
        // ⚠️ 같은 언어가 두 번 올 수 있다 — Info.plist 의 CFBundleLocalizations 와 lproj 폴더가
        //    겹치면 Bundle.localizations 가 둘 다 돌려준다. 겹친 채로 사전을 만들면 앱이 멈춘다.
        var seen = Set<String>()
        let languages = bundle.localizations.filter { $0 != "Base" && seen.insert($0).inserted }
        guard languages.count >= 2 else { return [:] }
        let tables: [String: [String: String]] = Dictionary(uniqueKeysWithValues: languages.map { lang in
            let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: lang)
            return (lang, url.flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:])
        })
        var result: [String: [String]] = [:]
        for shortcut in shortcuts ?? load(from: bundle) {
            let missing = languages.filter { tables[$0]?[shortcut.titleKey] == nil }.sorted()
            if missing.count >= 2 { result[shortcut.titleKey] = missing }
        }
        return result
    }
}

// MARK: - 앱이 쓰는 문구

public enum LeeoShortcutsText {
    /// 설정 행 이름.
    public static var entry: String { L("Siri와 단축어", comment: "Shortcuts: settings entry") }
}

// MARK: - 화면

// 손목에는 설정의 지원 칸이 없다.
#if !os(watchOS)

/// 앱의 단축어와 Siri 에게 할 말을 보여 주고, 단축어 앱으로 데려간다.
public struct LeeoShortcutsView: View {
    @Environment(\.leeoStyle) private var theme
    @Environment(\.openURL) private var openURL
    private let shortcuts: [LeeoAppShortcut]
    private let appName: String

    /// - Parameter appName: Siri 가 알아듣는 앱 이름. 보통 `Spec.displayName`.
    public init(appName: String, shortcuts: [LeeoAppShortcut] = LeeoShortcuts.current) {
        self.appName = appName
        self.shortcuts = shortcuts
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("앱을 열지 않고 Siri에게 말하거나 단축어 앱에서 바로 쓸 수 있어요.",
                       comment: "Shortcuts: explanation at the top"))
                    .font(.subheadline)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                        if index > 0 { Divider().padding(.leading, 52) }
                        row(shortcut)
                    }
                }
                .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.surface))

                openShortcuts
                    .frame(maxWidth: .infinity)

                Text(L("단축어 앱의 자동화에 넣으면 정한 때에 저절로 실행돼요.",
                       comment: "Shortcuts: automation hint at the bottom"))
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(LeeoShortcutsText.entry)
    }

    private func row(_ shortcut: LeeoAppShortcut) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: shortcut.systemImageName ?? "square.on.square")
                .font(.title3)
                .foregroundStyle(theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(LeeoShortcuts.title(shortcut))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.text)
                if let phrase = LeeoShortcuts.phrase(shortcut, appName: appName) {
                    Text("“\(phrase)”")
                        .font(.subheadline)
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// 단축어 앱의 이 앱 칸으로 데려가는 애플 표준 단추. Mac 전용 앱에는 없어 단축어 앱을 연다.
    @ViewBuilder
    private var openShortcuts: some View {
        #if os(iOS) || os(visionOS)
        ShortcutsLink()
        #else
        Button {
            if let url = URL(string: "shortcuts://") { openURL(url) }
        } label: {
            Label(L("단축어 앱 열기", comment: "Shortcuts: open the Shortcuts app button"), systemImage: "square.2.layers.3d")
                .font(.body.weight(.semibold))
        }
        #endif
    }
}
#endif
