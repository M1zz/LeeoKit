//
//  LeeoPaywallView.swift
//  LeeoKit
//
//  앱마다 새로 만들지 않는 표준 페이월 화면. 상품 로드/구매/복원/권한은 LeeoStore 가
//  처리하고, 이 화면은 그 위에 테마(.leeoStyle) 룩을 입힌 UI만 얹는다.
//  헤드라인·부제·혜택 문구는 앱이 넘길 수 있고, 없으면 무난한 기본 문구를 쓴다.
//
//  사용 예:
//      // 1) 시트로 (가장 흔함) — Spec.paywall 을 자동으로 사용
//      SomeView()
//          .leeoPaywallSheet(MyAppSpec.self, isPresented: $showPaywall) {
//              // 구매 성공 콜백 (선택)
//          }
//
//      // 2) 화면 직접 배치
//      LeeoPaywallView<MyAppSpec>(
//          features: ["광고 제거", "무제한 저장", "프리미엄 테마"]
//      )
//      .leeoStyle(myTheme)
//

import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif

public struct LeeoPaywallView<Spec: LeeoAppSpec>: View {
    private let title: String
    private let subtitle: String
    private let features: [String]
    /// 기능 그림 (`LeeoShowcase`). 있으면 글 대신 이것을 넘겨 보인다.
    private let showcases: [LeeoShowcase]
    private let leadIcon: String
    private let onPurchased: (() -> Void)?
    /// 어떤 계기로 페이월이 떴는지 (분석 이벤트용). 리드 기능이 있으면 그 이름.
    private let analyticsReason: String?
    /// 방금 부딪힌 기능의 게이트 키 — 등급을 쓰는 앱이면 그 기능을 여는 등급을 먼저 보여 준다.
    private let leadKey: String?

    @StateObject private var store: LeeoStore
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedProductID: String?
    /// 등급을 쓰는 앱에서 지금 보고 있는 등급
    @State private var selectedTierID: String?

    private let hasConfig: Bool

    /// - Parameters:
    ///   - title: 큰 제목. 기본 "{앱이름} 프리미엄".
    ///   - subtitle: 부제. 기본 "모든 기능을 잠금 해제하세요".
    ///   - features: 혜택 불릿 목록 (체크 아이콘으로 노출). 비우면 혜택 섹션을 숨긴다.
    ///   - config: 상품 구성. 기본은 `Spec.paywall` — 앱 계약에 지정한 값을 그대로 쓴다.
    ///   - onPurchased: 구매(또는 복원으로 권한 확보) 성공 시 호출.
    public init(
        title: String? = nil,
        subtitle: String? = nil,
        features: [String] = [],
        leadFeature: LeeoProFeature? = nil,
        showcases: [LeeoShowcase] = [],
        config: LeeoPaywallConfig? = Spec.paywall,
        onPurchased: (() -> Void)? = nil
    ) {
        self.showcases = showcases
        // 리드 기능이 있으면 "방금 부딪힌 그 기능"을 팔도록 헤더/문구를 맞춘다.
        self.title = title ?? leadFeature?.leeoTitle
            ?? String(format: L("%@ 프리미엄", comment: "Paywall default title"), Spec.displayName)
        self.subtitle = subtitle ?? leadFeature?.leeoDetail
            ?? L("모든 기능을 잠금 해제하세요.", comment: "Paywall default subtitle")
        self.features = features
        self.leadIcon = leadFeature?.leeoIcon ?? "crown.fill"
        self.onPurchased = onPurchased
        self.analyticsReason = leadFeature?.leeoTitle
        self.leadKey = leadFeature?.leeoKey
        // config 가 없으면 빈 구성으로라도 안전하게 만든 뒤 안내 문구를 띄운다.
        self.hasConfig = config != nil
        _store = StateObject(wrappedValue: LeeoStore(config: config ?? LeeoPaywallConfig(productIDs: [])))
    }

    public var body: some View {
        // 그림으로 파는 틀(`LeeoShowcasePaywall`): 머리말 없이 등급 · 그림 · 요금이 첫 화면에, 구매 단추는 늘 떠 있다.
        LeeoShowcasePaywall(showcases: pages) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 36)   // 닫기 단추 자리
                tierPicker
            }
        } plans: {
            productSection
        } button: {
            purchaseButton
        } details: {
            VStack(spacing: 16) {
                if let error = store.lastError, !visibleProducts.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                footer
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .task {
            // 노출 자체가 퍼널의 시작점 — 앱이 따로 기록할 필요 없다.
            LeeoAnalyticsCenter.track(.paywallShown(reason: analyticsReason))
            guard hasConfig, store.config.autoLoad else { return }
            await store.loadProducts()
            selectDefault()
        }
        .onChange(of: isSatisfied) { _, satisfied in
            if satisfied { onPurchased?(); dismiss() }
        }
    }

    // MARK: - 섹션

    /// 넘겨 볼 장. 앱이 그린 그림이 있으면 그것, 없으면 방금 부딪힌 기능 · 등급 혜택 · 혜택 글을 큰 기호 한 장씩으로.
    private var pages: [LeeoShowcase] {
        if !showcases.isEmpty {
            // 등급을 쓰는 앱: 장의 id 가 기능 키(`LeeoTier.features`)면 고른 등급의 장만 보인다
            guard let tier = selectedTier, !tier.features.isEmpty else { return showcases }
            let mine = showcases.filter { tier.features.contains($0.id) }
            return mine.isEmpty ? showcases : mine
        }
        var pages: [LeeoShowcase] = []
        if leadKey != nil || analyticsReason != nil {
            pages.append(LeeoShowcase(id: "lead", title: title, detail: subtitle, systemImage: leadIcon))
        }
        let lines = selectedTier.map(highlights(of:)) ?? features
        pages += lines.enumerated().map { index, line in
            LeeoShowcase(id: "\(selectedTier?.id ?? "")#\(index)", title: line, detail: "",
                         systemImage: index == 0 && pages.isEmpty ? leadIcon : "checkmark.seal.fill")
        }
        if pages.isEmpty { pages.append(LeeoShowcase(id: "lead", title: title, detail: subtitle, systemImage: leadIcon)) }
        return pages
    }

    @ViewBuilder
    private var productSection: some View {
        if !hasConfig {
            notice(L("판매 상품이 구성되지 않았어요.", comment: "Paywall: no config"))
        } else if store.isLoadingProducts && visibleProducts.isEmpty {
            ProgressView(L("상품을 불러오는 중…", comment: "Paywall: loading products"))
                .tint(theme.accent)
                .padding(.vertical, 24)
        } else if visibleProducts.isEmpty {
            // 등급을 쓰면 고른 등급의 상품이 하나도 안 왔을 때도 여기다 (다른 등급 상품만 온 경우)
            VStack(spacing: 12) {
                notice(store.lastError ?? L("상품을 불러오지 못했어요.", comment: "Paywall: load failed"))
                Button(L("다시 시도", comment: "Paywall: retry")) {
                    Task { await store.loadProducts(); selectDefault() }
                }
                .tint(theme.accent)
            }
        } else {
            // 연간 줄의 할인 배지가 줄 위로 살짝 올라오므로 간격과 위 여백을 둔다
            VStack(spacing: 20) {
                ForEach(visibleProducts, id: \.id) { product in
                    productRow(product)
                }
            }
            .padding(.top, 10)
        }
    }

    private func productRow(_ product: Product) -> some View {
        let saving = savingPercent(product)
        return LeeoOptionRow(title: rowTitle(product), detail: rowDetail(product, saving: saving),
                             selected: selectedProductID == product.id) {
            selectedProductID = product.id
        } trailing: {
            price(product)
        }
        .overlay(alignment: .topTrailing) {
            if let saving { savingBadge(saving) }
        }
    }

    // MARK: - 상품 줄의 글

    /// 등급을 쓰면 등급은 위에서 이미 골랐으니 줄 이름은 기간만 ("연간"). 앱 언어로 나온다.
    /// 상품 이름(App Store 현지화)에 기대지 않으니, 그 언어 현지화가 없는 상품도 섞여 보이지 않는다.
    private func rowTitle(_ product: Product) -> String {
        guard !tiers.isEmpty else { return product.displayName }
        if let period = product.subscription?.subscriptionPeriod, period.value == 1 {
            switch period.unit {
            case .year:  return L("연간", comment: "Paywall row: yearly plan")
            case .month: return L("월간", comment: "Paywall row: monthly plan")
            default: break
            }
        }
        if product.type == .nonConsumable { return L("평생", comment: "Paywall row: lifetime") }
        return product.displayName
    }

    /// 연간이면 한 달에 얼마꼴인지. 등급이 없는 앱은 상품 설명을 그대로 (할인 배지가 서면 설명은 겹치니 뺀다).
    private func rowDetail(_ product: Product, saving: Int?) -> String? {
        if let period = product.subscription?.subscriptionPeriod, period.unit == .year, period.value == 1,
           (saving != nil || !tiers.isEmpty) {
            let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
            return String(format: L("월 %@꼴", comment: "Paywall row: yearly price per month"), perMonth)
        }
        // 평생이면 연간 몇 년치인지 ("연 구독 3년치, 한 번만 내면 끝")
        if product.type == .nonConsumable, let yearly = yearlyProduct, yearly.price > 0 {
            let years = Int(NSDecimalNumber(decimal: product.price / yearly.price).doubleValue.rounded())
            if years >= 2 { return String(format: L("연 구독 %d년치, 한 번만 내면 끝", comment: "Pricing ladder: lifetime equals N years of the subscription. %d = years"), years) }
        }
        if !tiers.isEmpty || saving != nil || product.description.isEmpty { return nil }
        return product.description
    }

    private var monthlyProduct: Product? {
        visibleProducts.first { $0.subscription?.subscriptionPeriod.unit == .month && $0.subscription?.subscriptionPeriod.value == 1 }
    }

    private var yearlyProduct: Product? {
        visibleProducts.first { $0.subscription?.subscriptionPeriod.unit == .year && $0.subscription?.subscriptionPeriod.value == 1 }
    }

    /// 연간이 월간 열두 달보다 몇 % 싼지. 같은 줄에 월간이 있고 5% 이상일 때만.
    private func savingPercent(_ product: Product) -> Int? {
        guard let period = product.subscription?.subscriptionPeriod, period.unit == .year, period.value == 1,
              let monthly = monthlyProduct, monthly.price > 0
        else { return nil }
        let ratio = NSDecimalNumber(decimal: product.price / (monthly.price * 12)).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded(.down))
        return percent >= 5 ? percent : nil
    }

    private func savingBadge(_ percent: Int) -> some View {
        Text(String(format: L("%d%% 할인", comment: "Paywall badge: yearly saving vs monthly"), percent))
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(theme.accent, in: Capsule())
            .shadow(color: theme.accent.opacity(0.35), radius: 4, y: 2)
            .offset(x: -14, y: -14)
    }

    private func price(_ product: Product) -> some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(priceLabel(product))
                .font(.headline)
                .foregroundStyle(theme.text)
            // 연간이면 월간으로 열두 달 낼 값을 그어 보인다 — 얼마나 아끼는지 한눈에
            if savingPercent(product) != nil, let monthly = monthlyProduct {
                Text((monthly.price * 12).formatted(product.priceFormatStyle))
                    .font(.caption)
                    .strikethrough()
                    .foregroundStyle(theme.textMuted)
                    .accessibilityHidden(true)
            }
        }
    }

    private var purchaseTitle: String {
        isSubscription(selectedProduct)
            ? L("구독 시작하기", comment: "Paywall: purchase CTA (subscription)")
            : L("구매하기", comment: "Paywall: purchase CTA (one-time)")
    }

    private var purchaseButton: some View {
        LeeoPrimaryButton(title: purchaseTitle, isWorking: store.purchasingProductID != nil) {
            guard let product = selectedProduct else { return }
            Task { await store.purchase(product) }
        }
        .disabled(selectedProduct == nil)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.restore() }
            } label: {
                if store.isRestoring {
                    ProgressView().tint(theme.accent)
                } else {
                    Text(L("구매 복원", comment: "Paywall: restore purchases"))
                        .font(.footnote)
                }
            }
            .tint(theme.accent)
            .disabled(store.isRestoring)
            .accessibilityLabel(L("구매 복원", comment: "Paywall: restore purchases"))

            // 구독 안내는 구독 상품을 팔 때만. 평생 상품만 파는 앱에 "해지할 수 있어요"를
            // 띄우면 구독인 줄 알고 망설이게 되고, 사실과도 다르다.
            Text(sellsSubscription
                 ? L("결제는 App Store 계정으로 청구됩니다. 구독은 언제든지 App Store 설정에서 관리·해지할 수 있어요.",
                     comment: "Paywall: billing disclaimer (subscription)")
                 : L("결제는 App Store 계정으로 청구됩니다.",
                     comment: "Paywall: billing disclaimer (one-time)"))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textMuted)

            HStack(spacing: 16) {
                if let terms = store.config.termsURL {
                    Link(L("이용약관", comment: "Paywall: terms of use"), destination: terms)
                }
                if let privacy = store.config.privacyURL {
                    Link(L("개인정보처리방침", comment: "Paywall: privacy policy"), destination: privacy)
                }
            }
            .font(.caption2)
            .tint(theme.textMuted)
        }
        .padding(.top, 4)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textMuted)
                .padding(16)
        }
        .accessibilityLabel(L("닫기", comment: "Paywall: close"))
    }

    // MARK: - 등급

    /// 등급 (낮은 것부터). 비어 있으면 등급 없는 페이월이다.
    private var tiers: [LeeoTier] { store.config.gate.tiers }

    /// 살 수 있는 등급 — 이미 가진 등급과 그 아래는 뺀다
    private var offeredTiers: [LeeoTier] {
        Array(tiers.dropFirst((store.currentTierIndex ?? -1) + 1))
    }

    private var selectedTier: LeeoTier? {
        offeredTiers.first { $0.id == selectedTierID } ?? offeredTiers.last
    }

    @ViewBuilder
    private var tierPicker: some View {
        if offeredTiers.count > 1 {
            Picker(L("등급", comment: "Paywall: tier picker"), selection: Binding(
                get: { selectedTier?.id ?? "" },
                set: { selectTier($0) }
            )) {
                ForEach(offeredTiers) { Text($0.name).tag($0.id) }
            }
            #if !os(watchOS)
            .pickerStyle(.segmented)
            #endif
        }
    }

    /// 그 등급의 혜택 — 아래 등급이 있으면 "그 등급의 모든 기능" 을 맨 위에 둔다
    private func highlights(of tier: LeeoTier) -> [String] {
        guard let index = tiers.firstIndex(of: tier), index > 0 else { return tier.highlights }
        let lower = String(format: L("%@의 모든 기능", comment: "Paywall: includes every feature of the lower tier (tier name)"),
                           tiers[index - 1].name)
        return [lower] + tier.highlights
    }

    private func selectTier(_ id: String) {
        guard id != selectedTierID else { return }
        selectedTierID = id
        selectedProductID = nil
        selectDefault()
    }

    /// 지금 보여 줄 상품 — 등급을 쓰면 고른 등급의 상품만
    private var visibleProducts: [Product] {
        guard let tier = selectedTier else { return store.products }
        return tier.productIDs.compactMap { id in store.products.first { $0.id == id } }
    }

    /// 페이월을 닫아도 되는지 — 고른(또는 방금 막힌 기능이 요구하는) 등급에 닿았는지
    private var isSatisfied: Bool {
        guard !tiers.isEmpty else { return store.hasPro }
        guard let owned = store.currentTierIndex else { return false }
        if let leadKey, let required = store.config.gate.requiredTierIndex(for: leadKey) { return owned >= required }
        return owned == tiers.count - 1 || offeredTiers.isEmpty
    }

    // MARK: - 헬퍼

    private func notice(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(theme.textMuted)
            .padding(.vertical, 16)
    }

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedProductID }
    }

    /// 불러온 상품 중 자동 갱신 구독이 하나라도 있는지.
    private var sellsSubscription: Bool {
        store.products.contains { isSubscription($0) }
    }

    private func isSubscription(_ product: Product?) -> Bool {
        #if canImport(StoreKit)
        return product?.subscription != nil
        #else
        return false
        #endif
    }

    private func selectDefault() {
        if selectedTierID == nil, !tiers.isEmpty {
            // 방금 막힌 기능을 여는 등급, 없으면 가장 높은 등급
            let lead = leadKey.flatMap { store.config.gate.requiredTierIndex(for: $0) }.map { tiers[$0].id }
            selectedTierID = offeredTiers.first { $0.id == lead }?.id ?? offeredTiers.last?.id
        }
        if selectedProductID == nil { selectedProductID = visibleProducts.first?.id }
    }

    /// 구독 상품이면 "가격/기간", 아니면 그냥 가격.
    private func priceLabel(_ product: Product) -> String {
        #if canImport(StoreKit)
        if let period = product.subscription?.subscriptionPeriod {
            return "\(product.displayPrice) / \(periodText(period))"
        }
        #endif
        return product.displayPrice
    }

    #if canImport(StoreKit)
    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day:   return n == 1 ? L("일", comment: "period day") : String(format: L("%d일", comment: "period days"), n)
        case .week:  return n == 1 ? L("주", comment: "period week") : String(format: L("%d주", comment: "period weeks"), n)
        case .month: return n == 1 ? L("월", comment: "period month") : String(format: L("%d개월", comment: "period months"), n)
        case .year:  return n == 1 ? L("년", comment: "period year") : String(format: L("%d년", comment: "period years"), n)
        @unknown default: return ""
        }
    }
    #endif
}

// MARK: - View API

public extension View {
    /// 페이월을 시트로 띄운다. `config` 는 기본으로 `Spec.paywall` 을 사용한다.
    /// - Parameters:
    ///   - isPresented: 시트 표시 바인딩. 구매/복원 성공 시 자동으로 닫힌다.
    ///   - features: 혜택 불릿 (선택).
    ///   - onPurchased: 권한 확보 시 콜백 (선택).
    func leeoPaywallSheet<Spec: LeeoAppSpec>(
        _ spec: Spec.Type,
        isPresented: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        features: [String] = [],
        leadFeature: LeeoProFeature? = nil,
        showcases: [LeeoShowcase] = [],
        onPurchased: (() -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            LeeoPaywallView<Spec>(
                title: title,
                subtitle: subtitle,
                features: features,
                leadFeature: leadFeature,
                showcases: showcases,
                onPurchased: onPurchased
            )
        }
    }
}
