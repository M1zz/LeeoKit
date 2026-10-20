//
//  LeeoReviewGate.swift
//  LeeoKit
//
//  "앱을 즐겁게 쓰고 계신가요?" 능동적 만족도 프롬프트.
//  - 만족 → 시스템 App Store 리뷰 요청
//  - 아쉬움 → 피드백 화면(개선 제안)으로 연결
//  좋은 인상일 때만 리뷰를 유도하고, 불편한 사용자는 스토어 별점 대신 피드백으로 흡수한다.
//  - 나중에 → 답이 아니다. 버전·쿨다운 대신 짧게 미룬다 (LeeoReviewPolicy.laterDays + 새 긍정행동)
//
//  묻는 때: 앱을 켜자마자보다 **사용자가 무언가를 해낸 직후**가 좋다. 그 자리에서
//  shouldRequest 를 확인하고 `.leeoReviewGate` 바인딩을 켜는 방식(2번)을 우선 쓴다.
//
//  사용 예:
//      // 1) 자동: 조건(LeeoReviewPolicy)이 맞으면 화면 진입 시 스스로 물어본다
//      SomeRootView()
//          .leeoSatisfactionCheck(MyAppSpec.self)
//
//      // 2) 수동: 특정 시점에 직접 띄운다
//      .leeoReviewGate(MyAppSpec.self, isPresented: $showGate)
//

import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif

// MARK: - 프롬프트 본체 (Binding 제어)

private struct LeeoReviewGateModifier<Spec: LeeoAppSpec>: ViewModifier {
    @Binding var isPresented: Bool
    let policy: LeeoReviewPolicy
    let engagement: LeeoEngagement

    @Environment(\.requestReview) private var requestReview
    @Environment(\.leeoStyle) private var theme
    @State private var showFeedback = false
    /// 이번 노출에서 사용자가 답했는가. 답 없이 닫히면 "나중에"로 본다.
    @State private var answered = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                String(format: L("%@를 즐겁게 쓰고 계신가요?", comment: "Satisfaction prompt title"), Spec.displayName),
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button(L("네, 좋아요 👍", comment: "Satisfaction: happy")) {
                    answered = true
                    LeeoReviewRequest.markRequested(engagement: engagement)
                    requestReview()
                }
                Button(L("아쉬운 점이 있어요", comment: "Satisfaction: unhappy")) {
                    answered = true
                    LeeoReviewRequest.markRequested(engagement: engagement)
                    showFeedback = true
                }
                Button(L("나중에", comment: "Satisfaction: later"), role: .cancel) {}
            } message: {
                Text(L("의견을 들려주시면 더 좋은 앱으로 만들 수 있어요.", comment: "Satisfaction prompt message"))
            }
            // "나중에"·바깥 눌러 닫기는 답이 아니다 — 띄울 때 남긴 버전·쿨다운 기록을 짧은 미룸으로 바꾼다.
            // 버튼 동작이 닫힘보다 늦게 올 수 있어 잠깐 기다린 뒤 판정한다.
            .onChange(of: isPresented) { _, shown in
                guard !shown else { answered = false; return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !answered { LeeoReviewRequest.markLater(policy: policy, engagement: engagement) }
                }
            }
            .sheet(isPresented: $showFeedback) {
                LeeoFeedbackView<Spec>(initialType: .improvement)
                    .leeoStyle(theme)
            }
    }
}

// MARK: - 자동 트리거 (조건 충족 시 스스로 노출)

private struct LeeoAutoSatisfactionModifier<Spec: LeeoAppSpec>: ViewModifier {
    let policy: LeeoReviewPolicy
    let engagement: LeeoEngagement
    let delay: Double

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                guard LeeoReviewRequest.shouldRequest(policy: policy, engagement: engagement) else { return }
                // 화면이 자리 잡은 뒤 살짝 지연해서 자연스럽게 노출
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                // 노출하는 순간 쿨다운을 기록해 다음 실행에서 곧바로 다시 뜨지 않게 한다
                LeeoReviewRequest.markRequested(engagement: engagement)
                isPresented = true
            }
            .modifier(LeeoReviewGateModifier<Spec>(
                isPresented: $isPresented, policy: policy, engagement: engagement))
    }
}

// MARK: - View API

public extension View {
    /// 만족도 프롬프트를 바인딩으로 직접 제어한다.
    func leeoReviewGate<Spec: LeeoAppSpec>(
        _ spec: Spec.Type,
        isPresented: Binding<Bool>,
        policy: LeeoReviewPolicy = .default,
        engagement: LeeoEngagement = .shared
    ) -> some View {
        modifier(LeeoReviewGateModifier<Spec>(
            isPresented: isPresented, policy: policy, engagement: engagement))
    }

    /// 사용량이 정책 조건을 만족하면 화면 진입 시 스스로 "즐겁게 쓰고 계신가요?"를 물어본다.
    /// 쿨다운·버전 조건이 내장되어 있어 과하게 반복되지 않는다.
    func leeoSatisfactionCheck<Spec: LeeoAppSpec>(
        _ spec: Spec.Type,
        policy: LeeoReviewPolicy = .default,
        engagement: LeeoEngagement = .shared,
        delay: Double = 1.2
    ) -> some View {
        modifier(LeeoAutoSatisfactionModifier<Spec>(
            policy: policy, engagement: engagement, delay: delay))
    }
}
