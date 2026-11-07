//
//  LeeoShowcase.swift
//  LeeoKit
//
//  **그림으로 파는 페이월 틀.** 글을 늘어놓지 않고, 기능이 적용된 화면 그림을 옆으로 넘겨 보인다.
//
//    등급 고르기(있으면)           ← top
//    ┌──────────────────────┐
//    │   기능이 적용된 그림       │   ← 옆으로 넘긴다(점으로 몇 번째인지)
//    └──────────────────────┘
//    기능 이름 · 한 줄 설명
//    월간 · 연간 · 평생          ← plans. 첫 화면에 다 들어온다
//    ─── 스크롤해야 보임 ───
//    갱신 조건 · 복원 · 약관 · 비교  ← details
//    ════ 늘 떠 있음 ════
//    [ 구매 단추 ]               ← button. 본문 위에 겹쳐 늘 보인다
//
//  ⚠️ 머리말(앱 이름 · "프리미엄" · 미사여구)은 두지 않는다. 사용자는 지금 결제 화면에 와 있는 줄 안다.
//  ⚠️ 그림은 앱이 그린다(`LeeoShowcase(art:)`). 스크린샷 대신 SwiftUI 로 그리면 언어 · 다크 모드를 따라가고 용량이 들지 않는다.
//     그림이 없으면 큰 기호로 대신한다(`LeeoShowcase(systemImage:)`).
//
//  사용 예:
//      LeeoShowcasePaywall(showcases: [
//          LeeoShowcase(id: "planner", title: "연간 최적 플래너", detail: "남은 연차로 가장 긴 연휴를") { PlannerArt() },
//      ]) {
//          tierPicker
//      } plans: {
//          planRows
//      } button: {
//          buyButton
//      } details: {
//          termsAndLinks
//      }
//

import SwiftUI

/// 페이월에서 넘겨 보는 기능 한 장 — 그림 · 이름 · 한 줄 설명.
public struct LeeoShowcase: Identifiable {
    /// 장의 이름. 등급을 쓰는 앱이 기능 키(`LeeoTier.features`)로 주면 `LeeoPaywallView` 가 고른 등급의 장만 보인다.
    public let id: String
    public let title: String
    public let detail: String
    let art: AnyView

    /// 앱이 그린 그림으로. 그림은 카드 안(가로 꽉, 세로는 페이월이 정한 높이)에 놓인다.
    public init<Art: View>(id: String, title: String, detail: String, @ViewBuilder art: () -> Art) {
        self.id = id
        self.title = title
        self.detail = detail
        self.art = AnyView(art())
    }

    /// 그림 없이 — 큰 기호로 대신한다.
    public init(id: String, title: String, detail: String, systemImage: String, tint: Color? = nil) {
        self.init(id: id, title: title, detail: detail) {
            LeeoShowcaseSymbolArt(systemImage: systemImage, tint: tint)
        }
    }
}

/// 그림이 없는 기능의 그림 자리 — 큰 기호 하나.
struct LeeoShowcaseSymbolArt: View {
    let systemImage: String
    let tint: Color?
    @Environment(\.leeoStyle) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 72, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint ?? theme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// 기능 그림을 옆으로 넘기는 띠. 아래 점이 몇 번째인지 알린다.
public struct LeeoShowcaseCarousel: View {
    let showcases: [LeeoShowcase]
    /// 그림 카드 높이
    let artHeight: CGFloat
    @State private var current: String?
    @Environment(\.leeoStyle) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(showcases: [LeeoShowcase], artHeight: CGFloat = 260) {
        self.showcases = showcases
        self.artHeight = artHeight
    }

    public var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(showcases) { item in
                        page(item)
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            if showcases.count > 1 { dots }
        }
        // 등급을 바꾸면 그림 묶음이 바뀐다 — 첫 장부터
        .onChange(of: showcases.map(\.id)) { _, ids in current = ids.first }
        .onAppear { if current == nil { current = showcases.first?.id } }
    }

    private func page(_ item: LeeoShowcase) -> some View {
        VStack(spacing: 14) {
            item.art
                .frame(maxWidth: .infinity)
                .frame(height: artHeight)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.text)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 20)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(showcases) { item in
                let on = item.id == (current ?? showcases.first?.id)
                Capsule()
                    .fill(on ? theme.accent : theme.textMuted.opacity(0.35))
                    .frame(width: on ? 18 : 7, height: 7)
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .snappy) { current = item.id }
                    }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel(pageLabel)
        .accessibilityAdjustableAction { direction in
            guard let index = showcases.firstIndex(where: { $0.id == current }) else { return }
            let next = direction == .increment ? min(index + 1, showcases.count - 1) : max(index - 1, 0)
            current = showcases[next].id
        }
    }

    private var pageLabel: String {
        let index = (showcases.firstIndex { $0.id == current } ?? 0) + 1
        return "\(index) / \(showcases.count)"   // 숫자뿐이라 번역하지 않는다
    }
}

/// 그림으로 파는 페이월의 틀. 앞 화면에 고르기 · 그림 · 요금이 다 들어오고, 구매 단추는 늘 떠 있다.
public struct LeeoShowcasePaywall<Top: View, Plans: View, Button: View, Details: View>: View {
    let showcases: [LeeoShowcase]
    let top: Top
    let plans: Plans
    let button: Button
    let details: Details
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 떠 있는 단추 높이 — 본문 끝이 단추에 가리지 않게 그만큼 비운다
    @State private var buttonHeight: CGFloat = 80

    public init(showcases: [LeeoShowcase],
                @ViewBuilder top: () -> Top,
                @ViewBuilder plans: () -> Plans,
                @ViewBuilder button: () -> Button,
                @ViewBuilder details: () -> Details) {
        self.showcases = showcases
        self.top = top()
        self.plans = plans()
        self.button = button()
        self.details = details()
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    top.padding(.horizontal, 20)
                    if !showcases.isEmpty {
                        // 아주 큰 글씨에서는 그림을 줄여 요금 줄이 첫 화면에 남게 한다
                        LeeoShowcaseCarousel(showcases: showcases, artHeight: typeSize.isAccessibilitySize ? 150 : 240)
                    }
                    plans.padding(.horizontal, 20)
                    details
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                }
                .padding(.top, 8)
                .padding(.bottom, buttonHeight + 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            button
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    // 본문이 단추 밑으로 흘러들어도 단추가 읽히게 — 위로 갈수록 투명해진다
                    LinearGradient(colors: [theme.bg.opacity(0), theme.bg], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { buttonHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in buttonHeight = height }
                    }
                }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}
