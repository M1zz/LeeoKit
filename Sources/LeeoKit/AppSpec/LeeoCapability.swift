//
//  LeeoCapability.swift
//  LeeoKit
//
//  포트폴리오 완성도 체크리스트(8개 영역)를 코드 선언으로 옮긴 것.
//  지금까지 이 목록은 소스를 grep 해서 **추정**했고, 그래서 46개 앱 중 21개만 스캔되고
//  나머지는 "미확인(?)" 이었다. 앱이 스스로 신고하면 추정이 실측이 된다.
//
//  핵심은 3분법이다:
//    - `.implemented`   구현했다
//    - `.notApplicable` 이 앱에는 해당 없다 (이유를 반드시 적는다)
//    - `.unknown`       아직 판단하지 않았다  ← 미선언의 기본값
//
//  "안 해도 되는 것"과 "안 한 것"을 구분하는 게 이 타입의 존재 이유다.
//  LeeoKit 이 이미 제공하는 항목(피드백·리뷰요청·결제 안정성·정책 링크 등)은
//  `LeeoManifest` 가 계약에서 자동으로 `.providedByLeeoKit` 으로 채우므로 앱이 적을 필요가 없다.
//
//  사용 예:
//      static let capabilities = LeeoCapabilities(
//          implemented: [.cloudSync, .backupExport, .darkMode, .localization, .emptyStates],
//          notApplicable: [.pushNotifications: "알림이 필요 없는 단발성 유틸리티",
//                          .accountDeletion: "계정 개념 없음"])
//

import Foundation

// MARK: - 영역

/// 완성도 체크리스트의 8개 영역.
public enum LeeoCapabilityCategory: String, Sendable, CaseIterable, Codable {
    case data          // 데이터 안정성
    case resilience    // 장애 대응·복원력
    case qa            // 품질 보증
    case observability // 관측성
    case security      // 보안·개인정보
    case ux            // UX 완성도
    case growth        // 성장·리텐션
    case marketing     // 마케팅·홍보

    public var label: String {
        switch self {
        case .data:          return L("데이터 안정성", comment: "Capability category: data")
        case .resilience:    return L("장애 대응·복원력", comment: "Capability category: resilience")
        case .qa:            return L("품질 보증(QA)", comment: "Capability category: QA")
        case .observability: return L("관측성", comment: "Capability category: observability")
        case .security:      return L("보안·개인정보", comment: "Capability category: security")
        case .ux:            return L("UX 완성도", comment: "Capability category: UX")
        case .growth:        return L("성장·리텐션", comment: "Capability category: growth")
        case .marketing:     return L("마케팅·홍보", comment: "Capability category: marketing")
        }
    }

    public var emoji: String {
        switch self {
        case .data: return "🗄️"; case .resilience: return "🛟"
        case .qa: return "🧪";   case .observability: return "🔭"
        case .security: return "🔐"; case .ux: return "✨"
        case .growth: return "📈"; case .marketing: return "📣"
        }
    }
}

// MARK: - 항목

/// 완성도 체크리스트의 개별 항목.
public enum LeeoCapability: String, Sendable, CaseIterable, Codable {
    // 데이터 안정성
    case cloudSync, backupExport, structuredStorage, schemaMigration
    case syncConflictResolution, transactionAtomicity, dataIntegrityCheck, autosaveRecovery

    // 장애 대응·복원력
    case crashReporting, emptyStates, networkRetry, globalErrorHandling, killSwitch, rollbackPlan

    // 품질 보증
    case automatedTests, staticAnalysis, continuousIntegration, betaTesting, regressionRoutine, codeReview

    // 관측성
    case analytics, feedbackChannel, performanceMonitoring, structuredLogging, metricsDashboard

    // 보안·개인정보
    case biometricLock, privacyManifest, accountDeletion, policyLinks, encryption, minimalPermissions

    // UX 완성도
    case accessibility, localization, darkMode, onboarding, deviceCoverage, microInteractions

    // 성장·리텐션
    case reviewPrompt, pushNotifications, purchaseReliability, widgets
    case conversionFunnel, retentionAnalysis, abTesting

    // 마케팅·홍보
    case appStoreListing, supportPage, showcaseSite, published, promotionChannels, campaigns, aso, community

    public var category: LeeoCapabilityCategory {
        switch self {
        case .cloudSync, .backupExport, .structuredStorage, .schemaMigration,
             .syncConflictResolution, .transactionAtomicity, .dataIntegrityCheck, .autosaveRecovery:
            return .data
        case .crashReporting, .emptyStates, .networkRetry, .globalErrorHandling, .killSwitch, .rollbackPlan:
            return .resilience
        case .automatedTests, .staticAnalysis, .continuousIntegration, .betaTesting, .regressionRoutine, .codeReview:
            return .qa
        case .analytics, .feedbackChannel, .performanceMonitoring, .structuredLogging, .metricsDashboard:
            return .observability
        case .biometricLock, .privacyManifest, .accountDeletion, .policyLinks, .encryption, .minimalPermissions:
            return .security
        case .accessibility, .localization, .darkMode, .onboarding, .deviceCoverage, .microInteractions:
            return .ux
        case .reviewPrompt, .pushNotifications, .purchaseReliability, .widgets,
             .conversionFunnel, .retentionAnalysis, .abTesting:
            return .growth
        case .appStoreListing, .supportPage, .showcaseSite, .published, .promotionChannels, .campaigns, .aso, .community:
            return .marketing
        }
    }

    public var label: String {
        switch self {
        case .cloudSync:               return L("클라우드 동기화", comment: "Capability: cloud sync")
        case .backupExport:            return L("백업·복원/내보내기", comment: "Capability: backup export")
        case .structuredStorage:       return L("구조적 로컬 DB", comment: "Capability: structured storage")
        case .schemaMigration:         return L("스키마 마이그레이션", comment: "Capability: schema migration")
        case .syncConflictResolution:  return L("동기화 충돌 처리", comment: "Capability: sync conflict")
        case .transactionAtomicity:    return L("트랜잭션 원자성", comment: "Capability: transaction atomicity")
        case .dataIntegrityCheck:      return L("데이터 무결성 검증", comment: "Capability: data integrity")
        case .autosaveRecovery:        return L("자동저장·작업 복구", comment: "Capability: autosave recovery")

        case .crashReporting:          return L("크래시·장애 모니터링", comment: "Capability: crash reporting")
        case .emptyStates:             return L("빈/에러/로딩 상태 UI", comment: "Capability: empty states")
        case .networkRetry:            return L("네트워크 재시도·타임아웃", comment: "Capability: network retry")
        case .globalErrorHandling:     return L("전역 에러 핸들링·폴백 화면", comment: "Capability: global error handling")
        case .killSwitch:              return L("기능 플래그·원격 킬스위치", comment: "Capability: kill switch")
        case .rollbackPlan:            return L("롤백 전략", comment: "Capability: rollback plan")

        case .automatedTests:          return L("자동화 테스트", comment: "Capability: automated tests")
        case .staticAnalysis:          return L("정적 분석(SwiftLint)", comment: "Capability: static analysis")
        case .continuousIntegration:   return L("CI/CD 파이프라인", comment: "Capability: CI/CD")
        case .betaTesting:             return L("베타 테스트(TestFlight)", comment: "Capability: beta testing")
        case .regressionRoutine:       return L("회귀 테스트 루틴", comment: "Capability: regression routine")
        case .codeReview:              return L("코드 리뷰 프로세스", comment: "Capability: code review")

        case .analytics:               return L("사용현황 분석", comment: "Capability: analytics")
        case .feedbackChannel:         return L("피드백 채널", comment: "Capability: feedback channel")
        case .performanceMonitoring:   return L("성능 모니터링", comment: "Capability: performance monitoring")
        case .structuredLogging:       return L("구조적 로그·원격 진단", comment: "Capability: structured logging")
        case .metricsDashboard:        return L("핵심지표 대시보드", comment: "Capability: metrics dashboard")

        case .biometricLock:           return L("보안·생체 인증", comment: "Capability: biometric lock")
        case .privacyManifest:         return L("개인정보 매니페스트", comment: "Capability: privacy manifest")
        case .accountDeletion:         return L("계정·데이터 삭제 경로", comment: "Capability: account deletion")
        case .policyLinks:             return L("개인정보 처리방침·약관 링크", comment: "Capability: policy links")
        case .encryption:              return L("전송·저장 암호화", comment: "Capability: encryption")
        case .minimalPermissions:      return L("최소 권한 요청", comment: "Capability: minimal permissions")

        case .accessibility:           return L("접근성", comment: "Capability: accessibility")
        case .localization:            return L("다국어·현지화", comment: "Capability: localization")
        case .darkMode:                return L("다크모드", comment: "Capability: dark mode")
        case .onboarding:              return L("온보딩·권한 사전안내", comment: "Capability: onboarding")
        case .deviceCoverage:          return L("다양한 기기·화면 대응", comment: "Capability: device coverage")
        case .microInteractions:       return L("햅틱·스켈레톤·마이크로카피", comment: "Capability: micro interactions")

        case .reviewPrompt:            return L("리뷰요청 장치", comment: "Capability: review prompt")
        case .pushNotifications:       return L("푸시 알림·재참여", comment: "Capability: push notifications")
        case .purchaseReliability:     return L("결제·구독 안정성", comment: "Capability: purchase reliability")
        case .widgets:                 return L("위젯·확장 표면", comment: "Capability: widgets")
        case .conversionFunnel:        return L("온보딩 완료·전환 퍼널", comment: "Capability: conversion funnel")
        case .retentionAnalysis:       return L("리텐션·코호트 분석", comment: "Capability: retention analysis")
        case .abTesting:               return L("A/B 테스트", comment: "Capability: A/B testing")

        case .appStoreListing:         return L("App Store 등록", comment: "Capability: App Store listing")
        case .supportPage:             return L("지원·랜딩 페이지", comment: "Capability: support page")
        case .showcaseSite:            return L("공개 쇼케이스 사이트", comment: "Capability: showcase site")
        case .published:               return L("실제 발행·게시", comment: "Capability: published")
        case .promotionChannels:       return L("홍보 채널 다변화", comment: "Capability: promotion channels")
        case .campaigns:               return L("이벤트·캠페인 진행", comment: "Capability: campaigns")
        case .aso:                     return L("ASO 키워드 최적화", comment: "Capability: ASO")
        case .community:               return L("커뮤니티·제휴·인플루언서", comment: "Capability: community")
        }
    }

    /// 이 항목이 계약 선언만으로 충족될 수 있는지 (= LeeoKit 이 판단 가능).
    /// 나머지는 앱이 직접 신고해야 한다.
    public var isDerivable: Bool {
        switch self {
        case .analytics, .feedbackChannel, .reviewPrompt, .purchaseReliability,
             .policyLinks, .accountDeletion, .appStoreListing, .supportPage, .showcaseSite:
            return true
        default:
            return false
        }
    }
}

// MARK: - 상태

/// 항목별 상태.
public enum LeeoCapabilityState: Sendable, Equatable, Codable {
    /// LeeoKit 이 제공한다 — 계약 선언만으로 충족됨.
    case providedByLeeoKit
    /// 앱이 직접 구현했다.
    case implemented
    /// 이 앱에는 해당 없다 (이유 필수).
    case notApplicable(reason: String)
    /// 아직 판단하지 않았다.
    case unknown

    /// 완성도 계산의 분자에 들어가는가.
    public var counts: Bool {
        switch self {
        case .providedByLeeoKit, .implemented: return true
        case .notApplicable, .unknown:         return false
        }
    }

    /// 완성도 계산의 분모에 들어가는가 (해당 없음·미판단은 제외).
    public var isMeasured: Bool {
        switch self {
        case .providedByLeeoKit, .implemented: return true
        case .notApplicable, .unknown:         return false
        }
    }

    /// 직렬화용 짧은 문자열.
    public var rawLabel: String {
        switch self {
        case .providedByLeeoKit: return "provided"
        case .implemented:       return "implemented"
        case .notApplicable:     return "not_applicable"
        case .unknown:           return "unknown"
        }
    }
}

// MARK: - 선언

/// 앱이 신고하는 완성도 선언. LeeoKit 이 스스로 알 수 있는 항목은 적지 않아도 된다.
public struct LeeoCapabilities: Sendable {
    /// 명시적으로 선언된 항목만 담는다. 나머지는 `.unknown`.
    public let declared: [LeeoCapability: LeeoCapabilityState]

    /// 아무것도 선언하지 않은 상태 — 전 항목 `.unknown`.
    public static let undeclared = LeeoCapabilities()

    public init(_ declared: [LeeoCapability: LeeoCapabilityState] = [:]) {
        self.declared = declared
    }

    /// 가장 흔한 형태 — 구현한 것과 해당 없는 것만 적는다.
    /// 적지 않은 항목은 `.unknown` 이며, 그 자체가 "아직 안 봤다"는 정직한 신호다.
    public init(
        implemented: Set<LeeoCapability> = [],
        notApplicable: [LeeoCapability: String] = [:]
    ) {
        var map: [LeeoCapability: LeeoCapabilityState] = [:]
        for c in implemented { map[c] = .implemented }
        for (c, reason) in notApplicable { map[c] = .notApplicable(reason: reason) }
        self.declared = map
    }

    public subscript(_ capability: LeeoCapability) -> LeeoCapabilityState {
        declared[capability] ?? .unknown
    }

    /// 다른 선언을 덮어씌운 새 선언 (LeeoKit 파생값을 앱 선언 위에 얹을 때 사용).
    /// 앱이 명시한 값이 항상 이긴다 — 자동 추론이 사람의 판단을 덮어쓰지 않는다.
    public func merging(_ other: [LeeoCapability: LeeoCapabilityState]) -> LeeoCapabilities {
        var map = other
        for (k, v) in declared { map[k] = v }
        return LeeoCapabilities(map)
    }
}
