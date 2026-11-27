//
//  LeeoAppHandoff.swift
//  LeeoKit
//
//  내 앱끼리 일을 넘기는 부품 — "이 기능은 다른 앱이 더 잘한다" 일 때 그 앱으로 바로 잇는다.
//  예: 클립키보드에서 "10분 뒤 다시 알려줘" → 두번알림이 그 제목 · 시간으로 타이머를 맞춘다.
//
//  보내는 쪽 (앱 코드 한 줄):
//
//      @State private var handoff: LeeoHandoff?
//      Button("두번알림으로 알림 받기") { handoff = .rereminderTimer(minutes: 10, title: clip.title) }
//          .leeoHandoff($handoff)
//
//    또는 아이콘 · "두번알림에서 열기 / 받기" 가 붙은 단추를 그대로:
//
//      LeeoHandoffButton(.rereminderTimer(minutes: 10, title: clip.title), title: "10분 뒤 다시 알림")
//
//    깔려 있으면 그 앱을 열고, 아니면 App Clip(있고 그 동작을 받으면) 또는 App Store 시트를 띄운다.
//    무엇으로 갔는지 `handoff_sent` 이벤트로 남는다(허브에서 앱 사이로 몇 명이 넘어갔는지 센다).
//
//  받는 쪽:
//
//      .onOpenURL { url in
//          guard let request = LeeoHandoffRequest(url: url, for: .rereminder) else { return }
//          // request.action == "timer", request.parameters["minutes"] …
//      }
//
//    파싱과 함께 `handoff_received` 를 남긴다(어느 앱에서 왔는지).
//
//  ⚠️ 깔렸는지 알려면 **보내는 앱** Info.plist 의 `LSApplicationQueriesSchemes` 에 받는 앱의 스킴을
//     적어야 한다(iOS). 안 적으면 늘 "안 깔림" 으로 보고 App Store 시트를 띄운다 — 깔린 사람도 시트의
//     "열기" 로 들어갈 수는 있지만 넘긴 값은 잃는다.
//  ⚠️ 받는 앱의 옛 버전은 동작을 모른다 — 앱만 열리고 값은 버려진다. 받는 쪽을 먼저 내보내고,
//     그 버전이 퍼진 뒤에 보내는 단추를 낸다.
//  ⚠️ 키보드 · 공유 같은 **확장에서는 다른 앱을 열 수 없다.** 본 앱 화면 · 알림 · 위젯에서 쓴다.
//  ⚠️ 심사: 보내는 앱은 받는 앱 없이도 제 기능을 해야 한다. 넘기기는 "더 잘하는 길" 이지 필수가 아니다.
//

import SwiftUI
#if os(iOS) && !targetEnvironment(macCatalyst)
import StoreKit
#endif

// MARK: - 받는 앱

/// 일을 넘겨받을 수 있는 내 앱. 이름 · App Store ID · 아이콘은 `LeeoFamilyCatalog` 에서 온다 — 여기는 길만 적는다.
public struct LeeoHandoffTarget: Sendable, Equatable, Hashable {
    /// `LeeoFamilyCatalog` 의 id.
    public let familyID: String
    /// 받는 앱이 Info.plist 에 등록한 URL 스킴.
    public let scheme: String
    /// 설치 없이 그 자리에서 쓰는 App Clip 주소. **그 클립이 넘긴 동작을 읽을 때만** 적는다 —
    /// 읽지 못하는 클립으로 보내면 사용자가 넘긴 값을 잃은 채 빈 화면을 본다.
    public let appClipURL: URL?
    /// 받는 앱이 알아듣는 동작. 여기 없는 동작으로는 넘기지 않는다(옛 버전 앱이 엉뚱한 화면을 열지 않게).
    public let actions: Set<String>

    public init(familyID: String, scheme: String, appClipURL: URL? = nil, actions: Set<String>) {
        self.familyID = familyID
        self.scheme = scheme
        self.appClipURL = appClipURL
        self.actions = actions
    }

    public var app: LeeoFamilyApp? { LeeoFamilyCatalog.app(id: familyID) }
    public var name: String { app?.name ?? familyID }
    public var appStoreID: String? { app?.appStoreID }
    public var storeURL: URL? { appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") } }
}

public extension LeeoHandoffTarget {
    /// 두번알림 — 끝나기 전에 한 번 더 울리는 타이머.
    /// `timer`: minutes(분, 1 이상) · title(타이머 이름, 없어도 됨).
    static let rereminder = LeeoHandoffTarget(familyID: "rereminder", scheme: "com.xa.toki", actions: ["timer"])

    /// 넘겨받을 수 있는 앱 전부. **받는 앱이 그 동작을 읽게 된 뒤에** 여기와 `LeeoFamilyCatalog` 에 더한다 —
    /// 못 읽는 앱으로 보내면 앱만 열리고 넘긴 값은 사라진다.
    static let all: [LeeoHandoffTarget] = [.rereminder]
}

// MARK: - 넘기는 일 하나

/// 다른 앱에 넘기는 일 — 받는 앱 · 동작 · 값.
public struct LeeoHandoff: Sendable, Equatable, Identifiable {
    public let target: LeeoHandoffTarget
    public let action: String
    public let parameters: [String: String]

    public var id: String { "\(target.familyID)/\(action)?\(parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))" }

    /// 받는 앱이 모르는 동작이면 nil.
    public init?(target: LeeoHandoffTarget, action: String, parameters: [String: String] = [:]) {
        guard target.actions.contains(action) else { return nil }
        self.target = target
        self.action = action
        self.parameters = parameters
    }

    /// 보낸 앱 — 받는 쪽이 어디서 왔는지 센다. 번들 ID.
    public static var sourceID: String { Bundle.main.bundleIdentifier ?? "unknown" }

    /// `<스킴>://<동작>?<값>&from=<보낸 앱>`. 값은 퍼센트 인코딩한다.
    public func deepLink(from source: String = LeeoHandoff.sourceID) -> URL? {
        Self.url(base: "\(target.scheme)://\(action)", parameters: parameters, source: source)
    }

    /// App Clip 으로 보낼 주소 — `<클립 주소>?action=<동작>&<값>&from=<보낸 앱>`. 클립이 없으면 nil.
    public func clipLink(from source: String = LeeoHandoff.sourceID) -> URL? {
        guard let clip = target.appClipURL else { return nil }
        return Self.url(base: clip.absoluteString, parameters: parameters.merging(["action": action]) { a, _ in a },
                        source: source)
    }

    private static func url(base: String, parameters: [String: String], source: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        let items = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: LeeoHandoffRequest.sourceKey, value: source)]
        components.queryItems = (components.queryItems ?? []) + items
        return components.url
    }
}

public extension LeeoHandoff {
    /// 두번알림에 타이머를 맞춰 달라고 넘긴다. 분은 1~1440 으로 자른다.
    static func rereminderTimer(minutes: Int, title: String? = nil) -> LeeoHandoff {
        var parameters = ["minutes": String(min(max(minutes, 1), 1_440))]
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            parameters["title"] = String(title.prefix(80))
        }
        // "timer" 는 `.rereminder.actions` 에 있으니 nil 이 될 수 없다.
        return LeeoHandoff(target: .rereminder, action: "timer", parameters: parameters)!
    }
}

// MARK: - 어디로 보낼까 (순수 규칙)

public enum LeeoHandoffRoute: String, Sendable {
    /// 깔려 있다 — 그 앱을 연다.
    case app
    /// 안 깔렸지만 그 동작을 받는 App Clip 이 있다 — 설치 없이 그 자리에서.
    case appClip = "clip"
    /// 안 깔렸다 — App Store 시트에서 받게 한다. 넘긴 값은 잃는다.
    case store

    public static func decide(installed: Bool, hasClip: Bool) -> LeeoHandoffRoute {
        if installed { return .app }
        return hasClip ? .appClip : .store
    }
}

// MARK: - 받는 쪽

/// 넘겨받은 일. 받는 앱의 `onOpenURL` 에서 만든다.
public struct LeeoHandoffRequest: Sendable, Equatable {
    static let sourceKey = "from"

    public let action: String
    public let parameters: [String: String]
    /// 보낸 앱의 번들 ID. 모르면 nil.
    public let source: String?

    /// 이 앱 앞으로 온 넘기기면 만든다 — 스킴이 다르거나 모르는 동작이면 nil.
    /// 딥링크(`<스킴>://<동작>?…`)와 App Clip 주소(`…?action=<동작>&…`)를 둘 다 읽는다.
    public init?(url: URL, for target: LeeoHandoffTarget, track: Bool = true) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { values[item.name] = value }
        }
        let action: String?
        if url.scheme?.lowercased() == target.scheme.lowercased() {
            action = components.host ?? values["action"]
        } else if let clip = target.appClipURL, url.host == clip.host {
            action = values["action"]
        } else {
            action = nil
        }
        guard let action, target.actions.contains(action) else { return nil }
        let source = values.removeValue(forKey: Self.sourceKey)
        values.removeValue(forKey: "action")
        self.action = action
        self.parameters = values
        self.source = source
        if track {
            LeeoAnalyticsCenter.track(.custom(name: "handoff_received", parameters: [
                "action": action, "from": source ?? "unknown",
            ]))
        }
    }

    /// 자주 쓰는 정수 값(분 등). 없거나 숫자가 아니면 nil.
    public func int(_ key: String) -> Int? { parameters[key].flatMap { Int($0) } }
}

// MARK: - 열기

/// 넘기기를 실제로 하는 곳. 깔렸는지 보고 앱 · App Clip · App Store 중 하나로.
@MainActor
public enum LeeoAppHandoff {

    /// 이 기기에 받는 앱이 깔려 있나. iOS 는 보내는 앱의 `LSApplicationQueriesSchemes` 에 스킴이 있어야 안다.
    public static func isInstalled(_ target: LeeoHandoffTarget) -> Bool {
        guard let probe = URL(string: "\(target.scheme)://") else { return false }
        #if os(iOS) || os(visionOS)
        return UIApplication.shared.canOpenURL(probe)
        #elseif os(macOS)
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
        #else
        return false
        #endif
    }

    /// 어디로 갈지 — 화면이 미리 단추 문구("열기" · "받기")를 고를 때도 쓴다.
    public static func route(for handoff: LeeoHandoff) -> LeeoHandoffRoute {
        LeeoHandoffRoute.decide(installed: isInstalled(handoff.target), hasClip: handoff.clipLink() != nil)
    }

    /// 앱 · App Clip 이면 연다. App Store 로 가야 하면 false — 화면이 시트를 띄운다(`leeoHandoff`).
    @discardableResult
    static func openDirectly(_ handoff: LeeoHandoff, route: LeeoHandoffRoute, openURL: OpenURLAction) -> Bool {
        let url: URL?
        switch route {
        case .app: url = handoff.deepLink()
        case .appClip: url = handoff.clipLink()
        case .store: url = nil
        }
        track(handoff, route: route)
        guard let url else { return false }
        openURL(url)
        return true
    }

    static func track(_ handoff: LeeoHandoff, route: LeeoHandoffRoute) {
        LeeoAnalyticsCenter.track(.custom(name: "handoff_sent", parameters: [
            "to": handoff.target.familyID, "action": handoff.action, "route": route.rawValue,
        ]))
    }
}

// MARK: - SwiftUI

public extension View {
    /// `handoff` 에 값을 넣으면 넘긴다. 깔렸으면 그 앱, 아니면 App Clip, 그것도 없으면 App Store 시트.
    /// 다 하면 nil 로 돌린다.
    func leeoHandoff(_ handoff: Binding<LeeoHandoff?>) -> some View {
        modifier(LeeoHandoffModifier(handoff: handoff))
    }
}

struct LeeoHandoffModifier: ViewModifier {
    @Binding var handoff: LeeoHandoff?
    @Environment(\.openURL) private var openURL
    @State private var storeID: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: handoff) { _, value in
                guard let value else { return }
                handoff = nil
                let route = LeeoAppHandoff.route(for: value)
                if !LeeoAppHandoff.openDirectly(value, route: route, openURL: openURL) {
                    #if os(iOS) && !targetEnvironment(macCatalyst)
                    storeID = value.target.appStoreID
                    #else
                    if let url = value.target.storeURL { openURL(url) }
                    #endif
                }
            }
            #if os(iOS) && !targetEnvironment(macCatalyst)
            .background(LeeoHandoffStoreSheet(appStoreID: $storeID) { url in openURL(url) })
            #endif
    }
}

/// 넘기기 단추 — 받는 앱 아이콘과 "<앱>에서 열기" · "<앱> 받기". 문구는 깔렸는지에 따라 바뀐다.
public struct LeeoHandoffButton: View {
    let handoff: LeeoHandoff
    /// 단추 위에 적을 할 일(예: "10분 뒤 다시 알림"). nil 이면 앱 이름만.
    let title: String?

    @State private var pending: LeeoHandoff?
    @State private var installed = false

    public init(_ handoff: LeeoHandoff, title: String? = nil) {
        self.handoff = handoff
        self.title = title
    }

    public var body: some View {
        Button { pending = handoff } label: {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title).fontWeight(.semibold)
                    }
                    Text(String(format: installed ? LeeoHandoffText.openFormat : LeeoHandoffText.getFormat,
                                handoff.target.name))
                        .foregroundStyle(title == nil ? .primary : .secondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: installed ? "arrow.up.forward.app" : "arrow.down.app")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(LeeoHandoffText.hint)
        .leeoHandoff($pending)
        .task { installed = LeeoAppHandoff.isInstalled(handoff.target) }
    }

    @ViewBuilder
    private var icon: some View {
        #if canImport(UIKit)
        if let data = handoff.target.app?.iconPNGData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        } else {
            placeholder
        }
        #elseif canImport(AppKit)
        if let data = handoff.target.app?.iconPNGData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Image(systemName: handoff.target.app?.symbol ?? "app")
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
            .accessibilityHidden(true)
    }
}

enum LeeoHandoffText {
    static var openFormat: String { L("%@에서 열기", comment: "Handoff button: open the sibling app (app name)") }
    static var getFormat: String { L("%@ 받기", comment: "Handoff button: get the sibling app from the App Store (app name)") }
    static var hint: String { L("다른 앱으로 넘어갑니다", comment: "Handoff button accessibility hint") }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// 앱 안에서 App Store 시트를 띄운다. 못 띄우면 App Store 주소로.
private struct LeeoHandoffStoreSheet: UIViewControllerRepresentable {
    @Binding var appStoreID: String?
    let fallback: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard let appStoreID, host.presentedViewController == nil, host.view.window != nil else { return }
        let store = SKStoreProductViewController()
        store.delegate = context.coordinator
        host.present(store, animated: true)
        let storeURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")
        store.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: appStoreID]) { loaded, _ in
            guard !loaded else { return }
            DispatchQueue.main.async {
                store.dismiss(animated: true)
                self.appStoreID = nil
                if let storeURL { fallback(storeURL) }
            }
        }
    }

    final class Coordinator: NSObject, SKStoreProductViewControllerDelegate {
        var parent: LeeoHandoffStoreSheet
        init(_ parent: LeeoHandoffStoreSheet) { self.parent = parent }
        func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
            viewController.dismiss(animated: true)
            parent.appStoreID = nil
        }
    }
}
#endif
