//
//  LeeoTipAsk.swift
//  LeeoKit
//
//  **팁을 부탁할 때**를 고른다. 대가를 파는 말이 아니라 "계속 만들 수 있게 힘을 보태 달라" 는 부탁이므로,
//  앱이 그 사람에게 실제로 도움이 됐다는 것이 숫자로 보이는 순간에만, 드물게 묻는다.
//
//  앱이 하는 일: 지금 넘어선 순간(`LeeoTipMoment`)을 **인상적인 것부터** 넘긴다.
//      if let moment = tipJar.momentToAsk(from: reached) {
//          LeeoTipAskCard(tipJar: tipJar, moment: moment, onSupport: { showTipJar = true })
//      }
//  창으로 띄우려면 앱의 첫 화면에 한 줄(창 안에서 바로 팁을 낸다):
//      .leeoTipAsk(tipJar: tipJar, when: hasEverything) { MyTipMoments.reachedNow }
//
//  묻는 횟수의 규칙(`LeeoTipAskPolicy`):
//   - 한 번 물으면 60일은 다시 묻지 않는다
//   - 팁을 낸 사람에게는 180일 동안 묻지 않는다
//   - '다음에' 를 세 번 누르면 다시는 묻지 않는다
//   - '다시 보지 않기' 를 누르면 그때부터 다시는 묻지 않는다
//   - 같은 순간은 한 번만. 보여 줄 때 함께 넘어선 더 작은 순간도 다 쓴 것으로 친다
//

import SwiftUI

// MARK: - 순간

/// 팁을 부탁할 만한 순간 하나. `id` 는 앱 안에서 고정된 이름(예: "saved.5h"), `message` 는 그 사람의 숫자를 담은 한 줄.
public struct LeeoTipMoment: Equatable, Sendable, Identifiable {
    public let id: String
    public let message: String

    public init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}

// MARK: - 규칙 (순수 함수)

public enum LeeoTipAskPolicy {
    public static let quietDaysAfterAsk = 60
    public static let quietDaysAfterTip = 180
    public static let maxLaters = 3

    /// 지금 물어도 되면 물을 순간을, 아니면 nil.
    /// - Parameter reached: 넘어선 순간, **인상적인 것부터**.
    /// - Parameter optedOut: '다시 보지 않기' 를 눌렀다.
    public static func pick(reached: [LeeoTipMoment], seen: Set<String>,
                            lastAskedAt: Date?, lastTipAt: Date?, laters: Int,
                            optedOut: Bool = false,
                            now: Date) -> LeeoTipMoment? {
        guard !optedOut, laters < maxLaters else { return nil }
        if let lastTipAt, now.timeIntervalSince(lastTipAt) < days(quietDaysAfterTip) { return nil }
        if let lastAskedAt, now.timeIntervalSince(lastAskedAt) < days(quietDaysAfterAsk) { return nil }
        return reached.first { !seen.contains($0.id) }
    }

    private static func days(_ n: Int) -> TimeInterval { TimeInterval(n) * 24 * 60 * 60 }
}

// MARK: - 기록

@MainActor
public extension LeeoTipJar {

    /// 지금 부탁할 순간. 판매 중인 팁이 없으면 묻지 않는다.
    func momentToAsk(from reached: [LeeoTipMoment], now: Date = Date()) -> LeeoTipMoment? {
        guard isAvailable else { return nil }
        return LeeoTipAskPolicy.pick(reached: reached, seen: askSeen, lastAskedAt: lastAskedAt,
                                     lastTipAt: lastTipAt, laters: askLaters, optedOut: optedOutOfAsks, now: now)
    }

    /// 카드를 보여 줬다. 함께 넘어선 순간은 모두 쓴 것으로 친다(작은 순간이 나중에 다시 묻지 않게).
    func markAsked(covering reached: [LeeoTipMoment], now: Date = Date()) {
        defaults.set(Array(askSeen.union(reached.map(\.id))), forKey: askSeenKey)
        defaults.set(now, forKey: askLastKey)
    }

    /// '다음에'. 세 번이면 다시는 묻지 않는다.
    func declineAsk() {
        defaults.set(askLaters + 1, forKey: askLatersKey)
    }

    /// '다시 보지 않기'. 그때부터 다시는 묻지 않는다(팁 화면은 설정에서 그대로 열린다).
    func optOutOfAsks() {
        defaults.set(true, forKey: askNeverKey)
    }

    /// '다시 보지 않기' 를 눌렀는가.
    var optedOutOfAsks: Bool { defaults.bool(forKey: askNeverKey) }

    internal var askSeen: Set<String> { Set(defaults.stringArray(forKey: askSeenKey) ?? []) }
    internal var lastAskedAt: Date? { defaults.object(forKey: askLastKey) as? Date }
    internal var askLaters: Int { defaults.integer(forKey: askLatersKey) }
}

// MARK: - 카드

/// 목록 위에 얹는 부탁 카드. 숫자 한 줄(그 사람이 얻은 것) → 부탁 → '응원하기' · '다음에'.
public struct LeeoTipAskCard: View {
    @ObservedObject private var tipJar: LeeoTipJar
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    private let moment: LeeoTipMoment
    private let onSupport: () -> Void
    private let onLater: () -> Void

    /// - Parameters:
    ///   - onSupport: 팁 화면을 연다(앱이 띄운다).
    ///   - onLater: 카드를 내린다. '다음에' 기록은 카드가 남긴다.
    public init(tipJar: LeeoTipJar, moment: LeeoTipMoment,
                onSupport: @escaping () -> Void, onLater: @escaping () -> Void) {
        self.tipJar = tipJar
        self.moment = moment
        self.onSupport = onSupport
        self.onLater = onLater
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.accent.opacity(0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(moment.message)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.text)
                    Text(L("혼자 만들고 고쳐 가는 앱이에요. 앞으로도 계속 다듬을 수 있게 조금만 힘을 보태 주시겠어요?",
                           comment: "Tip ask card: asks for support so the developer can keep maintaining the app"))
                        .font(.body)
                        .foregroundStyle(theme.textMuted)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // 아주 큰 글자에서는 두 단추를 위아래로 세운다.
            let buttons = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            buttons {
                Button {
                    tipJar.declineAsk()
                    onLater()
                } label: {
                    Text(L("다음에", comment: "Tip ask card: not now"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                Button(action: onSupport) {
                    Text(L("응원하기", comment: "Tip ask card: open the tip jar"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
            LeeoTipAskNeverButton(tipJar: tipJar, onDone: onLater)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous).fill(theme.surface))
    }
}

// MARK: - 다시 보지 않기

/// 카드와 창 맨 아래의 작은 단추. 누르면 다시는 묻지 않는다.
struct LeeoTipAskNeverButton: View {
    @ObservedObject var tipJar: LeeoTipJar
    let onDone: () -> Void
    @Environment(\.leeoStyle) private var theme

    var body: some View {
        Button {
            tipJar.optOutOfAsks()
            onDone()
        } label: {
            Text(L("앞으로 이 메시지 보지 않기", comment: "Tip ask: never show this request again"))
                .font(.footnote)
                .foregroundStyle(theme.textMuted)
                .underline()
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 창

#if canImport(StoreKit)
import StoreKit

/// 부탁을 **창으로** 띄운다. 그 사람의 숫자 한 줄 → 혼자 만드는 사람의 부탁 → 팁 세 개를 바로 고르기
/// → '다음에' · '앞으로 이 메시지 보지 않기'. 팁을 내면 같은 자리에서 고맙다고 말한다.
///
/// ⚠️ 언제 띄울지는 `momentToAsk` 가 정한다. 띄운 뒤 앱이 `markAsked(covering:)` 를 부른다(카드와 같다).
/// ⚠️ 쓸어내려 닫으면 '다음에' 로 친다. 아무 말 없이 닫은 것도 지금은 아니라는 뜻이다.
public struct LeeoTipAskSheet: View {
    @ObservedObject private var tipJar: LeeoTipJar
    @Environment(\.leeoStyle) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchaseAction
    private let moment: LeeoTipMoment
    @State private var answered = false

    public init(tipJar: LeeoTipJar, moment: LeeoTipMoment) {
        self.tipJar = tipJar
        self.moment = moment
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: tipJar.justTipped ? "heart.circle.fill" : "heart.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 64, height: 64)
                .background(Circle().fill(theme.accent.opacity(0.14)))
                .accessibilityHidden(true)
            if tipJar.justTipped { thanks } else { ask }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .task { await tipJar.loadProducts() }
        .onDisappear {
            if !answered && !tipJar.justTipped { tipJar.declineAsk() }
            tipJar.justTipped = false
        }
    }

    private var ask: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(moment.message)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.text)
                Text(L("혼자 만드는 앱이에요. 작은 응원도 큰 힘이 되고, 더 좋은 앱을 만드는 데 그대로 쓰여요. 기능은 그대로예요.",
                       comment: "Tip ask sheet: a solo developer asks for a small tip; it helps a lot and goes into making the app better. Nothing is locked"))
                    .font(.body)
                    .foregroundStyle(theme.textMuted)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            tips

            if let error = tipJar.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            VStack(spacing: 2) {
                Button {
                    answered = true
                    tipJar.declineAsk()
                    dismiss()
                } label: {
                    Text(L("다음에", comment: "Tip ask card: not now"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                LeeoTipAskNeverButton(tipJar: tipJar) {
                    answered = true
                    dismiss()
                }
            }
        }
    }

    /// 팁 세 개를 나란히. 누르면 바로 결제한다(팁 화면으로 한 번 더 넘기지 않는다).
    @ViewBuilder
    private var tips: some View {
        if tipJar.products.isEmpty {
            ProgressView().frame(height: 88)
        } else {
            HStack(spacing: 10) {
                ForEach(Array(tipJar.products.enumerated()), id: \.element.id) { index, product in
                    let tier = tipJar.tier(for: product.id, fallbackIndex: index)
                    Button {
                        answered = true
                        Task { await tipJar.purchase(product, using: { try await purchaseAction($0) }) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tier.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(theme.accent)
                            Text(tier.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(theme.text)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.center)
                            Text(product.displayPrice)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(theme.accent)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous)
                            .fill(theme.accent.opacity(0.08)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(tipJar.isWorking)
                    .accessibilityLabel("\(tier.title), \(product.displayPrice)")
                }
            }
            .overlay { if tipJar.isWorking { ProgressView() } }
        }
    }

    private var thanks: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(L("정말 고마워요", comment: "Tip ask sheet: thanks after a tip"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.text)
                Text(L("보내 주신 응원으로 계속 다듬을게요.", comment: "Tip ask sheet: thanks body, the developer will keep improving the app"))
                    .font(.body)
                    .foregroundStyle(theme.textMuted)
            }
            .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: {
                Text(L("닫기", comment: "Pricing ladder: close"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(theme.accent))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 창을 띄우는 한 줄

public extension View {
    /// 고마운 순간에 부탁 창(`LeeoTipAskSheet`)을 한 번 띄운다. 언제 · 얼마나 드물게는 `LeeoTipAskPolicy` 가 정한다.
    ///
    /// - Parameters:
    ///   - when: 물어도 되는 사람인가. 유료 등급이 있는 앱은 이미 다 가진 사람에게만(`true` 일 때만 본다).
    ///   - reached: 지금 넘어선 순간, **인상적인 것부터**. 화면이 뜰 때마다 다시 센다.
    ///
    /// ⚠️ 화면이 뜨자마자 띄우지 않는다. 2초 머문 뒤에 본다(앱을 열자마자 막아서지 않게).
    func leeoTipAsk(tipJar: LeeoTipJar, when enabled: Bool = true,
                    reached: @escaping () -> [LeeoTipMoment]) -> some View {
        modifier(LeeoTipAskPresenter(tipJar: tipJar, enabled: enabled, reached: reached))
    }
}

private struct LeeoTipAskPresenter: ViewModifier {
    @ObservedObject var tipJar: LeeoTipJar
    let enabled: Bool
    let reached: () -> [LeeoTipMoment]
    @State private var moment: LeeoTipMoment?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // 팁 상품이 늦게 와도, 앱에 다시 들어와도 다시 본다.
            .task(id: "\(tipJar.isAvailable)-\(enabled)-\(scenePhase == .active)") {
                guard enabled, scenePhase == .active, moment == nil else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                let now = reached()
                guard let next = tipJar.momentToAsk(from: now) else { return }
                tipJar.markAsked(covering: now)
                moment = next
            }
            .sheet(item: $moment) { m in
                LeeoTipAskSheet(tipJar: tipJar, moment: m)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}
#endif
