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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LeeoTipText.entry)
                        Text(LeeoTipText.entrySubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
            }
        }
    }
}

// MARK: - 부탁 카드 자리

public struct LeeoTipAskSlot<Spec: LeeoAppSpec>: View {
    @ObservedObject private var tipJar: LeeoTipJar
    private let reached: [LeeoTipMoment]
    @State private var moment: LeeoTipMoment?
    @State private var showTipJar = false

    /// - Parameter reached: 지금 넘어선 순간, 인상적인 것부터.
    public init(tipJar: LeeoTipJar, reached: [LeeoTipMoment]) {
        self.tipJar = tipJar
        self.reached = reached
    }

    public var body: some View {
        Group {
            if let moment {
                LeeoTipAskCard(tipJar: tipJar, moment: moment,
                               onSupport: { showTipJar = true },
                               onLater: { withAnimation(.easeInOut(duration: 0.2)) { self.moment = nil } })
                    // 카드가 실제로 섰을 때 물은 것으로 적는다. 함께 넘어선 작은 순간도 다 쓴 것으로 친다.
                    .onAppear { tipJar.markAsked(covering: reached) }
                    .sheet(isPresented: $showTipJar, onDismiss: { self.moment = nil }) {
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
        .onAppear(perform: evaluate)
        .onChange(of: tipJar.isAvailable) { evaluate() }
        .onChange(of: reached.map(\.id)) { evaluate() }
    }

    /// 이미 카드가 서 있으면 그대로 둔다. 상품이 아직 안 왔으면 묻지 않는다(`momentToAsk`).
    private func evaluate() {
        guard moment == nil else { return }
        moment = tipJar.momentToAsk(from: reached)
    }
}
