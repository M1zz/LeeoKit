//
//  LeeoUpdate.swift
//  LeeoKit
//
//  **새 버전이 나왔으면 무엇이 좋아졌는지 짧게 보여 주고 업데이트로 이끈다.**
//
//  App Store 에 올라간 최신 버전과 그 버전의 "새로운 기능" 글은 iTunes 조회(`lookup?bundleId=`)로 읽는다 —
//  릴리즈 노트는 레포의 `RELEASE_NOTES.md` 가 배포 때 올린 그 글이다. 앱이 할 일은 없다:
//  `.leeoCelebrations` 가 아래쪽 카드를 함께 붙인다.
//
//  강제하지 않는다 — 돕는 정도로만:
//  - 화면을 막지 않는 아래쪽 작은 카드. 손대지 않으면 잠시 뒤 저절로 걷힌다
//  - 새 버전마다 딱 한 번. 한 번 보인 버전은 다시 띄우지 않는다
//  - 깔린 버전보다 새 버전이 있고, 이 기기에서 받을 수 있을 때만(최소 OS). 처음 깐 날은 띄우지 않는다
//

import Foundation

/// App Store 에 올라간 최신 버전.
struct LeeoStoreRelease: Equatable, Codable {
    var version: String
    var notes: [String]
    var url: URL
    var minimumOS: String?

    /// iTunes 조회 응답의 첫 결과. 없거나 모양이 다르면 nil.
    static func parse(_ data: Data) -> LeeoStoreRelease? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (root["results"] as? [[String: Any]])?.first,
              let version = first["version"] as? String,
              let link = (first["trackViewUrl"] as? String).flatMap(URL.init(string:)) else { return nil }
        let notes = ((first["releaseNotes"] as? String) ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { line in
                // 혹시 글머리표가 붙어 와도 떼어 낸다.
                var text = Substring(line)
                while let c = text.first, "-•·*".contains(c) { text = text.dropFirst() }
                return text.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        return LeeoStoreRelease(version: version, notes: notes, url: link, minimumOS: first["minimumOsVersion"] as? String)
    }
}

@MainActor
enum LeeoUpdate {

    private static let cacheKey = "leeo.update.release"
    private static let fetchedAtKey = "leeo.update.fetchedAt"
    private static let shownKey = "leeo.update.shownVersions"
    private static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// `1.10.0` > `1.9.2` 처럼 숫자로 견준다. 모자란 자리는 0.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// 이 기기에서 지금 보여 줄 새 버전.
    static func pending(release: LeeoStoreRelease?, installed: String?, osVersion: OperatingSystemVersion,
                        defaults: UserDefaults = .standard) -> LeeoStoreRelease? {
        guard let release, let installed, isNewer(release.version, than: installed) else { return nil }
        if let minimum = release.minimumOS {
            let os = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
            if isNewer(minimum, than: os) { return nil }
        }
        if (defaults.stringArray(forKey: shownKey) ?? []).contains(release.version) { return nil }
        return release
    }

    /// 이 버전은 보여 줬다 — 다시 띄우지 않는다.
    static func markShown(_ version: String, defaults: UserDefaults = .standard) {
        let shown = (defaults.stringArray(forKey: shownKey) ?? []).filter { $0 != version }
        defaults.set(Array((shown + [version]).suffix(20)), forKey: shownKey)
    }

    /// 반나절에 한 번 App Store 에서 읽는다. 못 읽으면 남겨 둔 것.
    static func latest(defaults: UserDefaults = .standard, session: URLSession = .shared) async -> LeeoStoreRelease? {
        let cached = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(LeeoStoreRelease.self, from: $0) }
        if let last = defaults.object(forKey: fetchedAtKey) as? Date, Date().timeIntervalSince(last) < refreshInterval {
            return cached
        }
        guard let bundleID = Bundle.main.bundleIdentifier else { return cached }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        var query = [URLQueryItem(name: "bundleId", value: bundleID)]
        // 사용자가 보는 나라 스토어의 글로 받는다.
        if let region = Locale.current.region?.identifier, region.count == 2 {
            query.append(URLQueryItem(name: "country", value: region.lowercased()))
        }
        components.queryItems = query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = LeeoStoreRelease.parse(data) else { return cached }
        if let encoded = try? JSONEncoder().encode(release) { defaults.set(encoded, forKey: cacheKey) }
        defaults.set(Date(), forKey: fetchedAtKey)
        return release
    }

    static var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
