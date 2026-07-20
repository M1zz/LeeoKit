//
//  LeeoAppSpec.swift
//  LeeoKit
//
//  모든 앱이 반드시 구현해야 하는 계약.
//  LeeoKit의 기능 컴포넌트(피드백 등)는 이 프로토콜 준수 없이는 생성할 수 없다 —
//  "LeeoKit을 쓰는 앱은 이 항목들을 반드시 채운다"를 컴파일 타임에 강제하는 장치.
//
//  사용 예:
//      enum MyAppSpec: LeeoAppSpec {
//          static let appName = "MyApp"
//          static let developerEmail = "leeo@kakao.com"
//          static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.MyApp")
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
