//
//  LeeoAppSpec.swift
//  LeeoKit
//
//  모든 앱이 반드시 구현해야 하는 계약.
//
//  LeeoKit 은 컴포넌트 모음이 아니라 **성숙도 계약**이다. 이 프로토콜을 만족한다는 것은
//  그 앱이 다음을 이미 결정했다는 뜻이다 —
//    · 수익모델과 그에 딸린 의무(페이월·복원·약관)         → `monetization`
//    · 개인정보/지원 링크                                  → `legal`
//    · 사용자 피드백을 받는 경로                            → `feedback`
//    · 완성도 체크리스트에서 무엇을 했고 무엇이 해당 없는지  → `capabilities`
//
//  "나중에 정하지"를 컴파일 에러로 바꾸는 게 목적이다. 항목을 빼먹으면 빌드가 실패한다.
//
//  사용 예:
//      enum MyAppSpec: LeeoAppSpec {
//          static let appName = "MyApp"
//          static let developerEmail = "leeo@kakao.com"
//          static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.MyApp")
//          static let legal = LeeoLegalConfig(
//              privacyURL: URL(string: "https://ysoup.io/myapp/privacy")!,
//              supportURL: URL(string: "https://ysoup.io/myapp/support")!)
//          static let monetization = LeeoMonetization.free
//      }
//

import Foundation

public protocol LeeoAppSpec {
    /// 사용자에게 노출되는 앱 이름 (메일 제목, 알림 문구 등에 사용)
    static var appName: String { get }

    /// 피드백 이메일 폴백 수신 주소
    static var developerEmail: String { get }

    /// 피드백 시스템 설정 (CloudKit 컨테이너 등)
    static var feedback: LeeoFeedbackConfig { get }

    /// 개인정보 처리방침·지원 페이지 링크. **기본값 없음** — 모든 앱의 의무다.
    static var legal: LeeoLegalConfig { get }

    /// 수익모델. **기본값 없음** — "이 앱에 페이월이 필요한가"를 앱마다 다시 고민하지 않기 위해
    /// 한 번은 반드시 선언한다. 결제가 없으면 `.free` 또는 `.paidUpfront` 를 고르면 된다.
    /// 선언하는 순간 페이월 필요 여부·복원 의무·약관 링크 의무가 전부 따라온다.
    static var monetization: LeeoMonetization { get }

    /// App Store 숫자 ID — "리뷰 남기기" 딥링크에 사용. 미지정(nil)이면 시스템 리뷰 요청만 쓴다.
    /// (시스템 평점 프롬프트 `requestReview` 는 ID 없이도 동작한다.)
    static var appStoreID: String? { get }

    /// 완성도 체크리스트 선언. 미지정이면 전 항목 `.unknown` — "아직 안 봤음"으로 정직하게 집계된다.
    static var capabilities: LeeoCapabilities { get }

    /// 분석 이벤트 싱크. 미지정이면 no-op (분석을 안 쓰는 앱도 그대로 동작).
    static var analytics: any LeeoAnalytics { get }

    /// 인앱 결제(페이월) 설정. **보통 선언하지 않는다** — `monetization` 에서 자동으로 유도된다.
    /// 직접 선언하면 그 값이 우선하지만, `monetization` 과 어긋나면 Preflight 가 잡아낸다.
    static var paywall: LeeoPaywallConfig? { get }
}

public extension LeeoAppSpec {
    /// 기본값 — 앱이 지정하지 않으면 딥링크형 "리뷰 남기기"는 숨기고 시스템 요청만 사용.
    static var appStoreID: String? { nil }

    /// 기본값 — 선언하지 않은 항목은 전부 `.unknown`.
    static var capabilities: LeeoCapabilities { .undeclared }

    /// 기본값 — 아무 데도 보내지 않는다.
    static var analytics: any LeeoAnalytics { LeeoNoopAnalytics() }

    /// 수익모델에서 유도한 페이월 구성. 앱이 직접 선언하면 그쪽이 이긴다.
    static var paywall: LeeoPaywallConfig? { monetization.paywallConfig(legal: legal) }

    /// 무료 한도·프로 전용 기능 정책 (수익모델에서 유도).
    static var gate: LeeoGatePolicy { monetization.gate }

    /// 소비성 결제 구성 (크레딧 모델에만 존재).
    static var consumable: LeeoConsumableConfig? { monetization.consumableConfig }
}

/// 피드백 시스템의 CloudKit 연결 설정.
public struct LeeoFeedbackConfig: Sendable {
    /// CloudKit 컨테이너 식별자 (Public DB에 Feedback 레코드 저장)
    public let containerIdentifier: String

    /// Dashboard의 Record Type 이름 — 바꾸면 기존 피드백이 조회에서 빠진다
    public let recordType: String

    /// 새 피드백 푸시 구독 ID — 바꾸면 기존 기기의 구독을 해제할 수 없다
    public let subscriptionID: String

    /// 여러 앱이 컨테이너 하나를 공유(피드백 허브)할 때 앱 구분값 (레코드의 appId 필드).
    /// nil이면 appId 필드를 아예 쓰지 않는다 — 기존 단일 앱 스키마와 100% 호환.
    /// ⚠️ nil → 값 전환 시 Production 스키마에 appId 필드 배포가 선행되어야 한다.
    public let appIdentifier: String?

    public init(
        containerIdentifier: String,
        recordType: String = "Feedback",
        subscriptionID: String = "feedback-new-v1",
        appIdentifier: String? = nil
    ) {
        self.containerIdentifier = containerIdentifier
        self.recordType = recordType
        self.subscriptionID = subscriptionID
        self.appIdentifier = appIdentifier
    }
}
