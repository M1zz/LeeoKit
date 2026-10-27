//
//  LeeoLadderViews.swift
//  LeeoKit
//
//  세 칸 요금제의 공통 화면 부품. 앱의 페이월이 칸 카드 안에 끼워 쓴다.
//
//   · `LeeoTermPicker`          칸마다 연 구독 / 평생 고르기, 첫 해 할인 · "연 구독 N년치" 한 줄
//   · `LeeoLifetimePriceNotice` 평생 가격이 오르기 전 한 줄
//   · `LeeoGraduationOfferView` 구독 졸업 평생가(구독 중인 사람에게만)
//   · `LeeoForeverPassLine`     세 칸 아래 "모든 앱 평생으로 열기" 한 줄과 그 화면
//
//  ⚠️ 결제는 `@Environment(\.purchase)` 로 한다(아이패드에서 결제 시트가 엉뚱한 창에 뜨지 않게).
//     산 뒤 앱의 권한을 다시 읽는 일은 앱이 `onPurchased` 로 받는다.
//

import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif

#if canImport(StoreKit)

// MARK: - 결제 한 번

/// 결제하고 확인된 결제를 마친다. 권한이 생겼으면 true.
@MainActor
func leeoBuy(_ product: Product, using purchase: PurchaseAction) async -> Bool {
    guard let result = try? await purchase(product) else { return false }
    guard case .success(let verification) = result, case .verified(let tx) = verification else { return false }
    await tx.finish()
    return true
}

// MARK: - 연 구독 / 평생

/// 유료 칸 하나의 두 가지 길. 칸 카드 안에 넣는다.
///
/// 연 구독을 고르면 처음 보는 사람에게 첫 해 할인을, 평생을 고르면 "연 구독 N년치, 한 번만 내면 끝" 을 보인다.
public struct LeeoTermPicker: View {
    @Binding private var term: LeeoPlanTerm
    private let yearly: Product?
    private let lifetime: Product?
    @Environment(\.leeoStyle) private var theme
    @State private var introEligible = false

    public init(term: Binding<LeeoPlanTerm>, yearly: Product?, lifetime: Product?) {
        self._term = term
        self.yearly = yearly
        self.lifetime = lifetime
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                option(.yearly, title: LeeoLadderText.yearly,
                       price: yearly.map { String(format: LeeoLadderText.perYearFormat, $0.displayPrice) })
                option(.lifetime, title: LeeoLadderText.lifetime, price: lifetime?.displayPrice)
            }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: yearly?.id) {
            introEligible = await yearly?.subscription?.isEligibleForIntroOffer ?? false
        }
    }

    private var note: String? {
        switch term {
        case .yearly:
            guard introEligible, let offer = yearly?.subscription?.introductoryOffer,
                  offer.paymentMode == .payUpFront || offer.paymentMode == .payAsYouGo else { return nil }
            return String(format: LeeoLadderText.introFormat, offer.displayPrice)
        case .lifetime:
            guard let years = LeeoLadderText.yearsCovered(yearly: yearly?.price, lifetime: lifetime?.price) else { return nil }
            return String(format: LeeoLadderText.lifetimeWorthFormat, years)
        }
    }

    private func option(_ value: LeeoPlanTerm, title: String, price: String?) -> some View {
        let selected = term == value
        return Button {
            term = value
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(price ?? " ")
                    .font(.footnote)
                    .monospacedDigit()
            }
            .foregroundStyle(selected ? theme.accent : theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: theme.radiusSm, style: .continuous)
                    .fill(selected ? theme.accent.opacity(0.12) : theme.surfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.radiusSm, style: .continuous)
                    .strokeBorder(selected ? theme.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(price == nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 구독 졸업

/// 구독 중인 사람에게 보이는 졸업가. 사면 구독 관리 화면으로 해지를 돕는다.
///
/// ⚠️ App Store 는 구독을 저절로 해지하거나 남은 기간을 돌려주지 않는다. 그래서 산 뒤 해지를 **안내만** 한다.
public struct LeeoGraduationOfferView: View {
    private let graduate: Product?
    private let onPurchased: @MainActor () async -> Void
    @Environment(\.leeoStyle) private var theme
    @Environment(\.purchase) private var purchase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var buying = false
    @State private var bought = false
    @State private var showsManage = false

    public init(graduate: Product?, onPurchased: @escaping @MainActor () async -> Void) {
        self.graduate = graduate
        self.onPurchased = onPurchased
    }

    public var body: some View {
        VStack(spacing: 18) {
            Image(systemName: bought ? "checkmark.seal.fill" : "graduationcap.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 80, height: 80)
                .background(Circle().fill(theme.accent.opacity(0.14)))
                .accessibilityHidden(true)
            Text(bought ? LeeoLadderText.graduatedTitle : LeeoLadderText.graduateTitle)
                .font(.title2.bold())
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(bought ? LeeoLadderText.graduatedBody : LeeoLadderText.graduateBody)
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if bought {
                Button(LeeoLadderText.manageSubscription) {
                    #if os(iOS)
                    showsManage = true
                    #else
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                    #endif
                }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            } else if let graduate {
                Button {
                    Task {
                        buying = true
                        if await leeoBuy(graduate, using: purchase) {
                            await onPurchased()
                            bought = true
                        }
                        buying = false
                    }
                } label: {
                    Text(String(format: LeeoLadderText.switchToLifetimeFormat, graduate.displayPrice))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(buying)
                Text(LeeoLadderText.graduateFootnote)
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView()
            }
            Button(bought ? LeeoLadderText.done : LeeoLadderText.later) { dismiss() }
                .foregroundStyle(theme.textMuted)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $showsManage)
        #endif
    }
}

// MARK: - 언제나 평생 패스

/// 세 칸 아래 한 줄. 누르면 패스 화면이 뜬다.
public struct LeeoForeverPassLine: View {
    @ObservedObject private var pass: LeeoForeverPass
    private let ownsLifetimePro: Bool
    @Environment(\.leeoStyle) private var theme
    @State private var showsPass = false

    /// - Parameter ownsLifetimePro: 이 앱의 평생 Pro 를 이미 샀는가. 그러면 패스를 올리기 값으로 판다.
    public init(pass: LeeoForeverPass, ownsLifetimePro: Bool = false) {
        self.pass = pass
        self.ownsLifetimePro = ownsLifetimePro
    }

    public var body: some View {
        Button { showsPass = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "infinity")
                    .accessibilityHidden(true)
                Text(LeeoLadderText.passLine)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.textFaint)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsPass) {
            LeeoForeverPassView(pass: pass, ownsLifetimePro: ownsLifetimePro)
        }
    }
}

/// 언제나 평생 패스 화면.
public struct LeeoForeverPassView: View {
    @ObservedObject private var pass: LeeoForeverPass
    private let ownsLifetimePro: Bool
    @Environment(\.leeoStyle) private var theme
    @Environment(\.purchase) private var purchase
    @Environment(\.dismiss) private var dismiss
    @State private var buying: String?
    @State private var checking = false

    public init(pass: LeeoForeverPass, ownsLifetimePro: Bool = false) {
        self.pass = pass
        self.ownsLifetimePro = ownsLifetimePro
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: pass.isActive ? "checkmark.seal.fill" : "infinity")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(theme.accent.opacity(0.14)))
                    .accessibilityHidden(true)
                Text(LeeoLadderText.passTitle)
                    .font(.title2.bold())
                    .foregroundStyle(theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(pass.isActive ? LeeoLadderText.passActiveBody : LeeoLadderText.passBody)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !pass.isActive { buttons }
                Button {
                    Task { checking = true; await pass.refresh(); checking = false }
                } label: {
                    if checking { ProgressView() } else { Text(LeeoLadderText.passFind) }
                }
                .font(.footnote)
                .foregroundStyle(theme.accent)
                .frame(minHeight: 44)
                Text(LeeoLadderText.passFootnote)
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(LeeoLadderText.done) { dismiss() }
                    .foregroundStyle(theme.textMuted)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await pass.loadProducts() }
    }

    @ViewBuilder
    private var buttons: some View {
        let lifetime = ownsLifetimePro ? (pass.product(.upgrade) ?? pass.product(.lifetime)) : pass.product(.lifetime)
        VStack(spacing: 10) {
            if let lifetime {
                buyButton(lifetime, title: String(format: LeeoLadderText.passLifetimeFormat, lifetime.displayPrice), prominent: true)
            }
            if let yearly = pass.product(.yearly) {
                buyButton(yearly, title: String(format: LeeoLadderText.passYearlyFormat, yearly.displayPrice), prominent: false)
            }
            if lifetime == nil && pass.product(.yearly) == nil { ProgressView() }
        }
    }

    private func buyButton(_ product: Product, title: String, prominent: Bool) -> some View {
        Button {
            Task {
                buying = product.id
                if await leeoBuy(product, using: purchase) { await pass.refresh() }
                buying = nil
            }
        } label: {
            Text(title)
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .modifier(LeeoProminence(prominent: prominent, tint: theme.accent))
        .disabled(buying != nil)
    }
}

private struct LeeoProminence: ViewModifier {
    let prominent: Bool
    let tint: Color
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent).tint(tint)
        } else {
            content.buttonStyle(.bordered).tint(tint)
        }
    }
}

#endif

// MARK: - 평생 가격 안내

/// 평생 가격이 오르기 전까지 페이월에 서는 한 줄. 날짜가 지나면 아무것도 그리지 않는다.
public struct LeeoLifetimePriceNotice: View {
    @Environment(\.leeoStyle) private var theme

    public init() {}

    public var body: some View {
        if LeeoLadderSchedule.showsLifetimeNotice() {
            Label {
                Text(String(format: LeeoLadderText.priceNoticeFormat,
                            LeeoLadderSchedule.lifetimePriceChange.formatted(.dateTime.month(.wide).day())))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "calendar.badge.clock")
            }
            .font(.footnote)
            .foregroundStyle(theme.textMuted)
        }
    }
}

// MARK: - 문구

public enum LeeoLadderText {
    public static var yearly: String { L("연 구독", comment: "Pricing ladder: yearly subscription option") }
    public static var lifetime: String { L("평생", comment: "Pricing ladder: one-time lifetime purchase option") }
    /// %@ = 연 가격
    public static var perYearFormat: String { L("%@ / 년", comment: "Pricing ladder: yearly price. %@ = price") }
    /// %@ = 첫 해 가격
    public static var introFormat: String { L("처음이면 첫 해 %@", comment: "Pricing ladder: first-year intro price for new subscribers. %@ = price") }
    /// %d = 평생 값이 연 구독 몇 년치인가
    public static var lifetimeWorthFormat: String {
        L("연 구독 %d년치, 한 번만 내면 끝", comment: "Pricing ladder: lifetime equals N years of the subscription. %d = years")
    }

    /// 평생 값이 연 구독 몇 년치인가(내림). 2년치가 안 되면 말하지 않는다.
    static func yearsCovered(yearly: Decimal?, lifetime: Decimal?) -> Int? {
        guard let yearly, let lifetime, yearly > 0 else { return nil }
        // ⚠️ `NSDecimalNumber.intValue` 는 자릿수가 긴 몫(3.0588…)에서 엉뚱한 값을 낸다. double 로 내린다.
        let years = Int(NSDecimalNumber(decimal: lifetime / yearly).doubleValue.rounded(.down))
        return years >= 2 ? years : nil
    }

    public static var graduateTitle: String { L("구독을 평생으로 바꿀까요?", comment: "Graduation offer: title for subscribers") }
    public static var graduateBody: String {
        L("지금까지 구독해 주셔서 고마워요. 구독하신 분께만 평생을 낮은 값에 드려요. 한 번만 내면 더는 갱신되지 않아요.",
          comment: "Graduation offer: body")
    }
    /// %@ = 졸업가
    public static var switchToLifetimeFormat: String { L("평생으로 바꾸기 %@", comment: "Graduation offer: buy button. %@ = price") }
    public static var graduateFootnote: String {
        L("평생을 사도 구독은 저절로 멈추지 않아요. 산 뒤 구독 관리에서 해지해 주세요. 남은 기간은 그대로 써요.",
          comment: "Graduation offer: the subscription must be cancelled by the user")
    }
    public static var graduatedTitle: String { L("이제 평생 쓰세요", comment: "Graduation offer: title after buying") }
    public static var graduatedBody: String {
        L("구독은 아직 켜져 있어요. 구독 관리에서 해지하면 다음 갱신부터 더 내지 않아요.",
          comment: "Graduation offer: body after buying, asks to cancel the subscription")
    }
    public static var manageSubscription: String { L("구독 관리 열기", comment: "Graduation offer: open App Store subscription management") }
    /// 설정의 구독 관리 아래에 늘 서는 줄.
    public static var switchToLifetimeEntry: String { L("평생으로 바꾸기", comment: "Settings row: switch a subscription to lifetime") }
    public static var later: String { L("다음에", comment: "Pricing ladder: dismiss for now") }
    public static var done: String { L("닫기", comment: "Pricing ladder: close") }

    public static var passLine: String { L("모든 앱 평생으로 열기", comment: "Forever pass: one line under the plans") }
    public static var passTitle: String { L("언제나 평생 패스", comment: "Forever pass: name") }
    public static var passBody: String {
        L("한 번 사면 이 개발자의 모든 앱이 Plus · Pro 평생으로 열려요. 앞으로 나올 앱과 기능도 따로 사지 않아요.",
          comment: "Forever pass: what it unlocks")
    }
    public static var passActiveBody: String {
        L("패스가 열려 있어요. 이 앱의 모든 기능을 평생 쓰세요.", comment: "Forever pass: already active")
    }
    /// %@ = 가격
    public static var passLifetimeFormat: String { L("평생 %@", comment: "Forever pass: lifetime buy button. %@ = price") }
    /// %@ = 가격
    public static var passYearlyFormat: String { L("연 %@", comment: "Forever pass: yearly buy button. %@ = price") }
    public static var passFind: String { L("다른 앱에서 산 패스 찾기", comment: "Forever pass: re-check a pass bought in another app") }
    public static var passFootnote: String {
        L("같은 Apple 계정의 iCloud 로 다른 앱에서도 열려요. 산 앱을 한 번 열어 두면 다른 앱이 찾아요.",
          comment: "Forever pass: how other apps find the pass")
    }
    /// %@ = 날짜
    public static var priceNoticeFormat: String {
        L("평생 가격이 %@부터 올라요. 이미 산 분은 그대로 써요.", comment: "Pricing ladder: lifetime price increase notice. %@ = date")
    }
}
