//
//  LeeoForeverPassApps.swift
//  LeeoKit
//
//  언제나 평생 패스로 열리는 앱 목록. 패스 화면의 목록과 페이월 한 줄의 앱 개수가 여기서 나온다.
//
//  ⚠️ `LeeoForeverPassRule.family` 와 다르다. family 는 "이 앱에서 산 패스를 믿는다"는 번들 ID 표이고,
//     여기는 **패스를 넣은 버전이 스토어에 나가 있는 앱**만 적는다. 돈을 받고 안 열리는 앱을 보여 주지 않기 위해서다.
//     앱을 더하기 전에 스토어 버전의 출시일이 패스 코드보다 뒤인지 확인한다:
//
//         curl "https://itunes.apple.com/lookup?bundleId=<번들ID>&country=kr"
//
//  새 앱은 저장소 맨 위의 `pass-apps.json` 에 더한다. 업데이트 없이 패스 화면에 나타나고,
//  받지 못하면 마지막으로 받은 것, 그것도 없으면 내장 목록(`embedded`)을 쓴다.
//
//  ⚠️ 로고가 없는 앱은 목록에 올리지 않는다. 받아 온 앱은 `icon`(base64)을 함께 적거나
//     `scripts/embed_family_icons.py` 로 내장한다.
//

import Foundation

public struct LeeoForeverPassApp: Identifiable, Equatable, Sendable {
    public let id: String
    public let bundleID: String
    public let appStoreID: String
    public let name: String
    public let tagline: String
    /// 이 앱을 알리는 소개 페이지. App Store 페이지와 다르다.
    public let introURL: URL
    public let platforms: [LeeoFamilyPlatform]
    /// 앱 아이콘 PNG. 비어 있는 채로 만들어지지 않는다.
    public let iconPNGData: Data

    public var storeURL: URL? { URL(string: "https://apps.apple.com/app/id\(appStoreID)") }
    public var runsOnThisDevice: Bool { platforms.contains(where: \.isCurrentDevice) }
}

public enum LeeoForeverPassApps {

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/M1zz/LeeoKit/main/pass-apps.json")!
    private static let cacheKey = "leeo.foreverPass.apps"
    private static let fetchedAtKey = "leeo.foreverPass.apps.fetchedAt"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    // MARK: - 내장 목록

    /// 계산 프로퍼티인 이유: 문구가 `L()` 이라 앱 실행 중 언어가 바뀌면 다시 읽어야 한다.
    static var embedded: [LeeoForeverPassApp] {
        let korean = prefersKorean()
        return [
            fromFamily("clipkeyboard", bundleID: "com.Ysoup.TokenMemo",
                       intro: korean ? "https://m1zz.github.io/ClipKeyboard/ko/" : "https://m1zz.github.io/ClipKeyboard/en/"),
            make(id: "goldweek", bundleID: "com.Ysoup.LeaveWise", appStoreID: "6755983135",
                 name: L("골드위크 - 황금연휴 플래너", comment: "Forever pass list: Goldweek store name"),
                 tagline: L("연차를 어디에 끼우면 가장 오래 쉬는지 찾아 준다", comment: "Forever pass list: Goldweek tagline"),
                 intro: korean ? "https://m1zz.github.io/Goldweek/ko/" : "https://m1zz.github.io/Goldweek/en/",
                 platforms: [.iPhone, .iPad]),
            fromFamily("rainbow-ios", bundleID: "com.example.ScheduleDensityApp",
                       intro: korean ? "https://m1zz.github.io/ScheduleDensity/" : "https://m1zz.github.io/ScheduleDensity/en/"),
        ].compactMap { $0 }
    }

    private static func fromFamily(_ id: String, bundleID: String, intro: String) -> LeeoForeverPassApp? {
        guard let app = LeeoFamilyCatalog.app(id: id) else { return nil }
        return make(id: id, bundleID: bundleID, appStoreID: app.appStoreID, name: app.name, tagline: app.tagline,
                    intro: intro, platforms: app.platforms)
    }

    private static func make(id: String, bundleID: String, appStoreID: String, name: String, tagline: String,
                             intro: String, platforms: [LeeoFamilyPlatform], iconBase64: String? = nil) -> LeeoForeverPassApp? {
        guard LeeoForeverPassRule.family.contains(bundleID),
              !appStoreID.isEmpty, appStoreID.allSatisfy(\.isNumber),
              !name.isEmpty, !platforms.isEmpty,
              let introURL = URL(string: intro), introURL.scheme == "https",
              let base64 = iconBase64 ?? LeeoFamilyIconData.pngBase64[id],
              let icon = Data(base64Encoded: base64), !icon.isEmpty else { return nil }
        return LeeoForeverPassApp(id: id, bundleID: bundleID, appStoreID: appStoreID, name: name, tagline: tagline,
                                  introURL: introURL, platforms: platforms, iconPNGData: icon)
    }

    // MARK: - 조회

    /// 지금 보여 줄 전체 목록. 받아 둔 목록이 있으면 그것을, 없으면 내장 목록을 쓴다.
    public static func current(defaults: UserDefaults = .standard) -> [LeeoForeverPassApp] {
        if let data = defaults.data(forKey: cacheKey), let apps = decode(data), !apps.isEmpty { return apps }
        return embedded
    }

    /// 지금 쓰는 앱을 뺀 목록.
    public static func others(than bundleID: String, defaults: UserDefaults = .standard) -> [LeeoForeverPassApp] {
        current(defaults: defaults).filter { $0.bundleID != bundleID }
    }

    /// 패스로 열리는 앱 수. 지금 쓰는 앱을 한 번만 넣어 센다.
    public static func unlockedCount(bundleID: String = Bundle.main.bundleIdentifier ?? "",
                                     defaults: UserDefaults = .standard) -> Int {
        others(than: bundleID, defaults: defaults).count + 1
    }

    // MARK: - 받아 오기

    /// 하루에 한 번 새 목록을 받는다. 실패하면 있던 목록을 그대로 둔다.
    public static func refresh(defaults: UserDefaults = .standard, session: URLSession = .shared,
                               now: Date = Date()) async {
        if let last = defaults.object(forKey: fetchedAtKey) as? Date,
           now.timeIntervalSince(last) < refreshInterval { return }
        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let apps = decode(data), !apps.isEmpty else { return }
        defaults.set(data, forKey: cacheKey)
        defaults.set(now, forKey: fetchedAtKey)
    }

    // MARK: - 받은 목록 읽기

    private struct Payload: Decodable {
        struct Entry: Decodable {
            let id: String
            let bundleID: String
            let appStoreID: String
            let name: [String: String]
            let tagline: [String: String]
            let intro: [String: String]
            let platforms: [String]
            let icon: String?
        }
        let apps: [Entry]
    }

    /// 표에 없는 번들 · 스토어 ID 가 이상한 앱 · 로고가 없는 앱은 조용히 뺀다.
    static func decode(_ data: Data, language: String = preferredLanguage()) -> [LeeoForeverPassApp]? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload.apps.compactMap { entry in
            guard let name = pick(entry.name, language), let intro = pick(entry.intro, language) else { return nil }
            return make(id: entry.id, bundleID: entry.bundleID, appStoreID: entry.appStoreID, name: name,
                        tagline: pick(entry.tagline, language) ?? "", intro: intro,
                        platforms: entry.platforms.compactMap(LeeoFamilyPlatform.init(rawValue:)), iconBase64: entry.icon)
        }
    }

    /// 그 언어 → 기본 언어(zh-Hant 는 그대로 먼저) → 영어 → 한국어 순으로 고른다.
    private static func pick(_ values: [String: String], _ language: String) -> String? {
        let base = language.split(separator: "-").first.map(String.init) ?? language
        return values[language] ?? values[base] ?? values["en"] ?? values["ko"]
    }

    static func preferredLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
    }

    private static func prefersKorean() -> Bool { preferredLanguage().hasPrefix("ko") }
}
