//
//  LeeoSaleBanner.swift
//  LeeoKit
//
//  할인 전면 배너. `.leeoPaywallLink` 가 함께 붙인다 — 단추를 누르면 그 앱의 요금제 화면이 열린다.
//
//  - 미리 알림(announce ~ 시작 전날): "곧 시작해요 · 11월 27일 금요일" + [요금제 미리 보기]
//  - 할인 중(시작 ~ 끝): "지금 할인 중"(마지막 날은 "오늘 마지막 날") + 원래 값 / 할인 값 + [할인 값으로 시작하기]
//  - 하루에 한 번. [3일 동안 보지 않기] 를 누르면 사흘 쉰다. 이미 유료이거나 첫 구독 할인을 받을 수 없으면 띄우지 않는다.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if !os(watchOS)
extension View {
    /// 할인 기간이면 앱을 연 뒤 한 번 전면 배너를 띄운다. `.leeoPaywallLink` 가 붙인다.
    func leeoSaleBanner() -> some View { modifier(LeeoSaleHost()) }
}

struct LeeoSaleHost: ViewModifier {
    @State private var offer: LeeoSaleOffer?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if let offer {
                    LeeoSaleBannerView(offer: offer,
                                       onClose: { self.offer = nil },
                                       onSnooze: { LeeoSale.snooze(); self.offer = nil },
                                       onOpen: {
                                           self.offer = nil
                                           // 배너가 걷힌 뒤에 요금제 시트를 올린다.
                                           Task { @MainActor in
                                               try? await Task.sleep(for: .milliseconds(350))
                                               LeeoPaywallLink.open()
                                           }
                                       })
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: offer)
            .task { await check() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await check() } }
            }
    }

    @MainActor
    private func check() async {
        guard offer == nil else { return }
        // 처음 깐 날은 앱을 익히게 둔다.
        guard LeeoEngagement.shared.launchCount > 1, LeeoSale.isDue(now: Date()) else { return }
        // 스토어가 권한을 읽고, 축하 · 감사가 먼저 뜰 틈을 준다.
        try? await Task.sleep(for: .seconds(2.5))
        for _ in 0..<20 where LeeoCelebration.shared.current != nil {
            try? await Task.sleep(for: .seconds(1))
        }
        guard LeeoCelebration.shared.current == nil else { return }

        let schedule = await LeeoSale.refresh()
        guard let (campaign, phase) = LeeoSale.current(in: schedule, bundleID: Bundle.main.bundleIdentifier, now: Date()) else { return }
        #if canImport(StoreKit)
        guard let found = await LeeoSale.offer(for: campaign, phase: phase) else { return }
        #else
        let found = LeeoSaleOffer(campaign: campaign, phase: phase, percent: campaign.percent)
        #endif
        guard LeeoSale.isDue(now: Date()) else { return }
        LeeoSale.markShown()
        offer = found
    }
}

struct LeeoSaleBannerView: View {
    let offer: LeeoSaleOffer
    let onClose: () -> Void
    let onSnooze: () -> Void
    let onOpen: () -> Void

    private let ground = Color(red: 0.078, green: 0.086, blue: 0.122)
    private let card = Color(red: 0.122, green: 0.133, blue: 0.188)
    private let chip = Color(red: 0.149, green: 0.161, blue: 0.220)
    private let gold = Color(red: 0.961, green: 0.710, blue: 0.267)
    private let text = Color(red: 0.957, green: 0.945, blue: 0.918)
    private let muted = Color(red: 0.788, green: 0.773, blue: 0.737)

    private var isLive: Bool { offer.phase == .live }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ground.ignoresSafeArea()

            VStack(spacing: 0) {
                // 보통은 가운데에 둔다. 글자를 크게 쓰는 사람에게만 스크롤이 생긴다.
                ViewThatFits(in: .vertical) {
                    VStack { Spacer(minLength: 0); content; Spacer(minLength: 0) }
                    ScrollView { content }
                }
                buttons
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(chip))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("닫기", comment: "Sale banner: close button accessibility label"))
            .padding(.trailing, 20)
            .padding(.top, 12)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            AccessibilityNotification.Announcement("\(offer.campaign.title) \(offer.percent)%").post()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 26) {
            LeeoSaleAppIcon()
            badge
            VStack(alignment: .leading, spacing: 4) {
                Text(offer.campaign.title)
                    .font(.title.bold())
                Text(L("첫 구독", comment: "Sale banner: small line above the headline, 'for your first subscription'"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(muted)
                Text(headline)
                    .font(.title.bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)

            Text(message)
                .font(.body)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)

            if let deal = offer.best { dealCard(deal) }
        }
        .foregroundStyle(text)
        .frame(maxWidth: 480, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 72)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    /// "최대 80% 할인" — 언어마다 어순이 달라 한 문장으로 번역하고, 숫자만 크게 칠한다.
    private var headline: AttributedString {
        let number = offer.percent.formatted(.percent.scale(1))
        var text = AttributedString(String(format: L("최대 %@ 할인", comment: "Sale banner headline. %@ = discount such as '80%'. Keep it short: 'Up to 80% off'"), number))
        if let range = text.range(of: number) {
            text[range].font = .system(size: 88, weight: .black, design: .rounded)
            text[range].foregroundColor = gold
        }
        return text
    }

    private var badge: some View {
        Text(badgeText)
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isLive ? ground : gold)
            .background {
                if isLive {
                    Capsule().fill(gold)
                } else {
                    Capsule().strokeBorder(gold, lineWidth: 1.5)
                }
            }
    }

    private var badgeText: String {
        if isLive {
            return offer.campaign.daysLeft(on: Date()) == 0
                ? L("오늘 마지막 날", comment: "Sale banner badge: today is the last day of the sale")
                : L("지금 할인 중", comment: "Sale banner badge: the sale is on now")
        }
        let start = offer.campaign.startDate()?.formatted(.dateTime.month(.wide).day().weekday(.wide)) ?? offer.campaign.start
        return String(format: L("곧 시작해요 · %@", comment: "Sale banner badge before the sale. %@ = start date such as 'Friday, November 27'"), start)
    }

    private var message: String {
        let end = offer.campaign.endDate()?.formatted(.dateTime.month(.wide).day()) ?? offer.campaign.end
        if isLive {
            return String(format: L("%@까지 처음 구독하면 할인된 값으로 시작할 수 있어요.", comment: "Sale banner body during the sale. %@ = end date such as 'December 4'"), end)
        }
        let start = offer.campaign.startDate()?.formatted(.dateTime.month(.wide).day()) ?? offer.campaign.start
        return String(format: L("%1$@부터 %2$@까지 처음 구독하면 할인된 값으로 시작할 수 있어요.", comment: "Sale banner body before the sale. %1$@ = start date, %2$@ = end date"), start, end)
    }

    private func dealCard(_ deal: LeeoSaleOffer.Deal) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(deal.name).foregroundStyle(muted)
                Spacer()
                Text(deal.regularPrice)
                    .strikethrough()
                    .foregroundStyle(muted.opacity(0.8))
                    .accessibilityLabel(String(format: L("원래 %@", comment: "Sale banner: accessibility label for the regular price. %@ = price"), deal.regularPrice))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(deal.periodLabel).foregroundStyle(muted)
                Spacer()
                Text(deal.offerPrice).font(.title2.bold())
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(card))
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button(action: onOpen) {
                Text(isLive ? L("할인 값으로 시작하기", comment: "Sale banner: main button during the sale, opens the plans")
                            : L("요금제 미리 보기", comment: "Sale banner: main button before the sale, opens the plans"))
                    .font(.headline)
                    .foregroundStyle(ground)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(gold))
            }
            .buttonStyle(.plain)
            Button(action: onSnooze) {
                Text(L("3일 동안 보지 않기", comment: "Sale banner: hide the banner for three days"))
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(ground)
    }
}

/// 이 앱의 아이콘. 못 찾으면 그리지 않는다.
struct LeeoSaleAppIcon: View {
    var body: some View {
        if let image = Self.image {
            image
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private static var image: Image? {
        #if canImport(UIKit)
        guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] else { return nil }
        let names = (primary["CFBundleIconFiles"] as? [String]) ?? []
        let candidates = names.reversed() + [(primary["CFBundleIconName"] as? String)].compactMap { $0 }
        for name in candidates {
            if let ui = UIImage(named: name) { return Image(uiImage: ui) }
        }
        return nil
        #elseif canImport(AppKit)
        return Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        return nil
        #endif
    }
}
#endif
