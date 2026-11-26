//
//  LeeoAppLanguage.swift
//  LeeoKit
//
//  앱 안에서 언어 고르기. 기기는 영어인데 이 앱만 한국어로 쓰고 싶은 사람을 위한 설정 한 줄.
//
//  iOS 설정 ▸ 앱 ▸ (앱) ▸ 언어 와 같은 자리(앱 도메인의 AppleLanguages)에 적는다. 그래서 두 곳이 늘 같은 값을 본다.
//  iOS 설정의 그 칸은 기기에 선호 언어가 둘 이상일 때만 보여서, 모르는 사람이 많다 — 그래서 앱 안에 둔다.
//
//  번들 언어는 앱이 뜰 때 정해진다. 고른 언어는 앱을 다시 열어야 바뀐다 (앱이 스스로 끄지 않는다).
//  앱의 문구도, LeeoKit 문구도 같이 바뀐다.
//
//  설정에서 한 줄:
//      LeeoLanguageLink()
//

import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
#endif

// MARK: - 언어 고르기

public enum LeeoAppLanguage {
    private static let key = "AppleLanguages"

    /// 앱이 가진 언어 (Base 빼고). 앱의 Info.plist `CFBundleLocalizations` · 카탈로그에서 온다.
    public static var available: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }
            .sorted { nativeName($0).localizedStandardCompare(nativeName($1)) == .orderedAscending }
    }

    /// 이번 실행이 쓰고 있는 언어.
    public static var launched: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// 이 앱에만 따로 고른 언어. nil 이면 기기 설정을 따른다.
    public static var chosen: String? {
        guard let id = Bundle.main.bundleIdentifier,
              let list = UserDefaults.standard.persistentDomain(forName: id)?[key] as? [String] else { return nil }
        return list.first
    }

    /// 고른다. nil 이면 기기 설정으로 돌아간다. 다음 실행부터 바뀐다.
    public static func choose(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// 기기 설정을 따를 때 이 앱이 쓰게 될 언어.
    public static var deviceResolved: String {
        let device = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String]
            ?? Locale.preferredLanguages
        return resolved(device)
    }

    /// 이 선택으로 다음에 열 때 쓰게 될 언어.
    public static func resolved(for choice: String?) -> String {
        choice.map { resolved([$0]) } ?? deviceResolved
    }

    private static func resolved(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: available, forPreferences: preferences).first ?? launched
    }

    /// 그 언어의 이름을 그 언어로 — "한국어", "English", "日本語".
    public static func nativeName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// 그 언어의 이름을 지금 화면 언어로 — 한국어 화면에서 "영어".
    public static func localName(_ code: String) -> String {
        Locale(identifier: launched).localizedString(forIdentifier: code) ?? code
    }
}

// MARK: - 문구

public enum LeeoLanguageText {
    /// 설정 행 이름 · 화면 제목.
    public static var entry: String { L("언어", comment: "App language: settings entry and screen title") }
    public static var followDevice: String { L("기기 설정 따르기", comment: "App language: use the device language") }
    public static var relaunchTitle: String {
        L("앱을 다시 열면 바뀌어요", comment: "App language: the chosen language applies after reopening the app")
    }
    public static var relaunchHow: String {
        L("앱 전환기에서 이 앱을 위로 밀어 닫은 뒤 다시 열어 주세요.",
          comment: "App language: how to reopen the app (swipe it up in the app switcher)")
    }
    public static var openSystemSettings: String {
        L("iOS 설정에서 바꾸기", comment: "App language: button that opens this app's page in the Settings app")
    }
    public static var systemSettingsNote: String {
        L("iOS 설정에서 바꾸면 앱이 바로 다시 열려요.",
          comment: "App language: changing the language in the Settings app relaunches the app right away")
    }
}

// MARK: - 설정 행

/// 설정에 두는 한 줄. 앱이 언어를 하나만 가졌으면 그리지 않는다.
public struct LeeoLanguageLink: View {
    private let systemImage: String

    public init(systemImage: String = "globe") {
        self.systemImage = systemImage
    }

    public var body: some View {
        if LeeoAppLanguage.available.count > 1 {
            NavigationLink {
                LeeoLanguageView()
            } label: {
                LabeledContent {
                    Text(verbatim: LeeoAppLanguage.nativeName(LeeoAppLanguage.resolved(for: LeeoAppLanguage.chosen)))
                } label: {
                    Label(LeeoLanguageText.entry, systemImage: systemImage)
                }
            }
        }
    }
}

// MARK: - 화면

public struct LeeoLanguageView: View {
    @State private var choice: String? = LeeoAppLanguage.chosen
    @Environment(\.openURL) private var openURL

    public init() {}

    private var willChange: Bool { LeeoAppLanguage.resolved(for: choice) != LeeoAppLanguage.launched }

    public var body: some View {
        List {
            if willChange {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: LeeoLanguageText.relaunchTitle).font(.headline)
                            Text(verbatim: LeeoLanguageText.relaunchHow).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                    }
                }
            }

            Section {
                row(code: nil,
                    title: LeeoLanguageText.followDevice,
                    detail: LeeoAppLanguage.nativeName(LeeoAppLanguage.deviceResolved))
                ForEach(LeeoAppLanguage.available, id: \.self) { code in
                    let local = LeeoAppLanguage.localName(code)
                    let native = LeeoAppLanguage.nativeName(code)
                    row(code: code, title: native,
                        detail: local.localizedCaseInsensitiveCompare(native) == .orderedSame ? nil : local)
                }
            }

            #if os(iOS) || os(visionOS)
            Section {
                Button(LeeoLanguageText.openSystemSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text(verbatim: LeeoLanguageText.systemSettingsNote).font(.body)
            }
            #endif
        }
        .navigationTitle(LeeoLanguageText.entry)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .animation(.default, value: choice)
    }

    private func row(code: String?, title: String, detail: String?) -> some View {
        let isOn = choice == code
        return Button {
            choice = code
            LeeoAppLanguage.choose(code)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(.primary)
                    if let detail {
                        Text(verbatim: detail).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
