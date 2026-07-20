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

    public var body: some View {
        NavigationLink(destination: LeeoFeedbackView<Spec>(emailFallback: emailFallback)) {
            Label(L("피드백 보내기", comment: "Feedback view title"),
                  systemImage: "envelope.badge")
        }
        if showInbox {
            NavigationLink(destination: LeeoFeedbackInboxView<Spec>()) {
                Label(L("접수된 피드백 (개발자)", comment: "Feedback inbox settings entry (developer)"),
                      systemImage: "tray.full")
            }
        }
    }
}
