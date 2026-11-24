//
//  LeeoPaywallLink.swift
//  LeeoKit
//
//  **밖에서 누른 링크로 앱을 열면 요금제 화면을 띄운다.**
//
//  App Store '앱 내 이벤트'(세일 카드)는 앱 안으로 들어가는 링크가 있어야 심사에 낼 수 있다.
//  그 링크가 `<번들 ID 소문자>://paywall` 이다. 앱이 할 일은 둘뿐이다.
//
//  1. Info.plist 의 URL Types 에 번들 ID 를 소문자로 적은 스킴을 하나 더한다.
//  2. 루트 화면에 한 줄 — 앱이 쓰는 요금제 화면을 넘긴다:
//
//      ContentView()
//          .leeoPaywallLink { PaywallView() }
//
//  페이월을 `isPresented` 로 띄우는 앱(`leeoPaywallSheet` 등)은 그 바인딩을 넘긴다:
//
//      ContentView()
//          .proPaywall(isPresented: $showPlans)
//          .leeoPaywallLink(isPresented: $showPlans)
//
//  이벤트에 적을 주소는 `LeeoPaywallLink.url` 이 알려 준다.
//
//  할인 기간에는 이 한 줄이 할인 전면 배너도 띄운다(`LeeoSale`).
//

import SwiftUI

public enum LeeoPaywallLink {
    /// 링크가 여는 곳. `<스킴>://paywall`
    public static let host = "paywall"

    /// 이 앱의 요금제 링크 — 스킴은 번들 ID 를 소문자로 쓴 것.
    public static var url: URL? {
        Bundle.main.bundleIdentifier.flatMap { URL(string: "\($0.lowercased())://\(host)") }
    }

    /// 앱 안에서 요금제 화면을 연다(할인 배너의 단추). `.leeoPaywallLink` 가 붙은 화면이 받는다.
    @MainActor public static func open() {
        NotificationCenter.default.post(name: openNotification, object: nil)
    }

    static let openNotification = Notification.Name("leeo.paywallLink.open")

    /// 요금제 화면을 여는 링크인가 — 스킴은 따지지 않는다(앱마다 다르고, 앱에 들어온 이상 그 앱의 것이다).
    public static func opensPaywall(_ url: URL) -> Bool {
        url.host?.lowercased() == host
    }
}

#if !os(watchOS)
public extension View {
    /// `<스킴>://paywall` 로 앱이 열리면 `paywall` 을 시트로 띄운다. 루트 화면에 한 번 붙인다.
    func leeoPaywallLink<Paywall: View>(@ViewBuilder paywall: @escaping () -> Paywall) -> some View {
        modifier(LeeoPaywallLinkHost(paywall: paywall))
    }
}

public extension View {
    /// `<스킴>://paywall` 로 앱이 열리면 `isPresented` 를 켠다 — 페이월은 앱이 이미 거는 시트가 띄운다.
    func leeoPaywallLink(isPresented: Binding<Bool>) -> some View {
        onOpenURL { url in
            if LeeoPaywallLink.opensPaywall(url) { isPresented.wrappedValue = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: LeeoPaywallLink.openNotification)) { _ in
            isPresented.wrappedValue = true
        }
        .leeoSaleBanner()
    }
}

struct LeeoPaywallLinkHost<Paywall: View>: ViewModifier {
    let paywall: () -> Paywall
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if LeeoPaywallLink.opensPaywall(url) { isPresented = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: LeeoPaywallLink.openNotification)) { _ in
                isPresented = true
            }
            .sheet(isPresented: $isPresented) { paywall() }
            .leeoSaleBanner()
    }
}
#endif
