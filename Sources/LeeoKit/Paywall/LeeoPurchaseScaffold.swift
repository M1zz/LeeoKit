//
//  LeeoPurchaseScaffold.swift
//  LeeoKit
//
//  **돈을 받는 화면의 한 틀.** 페이월(`LeeoPaywallView`) · 응원(`LeeoTipJarView`) · 선물(`LeeoGiftView`)이
//  모두 이 모양이다. 들어오면 무엇을 사는지 보이고, 바로 아래에서 고르고, 늘 떠 있는 단추 하나로 산다.
//
//    hero        그림 · 지금 상태 · 한 줄 말     ← 가장자리까지 쓴다(그림 띠). 글이면 안쪽 여백은 hero 가 둔다
//    options     고를 줄들(LeeoOptionRow)        ← 첫 화면에 들어와야 한다
//    ─── 스크롤해야 보임 ───
//    details     설명 · 약관 · 복원 · 보낸 것 · 문의
//    ════ 늘 떠 있음 ════
//    button      LeeoPrimaryButton 하나          ← 본문 위에 겹쳐 늘 보인다
//
//  ⚠️ 본문에 단추를 또 두지 않는다. 사는 길은 떠 있는 단추 하나다. 줄을 누르면 고르기만 한다.
//  ⚠️ 머리말(앱 이름 · "프리미엄" · 미사여구)은 두지 않는다. 들어온 줄 이름이 이미 말했다.
//
//  사용 예:
//      LeeoPurchaseScaffold {
//          MyHeroArt().padding(.horizontal, LeeoPurchaseScaffoldMetrics.margin)
//      } options: {
//          ForEach(items) { item in
//              LeeoOptionRow(title: item.name, price: item.price, selected: item.id == picked) { picked = item.id }
//          }
//      } button: {
//          LeeoPrimaryButton(title: "구매하기", isWorking: buying) { buy() }
//      } details: {
//          termsAndLinks
//      }
//

import SwiftUI

/// 틀의 치수. 앱이 hero 에 글을 둘 때 같은 여백을 쓰게 연다.
public enum LeeoPurchaseScaffoldMetrics {
    /// 좌우 여백
    public static let margin: CGFloat = 20
    /// 본문 최대 폭(아이패드 · 맥에서 줄이 너무 길어지지 않게)
    public static let maxWidth: CGFloat = 560
}

/// 돈을 받는 화면의 틀: hero · options 가 첫 화면에, 단추 하나는 늘 떠 있고, 설명은 스크롤한 아래에.
public struct LeeoPurchaseScaffold<Hero: View, Options: View, Button: View, Details: View>: View {
    let hero: Hero
    let options: Options
    let button: Button
    let details: Details
    @Environment(\.leeoStyle) private var theme
    /// 떠 있는 단추 높이. 본문 끝이 단추에 가리지 않게 그만큼 비운다
    @State private var buttonHeight: CGFloat = 80

    private var margin: CGFloat { LeeoPurchaseScaffoldMetrics.margin }
    private var maxWidth: CGFloat { LeeoPurchaseScaffoldMetrics.maxWidth }

    public init(@ViewBuilder hero: () -> Hero,
                @ViewBuilder options: () -> Options,
                @ViewBuilder button: () -> Button,
                @ViewBuilder details: () -> Details) {
        self.hero = hero()
        self.options = options()
        self.button = button()
        self.details = details()
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    options.padding(.horizontal, margin)
                    details
                        .padding(.horizontal, margin)
                        .padding(.top, 28)
                }
                .padding(.top, 8)
                .padding(.bottom, buttonHeight + 16)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            button
                .padding(.horizontal, margin)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    // 본문이 단추 밑으로 흘러들어도 단추가 읽히게. 위로 갈수록 투명해진다
                    LinearGradient(colors: [theme.bg.opacity(0), theme.bg], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonHeight = $0 }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

// MARK: - 고를 줄

/// 고를 줄 하나: 동그라미 · (그림) · 이름 · 한 줄 설명 · 값. 누르면 고르기만 한다(사는 것은 떠 있는 단추).
/// 아주 큰 글자에서는 값을 이름 아래로 내린다. 옆에 두면 이름 칸이 몇 글자 폭으로 눌린다.
public struct LeeoOptionRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let symbol: String?
    let selected: Bool
    let action: () -> Void
    let trailing: Trailing
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 값 자리를 앱이 그린다(구독 기간 · 그은 값처럼 두 줄일 때).
    public init(title: String, detail: String? = nil, symbol: String? = nil, selected: Bool,
                action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.selected = selected
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        SwiftUI.Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? theme.accent : theme.textMuted)
                    .accessibilityHidden(true)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.text)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(theme.textMuted)
                    }
                    if typeSize.isAccessibilitySize { trailing.padding(.top, 4) }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !typeSize.isAccessibilitySize { trailing.layoutPriority(1) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous)
                .strokeBorder(selected ? theme.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityInputLabels([Text(title)])
    }
}

public extension LeeoOptionRow where Trailing == LeeoPriceText {
    /// 값이 한 줄인 보통의 줄. 값이 아직 없으면(상품을 불러오는 중) 도는 표시가 선다.
    init(title: String, detail: String? = nil, symbol: String? = nil, price: String?,
         selected: Bool, action: @escaping () -> Void) {
        self.init(title: title, detail: detail, symbol: symbol, selected: selected, action: action) {
            LeeoPriceText(price)
        }
    }
}

/// 줄 끝의 값. ⚠️ 값은 **한 줄**이다. 두 줄로 꺾이면 "₩1," / "100" 처럼 읽혀 얼마인지 헷갈린다.
public struct LeeoPriceText: View {
    let price: String?
    @Environment(\.leeoStyle) private var theme

    public init(_ price: String?) { self.price = price }

    public var body: some View {
        if let price {
            Text(price)
                .font(.headline.monospacedDigit())
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            ProgressView()
        }
    }
}

// MARK: - 사는 단추

/// 떠 있는 단추. 화면에 하나뿐이다. 결제 중에는 글자 대신 도는 표시가 서고 눌리지 않는다.
public struct LeeoPrimaryButton: View {
    let title: String
    let isWorking: Bool
    let action: () -> Void
    @Environment(\.leeoStyle) private var theme
    @Environment(\.isEnabled) private var isEnabled

    public init(title: String, isWorking: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isWorking = isWorking
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(theme.accent.opacity(isEnabled ? 1 : 0.45),
                        in: RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        // 결제 중에는 글자 대신 도는 표시가 서므로 이름을 따로 붙인다
        .accessibilityLabel(title)
    }
}
