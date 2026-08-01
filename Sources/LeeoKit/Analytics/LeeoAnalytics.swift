//
//  LeeoAnalytics.swift
//  LeeoKit
//
//  분석 SDK 를 넣지 않는다. **이벤트 규약과 발화 지점만** 공용화하고, 실제 전송은
//  앱이 주입한 싱크가 담당한다. 이렇게 하면 앱마다 이벤트 이름이 제각각이 되는 문제를
//  막으면서도 LeeoKit 이 특정 벤더에 묶이지 않는다.
//
//  - 기본값은 `LeeoNoopAnalytics` — 아무것도 하지 않는다 (분석 미도입 앱도 그대로 동작).
//  - `LeeoConsoleAnalytics` — DEBUG 에서 콘솔로 확인.
//  - `LeeoUsageAnalytics` — 이미 있는 `LeeoUsageReporter`(CloudKit)로 흘려보낸다.
//
//  LeeoKit 내부 컴포넌트(페이월·게이트·리뷰·피드백)는 스스로 이벤트를 발화하므로,
//  싱크만 꽂으면 "페이월 노출 → 구매 전환" 퍼널이 앱 코드 한 줄 없이 생긴다.
//
//  사용 예:
//      enum MyAppSpec: LeeoAppSpec {
//          ...
//          static let analytics: any LeeoAnalytics = LeeoUsageAnalytics(spec: MyAppSpec.self)
//      }
//

import Foundation

// MARK: - 이벤트

/// LeeoKit 이 발화하는 표준 이벤트. 앱 고유 이벤트는 `.custom` 을 쓴다.
public enum LeeoEvent: Sendable, Equatable {
    /// 게이트에 막혀 페이월을 띄워야 하는 상황이 발생 (key = 기능 키).
    case gateBlocked(key: String)
    /// 페이월 화면 노출 (reason = 유입 계기).
    case paywallShown(reason: String?)
    /// 페이월에서 상품 구매 시도.
    case purchaseStarted(productID: String)
    /// 구매 성공 (권한 확보).
    case purchaseCompleted(productID: String)
    /// 구매 실패/취소.
    case purchaseFailed(productID: String, reason: String?)
    /// 구매 복원 완료 (restored = 권한을 되찾았는지).
    case purchaseRestored(restored: Bool)
    /// 만족도 프롬프트 노출.
    case satisfactionPromptShown
    /// 리뷰 요청으로 이어짐.
    case reviewRequested
    /// 피드백 제출.
    case feedbackSubmitted(type: String)
    /// 앱 고유 이벤트.
    case custom(name: String, parameters: [String: String])

    /// 전송용 이벤트 이름 (snake_case 고정 — 벤더 간 이식성).
    public var name: String {
        switch self {
        case .gateBlocked:             return "gate_blocked"
        case .paywallShown:            return "paywall_shown"
        case .purchaseStarted:         return "purchase_started"
        case .purchaseCompleted:       return "purchase_completed"
        case .purchaseFailed:          return "purchase_failed"
        case .purchaseRestored:        return "purchase_restored"
        case .satisfactionPromptShown: return "satisfaction_prompt_shown"
        case .reviewRequested:         return "review_requested"
        case .feedbackSubmitted:       return "feedback_submitted"
        case .custom(let name, _):     return name
        }
    }

    /// 전송용 파라미터.
    public var parameters: [String: String] {
        switch self {
        case .gateBlocked(let key):                    return ["key": key]
        case .paywallShown(let reason):                return reason.map { ["reason": $0] } ?? [:]
        case .purchaseStarted(let id),
             .purchaseCompleted(let id):               return ["product_id": id]
        case .purchaseFailed(let id, let reason):
            var p = ["product_id": id]
            if let reason { p["reason"] = reason }
            return p
        case .purchaseRestored(let restored):          return ["restored": restored ? "1" : "0"]
        case .satisfactionPromptShown, .reviewRequested: return [:]
        case .feedbackSubmitted(let type):             return ["type": type]
        case .custom(_, let parameters):               return parameters
        }
    }
}

// MARK: - 싱크

/// 이벤트를 어디로 보낼지 결정하는 최소 규약. 앱이 원하는 SDK 로 구현한다.
public protocol LeeoAnalytics: Sendable {
    func track(_ event: LeeoEvent)
}

public extension LeeoAnalytics {
    /// 앱 고유 이벤트 축약형.
    func track(_ name: String, _ parameters: [String: String] = [:]) {
        track(.custom(name: name, parameters: parameters))
    }
}

/// 기본값 — 아무것도 하지 않는다.
public struct LeeoNoopAnalytics: LeeoAnalytics {
    public init() {}
    public func track(_ event: LeeoEvent) {}
}

/// DEBUG 콘솔 출력용.
public struct LeeoConsoleAnalytics: LeeoAnalytics {
    public init() {}
    public func track(_ event: LeeoEvent) {
        #if DEBUG
        let params = event.parameters.isEmpty
            ? ""
            : " " + event.parameters.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        print("📊 [Leeo] \(event.name)\(params)")
        #endif
    }
}

/// 이미 있는 CloudKit 사용 통계(`LeeoUsageReporter`)로 이벤트를 흘려보낸다.
/// 별도 SDK 없이 "분석 있음"을 만족시키는 가장 싼 경로.
public struct LeeoUsageAnalytics: LeeoAnalytics {
    private let reporter: LeeoUsageReporter

    public init(reporter: LeeoUsageReporter) {
        self.reporter = reporter
    }

    public init<Spec: LeeoAppSpec>(spec: Spec.Type) {
        self.init(reporter: LeeoUsageReporter(spec: spec))
    }

    public func track(_ event: LeeoEvent) {
        reporter.logEventInBackground(event.name)
    }
}

// MARK: - 전역 접근점

/// LeeoKit 내부 컴포넌트가 이벤트를 발화할 때 쓰는 창구.
///
/// 뷰/스토어에 Spec 타입이 항상 흘러가 있지는 않으므로, 앱 시작 시 한 번 등록해두고
/// 내부에서는 여기로 보낸다. 등록하지 않으면 no-op 이라 아무 일도 일어나지 않는다.
public enum LeeoAnalyticsCenter {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sink: any LeeoAnalytics = LeeoNoopAnalytics()

    /// 앱 시작 시 1회. 보통 `LeeoAnalyticsCenter.register(MyAppSpec.self)` 로 충분하다.
    public static func register(_ sink: any LeeoAnalytics) {
        lock.lock(); defer { lock.unlock() }
        self.sink = sink
    }

    /// 계약에 선언된 싱크를 그대로 등록한다.
    public static func register<Spec: LeeoAppSpec>(_ spec: Spec.Type) {
        register(spec.analytics)
    }

    /// 이벤트 발화 — LeeoKit 내부와 앱 양쪽에서 쓸 수 있다.
    public static func track(_ event: LeeoEvent) {
        lock.lock()
        let current = sink
        lock.unlock()
        current.track(event)
    }
}
