//
//  LeeoSatisfactionCheck.swift
//  LeeoKit
//
//  참여도가 충분히 쌓였을 때 딱 한 번, 방해되지 않게 만족도를 묻는 뷰 모디파이어.
//  "좋아요" → 앱스토어 리뷰 요청(시스템 UI), "아쉬워요" → 피드백 화면으로 라우팅.
//  별점을 강요하지 않고, 불만족 사용자를 리뷰 대신 개선 창구로 보내는 2갈래 패턴.
//
//  사용 예:
//      ContentView()
//          .leeoSatisfactionCheck(MyAppSpec.self)
//          // 필요하면 조건을 조절:
//          .leeoSatisfactionCheck(MyAppSpec.self, config: .init(minLaunches: 6, minDays: 3))
//

import SwiftUI
import StoreKit

public extension View {
    /// 참여도 조건이 충족되면 만족도 체크를 1회 노출한다.
    /// - Parameters:
    ///   - spec: 앱 계약(피드백 라우팅에 사용).
    ///   - config: 노출 조건. 기본값은 보수적(며칠 + 여러 번 실행 + 버전당 1회).
    func leeoSatisfactionCheck<Spec: LeeoAppSpec>(
        _ spec: Spec.Type,
        config: LeeoSatisfactionConfig = LeeoSatisfactionConfig()
    ) -> some View {
        modifier(LeeoSatisfactionModifier<Spec>(config: config))
    }
}

struct LeeoSatisfactionModifier<Spec: LeeoAppSpec>: ViewModifier {
    let config: LeeoSatisfactionConfig

    @Environment(\.requestReview) private var requestReview
    @State private var showPrompt = false
    @State private var showFeedback = false

    func body(content: Content) -> some View {
        content
            .task {
                // 진입 직후 바로 띄우면 방해되므로 잠깐 뒤에 판단한다.
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                guard LeeoEngagement.shared.shouldPromptSatisfaction(config: config) else { return }
                LeeoEngagement.shared.markSatisfactionPrompted()
                withAnimation { showPrompt = true }
            }
            .sheet(isPresented: $showPrompt) {
                LeeoSatisfactionSheet(
                    appName: Spec.appName,
                    onPositive: {
                        LeeoEngagement.shared.markRespondedPositively()
                        showPrompt = false
                        // 시트가 닫힌 뒤 시스템 리뷰 UI를 띄운다 (동시 표시 충돌 방지).
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            await MainActor.run { requestReview() }
                        }
                    },
                    onNegative: {
                        showPrompt = false
                        Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            await MainActor.run { showFeedback = true }
                        }
                    }
                )
            }
            .sheet(isPresented: $showFeedback) {
                // 불만족 사용자는 "개선 제안" 유형으로 프리셋해 진입 마찰을 줄인다.
                LeeoFeedbackView<Spec>(initialType: .improvement)
            }
    }
}

/// 만족도 질문 카드. 시스템 색 기본, `.leeoStyle(_:)`로 앱 테마 주입 가능.
struct LeeoSatisfactionSheet: View {
    let appName: String
    let onPositive: () -> Void
    let onNegative: () -> Void

    @Environment(\.leeoStyle) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundColor(theme.accent)
                .accessibilityHidden(true)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text(String(format: L("%@, 잘 쓰고 계신가요?", comment: "Satisfaction check title, %@ = app name"), appName))
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(theme.text)

                Text(L("솔직한 한마디가 앱을 더 좋게 만들어요.", comment: "Satisfaction check subtitle"))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(theme.textMuted)
            }

            VStack(spacing: 10) {
                Button(action: onPositive) {
                    Text(L("좋아요 👍", comment: "Satisfaction positive button"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(theme.radiusSm)
                }
                .buttonStyle(.plain)

                Button(action: onNegative) {
                    Text(L("아쉬워요", comment: "Satisfaction negative button"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.surfaceAlt)
                        .foregroundColor(theme.text)
                        .cornerRadius(theme.radiusSm)
                }
                .buttonStyle(.plain)
            }

            Button(L("나중에", comment: "Satisfaction dismiss button")) { dismiss() }
                .font(.subheadline)
                .foregroundColor(theme.textMuted)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(theme.bg.ignoresSafeArea())
        #if os(iOS)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        #endif
    }
}
