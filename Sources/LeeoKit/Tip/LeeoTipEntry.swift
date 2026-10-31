//
//  LeeoTipEntry.swift
//  LeeoKit
//
//  팁을 앱에 붙이는 두 자리. 앱마다 같은 코드를 다시 쓰지 않게 여기 둔다.
//
//  - 설정의 '개발자 응원하기' 줄: 판매 중인 팁이 있어야 선다.
//      LeeoTipJarLink<MyAppSpec>(tipJar: tipJar)
//
//  - 고마운 순간의 부탁 카드: 그 사람이 앱으로 얻은 것이 숫자로 보이는 자리(무언가를 막 끝낸 화면)에 둔다.
//    넘어선 순간을 **인상적인 것부터** 넘기면, 물어도 될 때만(`LeeoTipAskPolicy`) 카드가 선다.
//      LeeoTipAskSlot<MyAppSpec>(tipJar: tipJar, reached: MyTipMoments.reachedNow)
//
//  ⚠️ 유료 등급이 있는 앱은 **이미 다 가진 사람**에게만 부탁한다. 아직 안 산 사람에게는 페이월이 맞는 길이다.
//     그런 앱은 `isPro` 일 때만 `LeeoTipAskSlot` 을 세운다.
//

import SwiftUI

// MARK: - 설정 줄

public struct LeeoTipJarLink<Spec: LeeoAppSpec>: View {
    @ObservedObject private var tipJar: LeeoTipJar
    private let systemImage: String

    public init(tipJar: LeeoTipJar, systemImage: String = "heart.fill") {
        self.tipJar = tipJar
        self.systemImage = systemImage
    }

    public var body: some View {
        if tipJar.isAvailable {
            NavigationLink {
                LeeoTipJarView<Spec>(tipJar: tipJar)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LeeoTipText.entry)
                        // 낸 사람에게는 설명 대신 후원자 배지 — 리이오의 어느 앱에서 냈든 여기 보인다.
                        if tipJar.level != nil {
                            LeeoSupporterBadge(tipJar: tipJar)
                        } else {
                            Text(LeeoTipText.entrySubtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
            }
            .task { await tipJar.syncSupporter(containerIdentifier: Spec.feedback.containerIdentifier) }
        }
    }
}

// MARK: - 후원자 배지

/// 응원 단계 배지(그림 · 단계 · 점수). 낸 적이 없으면 아무것도 그리지 않는다.
/// 설정의 '개발자 응원하기' 줄(`LeeoTipJarLink`)에 이미 들어 있다. 팁 줄을 직접 그리는 앱은 이것을 붙인다.
public struct LeeoSupporterBadge: View {
    @ObservedObject private var tipJar: LeeoTipJar
    @Environment(\.leeoStyle) private var theme

    public init(tipJar: LeeoTipJar) {
        self.tipJar = tipJar
    }

    public var body: some View {
        if let level = tipJar.level {
            Label {
                Text(String(format: L("%1$@ · %2$d점", comment: "Supporter badge: level and points. %1$@ = level, %2$d = points"),
                            level.title, tipJar.points))
            } icon: {
                Image(systemName: level.symbol)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(theme.accent.opacity(0.14)))
            .accessibilityLabel(String(format: L("후원자 배지: %1$@, %2$d점", comment: "Supporter badge: accessibility label. %1$@ = level, %2$d = points"),
                                       level.title, tipJar.points))
        }
    }
}

// MARK: - 부탁 카드 자리

public struct LeeoTipAskSlot<Spec: LeeoAppSpec>: View {
    @ObservedObject private var tipJar: LeeoTipJar
    private let reached: [LeeoTipMoment]
    /// 화면에 세운 순간. 세운 뒤에는 물은 것으로 적혀 `momentToAsk` 가 nil 이 되므로 여기 붙잡아 둔다.
    @State private var shown: LeeoTipMoment?
    @State private var closed = false
    @State private var showTipJar = false

    /// - Parameter reached: 지금 넘어선 순간, 인상적인 것부터.
    public init(tipJar: LeeoTipJar, reached: [LeeoTipMoment]) {
        self.tipJar = tipJar
        self.reached = reached
    }

    /// ⚠️ 빈 자리에 붙인 `onAppear` 는 불리지 않는다. 그래서 물을지는 그릴 때마다 계산한다
    ///    (상품이 늦게 와도 `tipJar` 를 관찰하므로 다시 그려진다).
    private var moment: LeeoTipMoment? {
        if closed { return nil }
        return shown ?? tipJar.momentToAsk(from: reached)
    }

    public var body: some View {
        if let moment {
            LeeoTipAskCard(tipJar: tipJar, moment: moment,
                           onSupport: { showTipJar = true },
                           onLater: { withAnimation(.easeInOut(duration: 0.2)) { closed = true } })
                // 카드가 실제로 섰을 때 물은 것으로 적는다. 함께 넘어선 작은 순간도 다 쓴 것으로 친다.
                .onAppear {
                    guard shown == nil else { return }
                    shown = moment
                    tipJar.markAsked(covering: reached)
                }
                .sheet(isPresented: $showTipJar, onDismiss: { closed = true }) {
                    NavigationStack {
                        LeeoTipJarView<Spec>(tipJar: tipJar)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(L("닫기", comment: "Close")) { showTipJar = false }
                                }
                            }
                    }
                }
        }
    }
}
