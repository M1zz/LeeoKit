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
//
//  묻는 횟수의 규칙(`LeeoTipAskPolicy`):
//   - 한 번 물으면 60일은 다시 묻지 않는다
//   - 팁을 낸 사람에게는 180일 동안 묻지 않는다
//   - '다음에' 를 세 번 누르면 다시는 묻지 않는다
//   - 같은 순간은 한 번만. 보여 줄 때 함께 넘어선 더 작은 순간도 다 쓴 것으로 친다
//

import SwiftUI

// MARK: - 순간

/// 팁을 부탁할 만한 순간 하나. `id` 는 앱 안에서 고정된 이름(예: "saved.5h"), `message` 는 그 사람의 숫자를 담은 한 줄.
public struct LeeoTipMoment: Equatable, Sendable {
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
    public static func pick(reached: [LeeoTipMoment], seen: Set<String>,
                            lastAskedAt: Date?, lastTipAt: Date?, laters: Int,
                            now: Date) -> LeeoTipMoment? {
        guard laters < maxLaters else { return nil }
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
                                     lastTipAt: lastTipAt, laters: askLaters, now: now)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.text)
                    Text(L("혼자 만들고 고쳐 가는 앱이에요. 앞으로도 계속 다듬을 수 있게 조금만 힘을 보태 주시겠어요?",
                           comment: "Tip ask card: asks for support so the developer can keep maintaining the app"))
                        .font(.footnote)
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
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                Button(action: onSupport) {
                    Text(L("응원하기", comment: "Tip ask card: open the tip jar"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: theme.radiusLg, style: .continuous).fill(theme.surface))
    }
}
