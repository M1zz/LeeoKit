//
//  LeeoSupportSection.swift
//  LeeoKit
//
//  설정 화면에 넣는 표준 "지원" 행 묶음 — 피드백 보내기 + (마스터 모드) 개발자 인박스.
//  새 앱은 설정 List/Form 안에 이 한 줄이면 피드백 시스템이 켜진다:
//
//      Section(...) {
//          LeeoSupportSection<MyAppSpec>(showInbox: masterModeEnabled)
//      }
//

import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif

public struct LeeoSupportSection<Spec: LeeoAppSpec>: View {
    private let showInbox: Bool
    private let emailFallback: ((String, String) -> Bool)?

    /// - Parameters:
    ///   - showInbox: 개발자(마스터 모드) 인박스 행 노출 여부
    ///   - emailFallback: 앱 자체 메일 컴포저 (LeeoFeedbackView와 동일 규약)
    public init(showInbox: Bool = false, emailFallback: ((String, String) -> Bool)? = nil) {
        self.showInbox = showInbox
        self.emailFallback = emailFallback
    }

    @Environment(\.requestReview) private var requestReview
    /// 개발자 모드 — 앱 버전을 7번 탭하면 토글. 켜지면 접수된 피드백(인박스)이 보인다.
    @AppStorage("dev.masterMode") private var devMode = false

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    public var body: some View {
        NavigationLink(destination: LeeoFeedbackView<Spec>(emailFallback: emailFallback)) {
            Label(L("피드백 보내기", comment: "Feedback view title"),
                  systemImage: "envelope.badge")
        }
        // 리뷰 남기기 — appStoreID 가 있으면 작성 페이지로, 없으면 시스템 평점 프롬프트
        Button {
            if let id = Spec.appStoreID {
                LeeoReviewRequest.openWriteReview(appStoreID: id)
            } else {
                LeeoReviewRequest.markRequested()
                requestReview()
            }
        } label: {
            Label(L("리뷰 남기기", comment: "Write a review entry"), systemImage: "star.bubble")
        }
        if showInbox || devMode {
            NavigationLink(destination: LeeoFeedbackInboxView<Spec>()) {
                Label(L("접수된 피드백 (개발자)", comment: "Feedback inbox settings entry (developer)"),
                      systemImage: "tray.full")
            }
        }
        // 앱 버전 — 7번 탭하면 개발자 모드(인박스) 토글. 모든 앱에 공통 노출.
        HStack {
            Label(L("버전", comment: "App version row"), systemImage: "info.circle")
            Spacer()
            Text(appVersion).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 7) { devMode.toggle() }
    }
}
