//
//  LeeoTipJarView.swift
//  LeeoKit
//
//  팁을 내는 화면. 무엇을 위한 돈인지(기능이 아니라 앱을 계속 다듬는 데) 먼저 말하고,
//  작은 것부터 큰 것까지 고르게 한다. 낸 뒤에는 같은 자리에서 고맙다고 말한다.
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
    #if canImport(StoreKit)
    @Environment(\.purchase) private var purchaseAction
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
                tiers
                if let error = tipJar.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Text(L("한 번만 결제돼요. 구독이 아니고, 열리는 기능도 없어요.",
                       comment: "Tip jar: footnote, one-time payment that unlocks nothing"))
                    .font(.footnote)
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
        }
        .onDisappear { tipJar.justTipped = false }
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

    private var thanks: some View {
        VStack(spacing: 6) {
            Text(L("고마워요! 큰 힘이 돼요.", comment: "Tip jar: thank-you title right after tipping"))
                .font(.headline)
                .foregroundStyle(theme.text)
            Text(String(format: L("지금까지 %d번 응원해 주셨어요.", comment: "Tip jar: how many times this person has tipped"),
                        tipJar.tipCount))
                .font(.subheadline)
                .foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous)
            .fill(theme.accent.opacity(0.12)))
        .accessibilityElement(children: .combine)
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
                Text(tier.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                // ⚠️ 가격은 **한 줄**이다. 자리가 모자라면 이름 쪽이 줄을 바꾸거나 작아진다.
                //    (가격이 두 줄로 꺾이면 "₩1," / "100" 처럼 읽혀 얼마인지 헷갈린다)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tipJar.isWorking)
        .accessibilityLabel("\(tier.title), \(price)")
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
