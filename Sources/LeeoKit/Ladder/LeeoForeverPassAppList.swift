//
//  LeeoForeverPassAppList.swift
//  LeeoKit
//
//  패스 화면에 서는 앱 목록. 줄을 누르면 소개 페이지, 산 뒤의 받기는 App Store 로 간다.
//  둘은 다른 페이지다. 소개 페이지는 무슨 앱인지 알리고, App Store 는 설치한다.
//
//  ⚠️ 이미 설치했는지는 다른 앱에서 알 수 없어 표시하지 않는다. App Store 시트가 열기 단추를 보여 준다.
//

import SwiftUI
#if os(iOS) && !targetEnvironment(macCatalyst)
import StoreKit
import UIKit
#endif

struct LeeoForeverPassAppList: View {
    let bundleID: String
    let owned: Bool

    @Environment(\.leeoStyle) private var theme
    @Environment(\.openURL) private var openURL
    @State private var apps: [LeeoForeverPassApp]
    @State private var showsAll = false
    @State private var storeApp: LeeoForeverPassApp?

    private static let collapsedCount = 5

    init(bundleID: String, owned: Bool) {
        self.bundleID = bundleID
        self.owned = owned
        _apps = State(initialValue: LeeoForeverPassApps.others(than: bundleID))
    }

    private var shown: [LeeoForeverPassApp] {
        showsAll ? apps : Array(apps.prefix(Self.collapsedCount))
    }

    var body: some View {
        Group {
            if !apps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(owned ? LeeoLadderText.passListOwnedTitle : LeeoLadderText.passListTitle)
                        .font(.headline)
                        .foregroundStyle(theme.text)
                        .accessibilityAddTraits(.isHeader)
                    if owned {
                        Text(LeeoLadderText.passListOwnedNote)
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 0) {
                        ForEach(shown) { app in
                            Divider()
                            row(app)
                        }
                    }
                    if apps.count > Self.collapsedCount && !showsAll {
                        Divider()
                        Button(String(format: LeeoLadderText.passListShowAllFormat, apps.count)) { showsAll = true }
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await LeeoForeverPassApps.refresh()
            apps = LeeoForeverPassApps.others(than: bundleID)
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .background(LeeoStoreSheetPresenter(app: $storeApp) { url in openURL(url) })
        #endif
    }

    private func row(_ app: LeeoForeverPassApp) -> some View {
        HStack(spacing: 12) {
            Button { openURL(app.introURL) } label: {
                HStack(spacing: 12) {
                    LeeoForeverPassAppIcon(app: app, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.text)
                        if !app.tagline.isEmpty {
                            Text(app.tagline)
                                .foregroundStyle(theme.textMuted)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(LeeoLadderText.passListIntroHint)

            trailing(app)
        }
        .padding(.vertical, 10)
    }

    /// 사기 전에는 소개 페이지, 산 뒤에는 App Store 로 간다. 이 기기에 못 까는 앱은 어디서 쓰는지만 말한다.
    @ViewBuilder
    private func trailing(_ app: LeeoForeverPassApp) -> some View {
        if !app.runsOnThisDevice {
            Text(app.platforms.contains(.mac) ? LeeoLadderText.passListMacOnly : LeeoLadderText.passListIPhoneOnly)
                .foregroundStyle(theme.textMuted)
        } else if owned {
            actionButton(LeeoLadderText.passListGet) { get(app) }
                .accessibilityLabel(String(format: LeeoLadderText.passListGetLabelFormat, app.name))
        } else {
            actionButton(LeeoLadderText.passListView) { openURL(app.introURL) }
                .accessibilityLabel(String(format: LeeoLadderText.passListViewLabelFormat, app.name))
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(theme.accent)
    }

    private func get(_ app: LeeoForeverPassApp) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        storeApp = app
        #else
        if let url = app.storeURL { openURL(url) }
        #endif
    }
}

/// 앱 아이콘. 모서리는 `LeeoFamilyIcon` 처럼 크기에 비례해 깎는다.
private struct LeeoForeverPassAppIcon: View {
    let app: LeeoForeverPassApp
    let size: CGFloat

    private var radius: CGFloat { size * 0.225 }

    var body: some View {
        icon
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }

    private var icon: Image {
        #if canImport(UIKit)
        UIImage(data: app.iconPNGData).map(Image.init(uiImage:)) ?? Image(systemName: "app.fill")
        #else
        NSImage(data: app.iconPNGData).map(Image.init(nsImage:)) ?? Image(systemName: "app.fill")
        #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// 앱을 떠나지 않고 받게 App Store 시트를 띄운다.
/// ⚠️ `SKStoreProductViewController` 는 모달로만 띄울 수 있어 SwiftUI sheet 에 넣지 않고 빈 컨트롤러에서 present 한다.
/// 시트가 상품을 못 불러오면 App Store 앱으로 넘긴다.
private struct LeeoStoreSheetPresenter: UIViewControllerRepresentable {
    @Binding var app: LeeoForeverPassApp?
    let fallback: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard let app, host.presentedViewController == nil, host.view.window != nil else { return }
        let store = SKStoreProductViewController()
        store.delegate = context.coordinator
        host.present(store, animated: true)
        let storeURL = app.storeURL
        store.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: app.appStoreID]) { loaded, _ in
            guard !loaded else { return }
            DispatchQueue.main.async {
                store.dismiss(animated: true)
                self.app = nil
                if let storeURL { fallback(storeURL) }
            }
        }
    }

    final class Coordinator: NSObject, SKStoreProductViewControllerDelegate {
        var parent: LeeoStoreSheetPresenter
        init(_ parent: LeeoStoreSheetPresenter) { self.parent = parent }

        func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
            viewController.dismiss(animated: true)
            parent.app = nil
        }
    }
}
#endif
