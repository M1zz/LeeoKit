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
    private let leadIcon: String
    private let onPurchased: (() -> Void)?

    @StateObject private var store: LeeoStore
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProductID: String?

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
        config: LeeoPaywallConfig? = Spec.paywall,
        onPurchased: (() -> Void)? = nil
    ) {
        // 리드 기능이 있으면 "방금 부딪힌 그 기능"을 팔도록 헤더/문구를 맞춘다.
        self.title = title ?? leadFeature?.leeoTitle
            ?? String(format: L("%@ 프리미엄", comment: "Paywall default title"), Spec.appName)
        self.subtitle = subtitle ?? leadFeature?.leeoDetail
            ?? L("모든 기능을 잠금 해제하세요.", comment: "Paywall default subtitle")
        self.features = features
        self.leadIcon = leadFeature?.leeoIcon ?? "crown.fill"
        self.onPurchased = onPurchased
        // config 가 없으면 빈 구성으로라도 안전하게 만든 뒤 안내 문구를 띄운다.
        self.hasConfig = config != nil
        _store = StateObject(wrappedValue: LeeoStore(config: config ?? LeeoPaywallConfig(productIDs: [])))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                if !features.isEmpty { featureList }
                productSection
                footer
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { closeButton }
        .task {
            guard hasConfig, store.config.autoLoad else { return }
            await store.loadProducts()
            selectDefault()
        }
        .onChange(of: store.hasPro) { _, pro in
            if pro { onPurchased?(); dismiss() }
        }
    }

    // MARK: - 섹션

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: leadIcon)
                .font(.system(size: 44))
                .foregroundStyle(theme.accent)
                .padding(.top, 28)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text)
            Text(subtitle)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textMuted)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features, id: \.self) { feature in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                    Text(feature)
                        .foregroundStyle(theme.text)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusLg))
    }

    @ViewBuilder
    private var productSection: some View {
        if !hasConfig {
            notice(L("판매 상품이 구성되지 않았어요.", comment: "Paywall: no config"))
        } else if store.isLoadingProducts && store.products.isEmpty {
            ProgressView(L("상품을 불러오는 중…", comment: "Paywall: loading products"))
                .tint(theme.accent)
                .padding(.vertical, 24)
        } else if store.products.isEmpty {
            VStack(spacing: 12) {
                notice(store.lastError ?? L("상품을 불러오지 못했어요.", comment: "Paywall: load failed"))
                Button(L("다시 시도", comment: "Paywall: retry")) {
                    Task { await store.loadProducts(); selectDefault() }
                }
                .tint(theme.accent)
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    productRow(product)
                }
            }
            purchaseButton
            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func productRow(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? theme.accent : theme.textFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundStyle(theme.text)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption)
                            .foregroundStyle(theme.textMuted)
                    }
                }
                Spacer(minLength: 8)
                Text(priceLabel(product))
                    .font(.headline)
                    .foregroundStyle(theme.text)
            }
            .padding(16)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radiusLg)
                    .stroke(isSelected ? theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            Task { await store.purchase(product) }
        } label: {
            HStack {
                if store.purchasingProductID != nil {
                    ProgressView().tint(.white)
                } else {
                    Text(L("구독 시작하기", comment: "Paywall: purchase CTA"))
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusLg))
            .foregroundStyle(.white)
        }
        .disabled(selectedProduct == nil || store.purchasingProductID != nil)
        .padding(.top, 4)
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

            Text(L("결제는 App Store 계정으로 청구됩니다. 구독은 언제든지 App Store 설정에서 관리·해지할 수 있어요.",
                    comment: "Paywall: billing disclaimer"))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textFaint)

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
                .foregroundStyle(theme.textFaint)
                .padding(16)
        }
        .accessibilityLabel(L("닫기", comment: "Paywall: close"))
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

    private func selectDefault() {
        if selectedProductID == nil { selectedProductID = store.products.first?.id }
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
        onPurchased: (() -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            LeeoPaywallView<Spec>(
                title: title,
                subtitle: subtitle,
                features: features,
                leadFeature: leadFeature,
                onPurchased: onPurchased
            )
        }
    }
}
