//
//  LeeoTipJarView.swift
//  LeeoKit
//
//  팁을 내는 화면. 무엇을 위한 돈인지(기능이 아니라 앱을 계속 다듬는 데) 먼저 말하고,
//  작은 것부터 큰 것까지 고르게 한다. 낸 뒤에는 같은 자리에서 고맙다고 말한다.
//  응원 단계(`LeeoSupporterLevel`)와 단계마다 받는 것을 늘 보여 주고, 연 보상(아이콘 · 한 표 · 베타)은 여기서 쓴다.
//
//  설정에서 한 줄:
//      if let tipJar = store.tipJar, tipJar.isAvailable {
//          NavigationLink(LeeoTipText.entry) { LeeoTipJarView<MyAppSpec>(tipJar: tipJar) }
//      }
//

import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif

// MARK: - 앱이 쓰는 문구

public enum LeeoTipText {
    /// 설정 행 이름.
    public static var entry: String { L("개발자 응원하기", comment: "Tip jar: settings entry") }
    /// 설정 행 아래 한 줄.
    public static var entrySubtitle: String {
        L("기능은 그대로, 앱을 더 다듬는 데 쓰여요", comment: "Tip jar: settings entry subtitle")
    }
}

// MARK: - 화면

public struct LeeoTipJarView<Spec: LeeoAppSpec>: View {
    @ObservedObject private var tipJar: LeeoTipJar
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    #if canImport(StoreKit)
    @Environment(\.purchase) private var purchaseAction
    #endif

    #if os(iOS)
    @State private var iconName: String? = UIApplication.shared.alternateIconName
    #endif

    /// 미리보기 가격(작은 것부터). 있으면 상품을 기다리지 않고 이 값으로 칸을 그리며, 눌러도 결제하지 않는다.
    private let previewPrices: [String]?

    public init(tipJar: LeeoTipJar) {
        self.tipJar = tipJar
        self.previewPrices = nil
    }

    /// **결제하지 않는** 미리보기. 인앱 상품 심사 이미지 · SwiftUI 미리보기처럼 StoreKit 상품이 없는 곳에서
    /// 화면을 그대로 그린다. 칸은 주어진 가격을 보여 주기만 한다.
    public init(previewPrices: [String]) {
        self.tipJar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: previewPrices.indices.map { "leeo.preview.tip.\($0)" }),
                                 defaults: UserDefaults(suiteName: "leeo.preview.tip") ?? .standard)
        self.previewPrices = previewPrices
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if tipJar.justTipped { thanks }
                levelCard
                if tipJar.hasTipped, let page = tipJar.config.thanksPage { thanksList(page) }
                tiers
                if let error = tipJar.lastError {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Text(L("한 번만 결제돼요. 구독이 아니고, 열리는 기능도 없어요.",
                       comment: "Tip jar: footnote, one-time payment that unlocks nothing"))
                    .font(.body)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(LeeoTipText.entry)
        .task {
            guard previewPrices == nil else { return }
            #if canImport(StoreKit)
            await tipJar.loadProducts()
            #endif
            await tipJar.syncSupporter(containerIdentifier: Spec.feedback.containerIdentifier)
        }
        .onDisappear { tipJar.justTipped = false }
        // 고맙다는 카드는 화면 위쪽에 조용히 선다. 결제 시트에서 돌아온 VoiceOver 사용자에게도 말해 준다.
        .onChange(of: tipJar.justTipped) { _, tipped in
            if tipped { AccessibilityNotification.Announcement(thanksTitle).post() }
        }
    }

    // MARK: 부분

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 84, height: 84)
                .background(Circle().fill(theme.accent.opacity(0.14)))
                .accessibilityHidden(true)
            Text(String(format: L("%@ 개발을 응원해 주세요", comment: "Tip jar: title. %@ = app name"), Spec.displayName))
                .font(.title2.bold())
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(L("이미 모든 기능을 쓰고 계신다면, 여기서 조금 더 응원할 수 있어요. 혼자 만드는 앱이라 한 번 한 번이 다음 업데이트를 만드는 힘이 돼요.",
                   comment: "Tip jar: explanation for people who already have everything"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var thanksTitle: String { L("고마워요! 큰 힘이 돼요.", comment: "Tip jar: thank-you title right after tipping") }

    private var thanks: some View {
        VStack(spacing: 6) {
            Text(thanksTitle)
                .font(.headline)
                .foregroundStyle(theme.text)
            Text(String(format: L("지금까지 %d번 응원해 주셨어요.", comment: "Tip jar: how many times this person has tipped"),
                        tipJar.tipCount))
                .font(.body)
                .foregroundStyle(theme.textMuted)
            // 개발자의 짧은 편지
            Text(L("혼자 만드는 앱이라 보내 주신 응원을 하나하나 다 보고 있어요. 다음 업데이트로 꼭 보답할게요.",
                   comment: "Tip jar: short letter from the developer right after tipping"))
                .font(.body)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text(L("— 만든 사람 드림", comment: "Tip jar: signature under the developer's letter"))
                .font(.body.italic())
                .foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous)
            .fill(theme.accent.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    /// '고마운 사람들' — 응원한 사람이 앱 소개 페이지에 이름을 올릴 수 있다고 알려 준다.
    /// 이름은 메일로 받아 개발자가 주문 번호로 확인한 뒤 손으로 올린다(서버 없음). 그래서 버튼은 메일 쓰기다.
    private func thanksList(_ page: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("고마운 사람들에 이름 올리기", comment: "Tip jar: thank-you list card title"),
                  systemImage: "person.2.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.text)
            Text(L("앱 소개 페이지의 '고마운 사람들'에 이름을 올려 드려요. 올리고 싶은 이름과 App Store 영수증 메일의 주문 번호(Order ID)를 보내 주세요.",
                   comment: "Tip jar: thank-you list card explanation"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { thanksButtons(page) }
                VStack(alignment: .leading, spacing: 10) { thanksButtons(page) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.surface))
    }

    @ViewBuilder
    private func thanksButtons(_ page: URL) -> some View {
        if let mail = mail(subject: L("[고마운 사람들] %@", comment: "Tip jar: thank-you list mail subject. %@ = app name"),
                           body: L("올리고 싶은 이름:\n주문 번호(Order ID):\n",
                                   comment: "Tip jar: thank-you list mail body with two blanks to fill in")) {
            Link(destination: mail) {
                pill(L("이름 보내기", comment: "Tip jar: button that opens a mail to send the name for the thank-you list"), filled: true)
            }
        }
        Link(destination: page) {
            pill(L("고마운 사람들 보기", comment: "Tip jar: button that opens the thank-you list on the app's web page"), filled: false)
        }
    }

    private func pill(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? Color.white : theme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(filled ? theme.accent : Color.clear))
            .overlay(Capsule().stroke(theme.accent, lineWidth: filled ? 0 : 1.5))
    }

    /// 개발자에게 가는 메일. `subject` 의 %@ 에 앱 이름이 들어간다.
    private func mail(subject: String, body: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Spec.developerEmail
        c.queryItems = [
            URLQueryItem(name: "subject", value: String(format: subject, Spec.displayName)),
            URLQueryItem(name: "body", value: body),
        ]
        return c.url
    }

    // MARK: 응원 단계

    /// 단계 사다리. 지금 단계 · 다음 단계까지 남은 점수 · 단계마다 받는 것. 아직 안 낸 사람에게도 보인다
    /// (무엇을 받는지 미리 안다). 기능은 열지 않으므로 '산다'가 아니라 '쌓인다'로 말한다.
    private var levelCard: some View {
        let level = tipJar.level
        let next: LeeoSupporterLevel? = level == nil ? .supporter : level?.next
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: level?.symbol ?? "heart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text(level?.title ?? L("응원 단계", comment: "Supporter: level card title before the first tip"))
                    .font(.headline)
                    .foregroundStyle(theme.text)
                Spacer(minLength: 8)
                if tipJar.points > 0 {
                    Text(String(format: L("%d점", comment: "Supporter: points. %d = points"), tipJar.points))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.accent)
                }
            }
            .accessibilityElement(children: .combine)
            if let next {
                ProgressView(value: Double(min(tipJar.points, next.need)), total: Double(next.need))
                    .tint(theme.accent)
                    .accessibilityHidden(true)
                Text(String(format: L("%1$@까지 %2$d점 남았어요", comment: "Supporter: points left to the next level. %1$@ = level, %2$d = points"),
                            next.title, next.need - tipJar.points))
                    .font(.body)
                    .foregroundStyle(theme.textMuted)
            } else {
                Text(L("가장 높은 단계예요. 늘 고마워요.", comment: "Supporter: reached the top level"))
                    .font(.body)
                    .foregroundStyle(theme.textMuted)
            }
            ForEach(LeeoSupporterLevel.allCases, id: \.self) { l in
                let reached = level.map { $0 >= l } ?? false
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(reached ? theme.accent : theme.textMuted)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: L("%1$@ · %2$d점부터", comment: "Supporter: level row. %1$@ = level, %2$d = points needed"),
                                    l.title, l.need))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.text)
                        Text(l.perks)
                            .font(.body)
                            .foregroundStyle(theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(reached ? .isSelected : [])
            }
            Text(L("커피 한 잔 1점 · 간식 한 번 3점 · 든든한 한 끼 10점. 리이오의 모든 앱에서 낸 응원을 합쳐요.",
                   comment: "Supporter: how points are counted"))
                .font(.body)
                .foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            rewards
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.surface))
    }

    /// 연 보상. 단골: 후원자 아이콘 · 다음 기능에 한 표, 후견인: 베타.
    @ViewBuilder
    private var rewards: some View {
        if let level = tipJar.level, level >= .regular {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { rewardButtons(level) }
                VStack(alignment: .leading, spacing: 10) { rewardButtons(level) }
            }
        }
    }

    @ViewBuilder
    private func rewardButtons(_ level: LeeoSupporterLevel) -> some View {
        #if os(iOS)
        if let icon = tipJar.config.supporterIcon, UIApplication.shared.supportsAlternateIcons {
            let using = iconName == icon
            Button {
                let target = using ? nil : icon
                UIApplication.shared.setAlternateIconName(target) { error in
                    if error == nil { Task { @MainActor in iconName = target } }
                }
            } label: {
                pill(using ? L("원래 아이콘으로", comment: "Supporter reward: switch back to the default app icon")
                           : L("후원자 아이콘 쓰기", comment: "Supporter reward: use the supporter-only app icon"), filled: !using)
            }
            .buttonStyle(.plain)
        }
        #endif
        if let vote = mail(subject: L("[한 표] %@", comment: "Supporter reward: vote mail subject. %@ = app name"), body: voteBody) {
            Link(destination: vote) {
                pill(L("다음 기능에 한 표", comment: "Supporter reward: vote for the next feature"), filled: false)
            }
        }
        if level >= .patron,
           let beta = tipJar.config.betaURL
            ?? mail(subject: L("[베타 신청] %@", comment: "Supporter reward: beta request mail subject. %@ = app name"),
                    body: L("TestFlight 초대를 받을 이메일:\n", comment: "Supporter reward: beta request mail body")) {
            Link(destination: beta) {
                pill(L("베타 함께하기", comment: "Supporter reward: join the TestFlight beta"), filled: false)
            }
        }
    }

    /// 한 표 메일 본문. 만들고 있거나 다음에 만들 기능을 미리 보여 주고 하나 고르게 한다.
    private var voteBody: String {
        let items = (Spec.roadmap.building + Spec.roadmap.planned).map { "- \($0.title)" }
        return ([L("가장 기다리는 기능을 하나 골라 남겨 주세요.", comment: "Supporter reward: vote mail body")] + [""] + items)
            .joined(separator: "\n") + "\n"
    }

    @ViewBuilder
    private var tiers: some View {
        if let previewPrices {
            VStack(spacing: 10) {
                ForEach(Array(previewPrices.enumerated()), id: \.offset) { index, price in
                    tierRow(tier: LeeoTipTier(index: index, of: previewPrices.count), price: price) {}
                }
            }
        } else {
            storeTiers
        }
    }

    @ViewBuilder
    private var storeTiers: some View {
        #if canImport(StoreKit)
        if tipJar.products.isEmpty {
            ProgressView().padding(.vertical, 24)
        } else {
            VStack(spacing: 10) {
                ForEach(Array(tipJar.products.enumerated()), id: \.element.id) { index, product in
                    tierRow(tier: tipJar.tier(for: product.id, fallbackIndex: index), price: product.displayPrice) {
                        Task { await tipJar.purchase(product, using: { try await purchaseAction($0) }) }
                    }
                }
            }
        }
        #endif
    }

    private func tierRow(tier: LeeoTipTier, price: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: tier.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                // 아주 큰 글자에서는 가격을 이름 아래로 내린다. 옆에 두면 이름이 몇 글자 폭으로 눌린다.
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tier.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        priceTag(price)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text(tier.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    priceTag(price)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tipJar.isWorking)
        .accessibilityLabel("\(tier.title), \(price)")
        .accessibilityInputLabels([Text(tier.title)])
    }

    /// ⚠️ 가격은 **한 줄**이다. 자리가 모자라면 이름 쪽이 줄을 바꾸거나 작아진다.
    ///    (가격이 두 줄로 꺾이면 "₩1," / "100" 처럼 읽혀 얼마인지 헷갈린다)
    private func priceTag(_ price: String) -> some View {
        Text(price)
            .font(.body.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(theme.accent))
            .layoutPriority(1)
    }
}

// MARK: - 단계

/// 팁 한 칸의 이름과 그림. 상품 이름은 App Store Connect 에서 언어마다 따로 적어야 해서 쓰지 않고,
/// **계약에 적은 순서**로 이름을 붙인다(작은 것 · 중간 · 큰 것). 계약에 둘이면 작은 것과 큰 것만 쓴다.
///
/// ⚠️ 불러온 상품 수가 아니라 **계약의 자리**로 정한다(`LeeoTipJar.tier(for:)`). 상품은 한 번에 하나씩 출시될 수 있다.
///    small · medium 만 나와 있을 때 불러온 수(2)로 정하면 medium 이 "큰 것" 이름을 단다.
struct LeeoTipTier: Equatable {
    enum Size: Equatable { case small, medium, large }
    let size: Size

    init(index: Int, of count: Int) {
        switch (index, count) {
        case (0, _): size = .small
        case (let i, let n) where i == n - 1: size = .large
        default: size = .medium
        }
    }

    var title: String {
        switch size {
        case .small:  return L("커피 한 잔", comment: "Tip jar: smallest tip")
        case .medium: return L("간식 한 번", comment: "Tip jar: middle tip")
        case .large:  return L("든든한 한 끼", comment: "Tip jar: largest tip")
        }
    }

    var symbol: String {
        switch size {
        case .small:  return "cup.and.saucer.fill"
        case .medium: return "birthday.cake.fill"
        case .large:  return "fork.knife"
        }
    }
}
