//
//  LeeoGatePolicy.swift
//  LeeoKit
//
//  "지금 페이월을 띄워야 하나?" 의 **판정만** 담당한다. 페이월 화면이 어떻게 생겼는지는
//  앱(또는 LeeoPaywallView)의 몫이고, 여기서는 무료 한도·프로 전용 기능·체험 기간을
//  선언해두면 순수 함수로 답이 나온다. 앱마다 다시 짜던 "n개 넘으면 잠금" 로직의 종착지.
//
//  사용 예:
//      // 계약에 한 번 선언
//      static let monetization = LeeoMonetization.freemium(
//          LeeoPurchaseConfig(productIDs: ["com.Ysoup.MyApp.pro"],
//                             gate: LeeoGatePolicy(freeLimits: ["memo": 10],
//                                                  proOnly: ["export"])))
//
//      // 호출부 — 앱이 짜는 코드는 이게 전부
//      switch store.gate.evaluate("memo", current: memos.count) {
//      case .allowed:                    save()
//      case .allowedNearLimit(let n):    save(); toast("무료 \(n)개 남았어요")
//      case .blocked(let reason):        showPaywall(reason)
//      }
//

import Foundation

// MARK: - 정책 선언

/// 무료로 어디까지 허용할지의 선언. 이 값이 "페이월이 필요한 앱인가"의 실질적 정의다.
public struct LeeoGatePolicy: Sendable, Equatable {
    /// 기능 키별 무료 허용 개수. 예: `["memo": 10, "exportPerDay": 3]`
    /// 여기 없는 키는 개수 제한이 없다.
    public let freeLimits: [String: Int]

    /// 개수와 무관하게 프로 권한이 있어야만 쓸 수 있는 기능 키.
    public let proOnly: Set<String>

    /// 남은 여유분이 이 값 이하이면 `.allowedNearLimit` 으로 알려준다 (0이면 알리지 않음).
    /// 한도에 부딪히기 **전에** 부드럽게 알리는 편이 전환율·체감 모두 낫다.
    public let warnWhenRemaining: Int

    /// 체험(무료 사용) 기간 정책. 체험 중에는 모든 게이트가 열린다.
    public let trial: LeeoTrial

    /// 게이트를 두지 않는 정책 — 유료 다운로드 앱이나 전체 무료 앱이 쓴다.
    public static let none = LeeoGatePolicy()

    public init(
        freeLimits: [String: Int] = [:],
        proOnly: Set<String> = [],
        warnWhenRemaining: Int = 0,
        trial: LeeoTrial = .none
    ) {
        self.freeLimits = freeLimits
        self.proOnly = proOnly
        self.warnWhenRemaining = warnWhenRemaining
        self.trial = trial
    }

    /// 무료 사용자가 페이월에 도달할 수 있는 경로가 하나라도 있는지.
    /// false 인데 유료 상품을 판다면 "팔 물건은 있는데 살 이유를 만들지 않은" 상태다 (Preflight 경고).
    public var hasAnyGate: Bool { !freeLimits.isEmpty || !proOnly.isEmpty }

    /// 이 정책이 다루는 모든 기능 키 (매니페스트·디버그 표시용).
    public var allKeys: Set<String> { Set(freeLimits.keys).union(proOnly) }
}

/// 체험 기간 정책. 판정에 필요한 사용량은 `LeeoEngagement` 에서 읽는다.
public enum LeeoTrial: Sendable, Equatable {
    /// 체험 없음.
    case none
    /// 설치 후 N일간 전체 기능 개방.
    case days(Int)
    /// 앱 실행 N회까지 전체 기능 개방.
    case launches(Int)

    /// 지금 체험이 유효한지 — 사용량 기록 기준.
    public func isActive(engagement: LeeoEngagement = .shared) -> Bool {
        switch self {
        case .none:              return false
        case .days(let d):       return engagement.daysSinceInstall < d
        case .launches(let n):   return engagement.launchCount <= n
        }
    }

    /// 체험 잔여량 (일 또는 실행 횟수). 체험이 끝났거나 없으면 0.
    public func remaining(engagement: LeeoEngagement = .shared) -> Int {
        switch self {
        case .none:            return 0
        case .days(let d):     return max(0, d - engagement.daysSinceInstall)
        case .launches(let n): return max(0, n - engagement.launchCount + 1)
        }
    }
}

// MARK: - 판정 결과

/// 게이트 판정 결과.
public enum LeeoGateDecision: Sendable, Equatable {
    /// 그냥 해도 된다.
    case allowed
    /// 해도 되지만 무료 여유분이 `remaining` 개 남았다 (부드러운 안내용).
    case allowedNearLimit(remaining: Int)
    /// 막혔다 — 페이월을 띄울 시점.
    case blocked(LeeoGateReason)

    /// 진행해도 되는지 (near-limit 포함).
    public var isAllowed: Bool {
        if case .blocked = self { return false }
        return true
    }

    /// 페이월을 띄워야 하는지.
    public var needsPaywall: Bool { !isAllowed }
}

/// 막힌 이유 — 페이월이 "무엇을 팔지"를 정하는 데 쓴다 (`LeeoProFeature` 로 연결).
public struct LeeoGateReason: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// 무료 한도 `limit` 을 다 썼다.
        case limitReached(limit: Int)
        /// 프로 전용 기능이다.
        case proOnlyFeature
    }

    /// 부딪힌 기능 키.
    public let key: String
    public let kind: Kind

    /// 사용자에게 보여줄 기본 문구 (앱이 자체 문구를 쓰면 무시해도 된다).
    public var localizedMessage: String {
        switch kind {
        case .limitReached(let limit):
            return String(format: L("무료로는 %d개까지 쓸 수 있어요.", comment: "Gate: free limit reached"), limit)
        case .proOnlyFeature:
            return L("프로 전용 기능이에요.", comment: "Gate: pro only feature")
        }
    }
}

// MARK: - 판정기

/// 정책 + 현재 권한을 묶어 판정을 수행하는 순수 값 타입.
/// `LeeoStore.gate` 로 자동 생성되지만, 스토어 없이 테스트/프리뷰에서 직접 만들어 쓸 수도 있다.
public struct LeeoGate: Sendable {
    public let policy: LeeoGatePolicy
    /// 프로 권한 보유 여부.
    public let hasPro: Bool
    /// 체험 유효 여부 (기본은 policy.trial 을 사용량 기록으로 평가한 값).
    public let isTrialActive: Bool

    public init(policy: LeeoGatePolicy, hasPro: Bool, isTrialActive: Bool) {
        self.policy = policy
        self.hasPro = hasPro
        self.isTrialActive = isTrialActive
    }

    public init(policy: LeeoGatePolicy, hasPro: Bool, engagement: LeeoEngagement = .shared) {
        self.init(policy: policy, hasPro: hasPro, isTrialActive: policy.trial.isActive(engagement: engagement))
    }

    /// 모든 게이트가 열려 있는 상태인지 (구매했거나 체험 중).
    public var isUnlocked: Bool { hasPro || isTrialActive }

    /// - Parameters:
    ///   - key: 기능 키 (`freeLimits`/`proOnly` 에서 쓴 이름).
    ///   - current: 지금 보유/사용 중인 개수. 개수 개념이 없는 기능은 생략.
    ///   - adding: 이번에 추가하려는 개수 (기본 1). 0이면 "쓸 수 있는지"만 확인.
    public func evaluate(_ key: String, current: Int = 0, adding: Int = 1) -> LeeoGateDecision {
        if isUnlocked { return .allowed }

        if policy.proOnly.contains(key) {
            return .blocked(LeeoGateReason(key: key, kind: .proOnlyFeature))
        }

        guard let limit = policy.freeLimits[key] else { return .allowed }

        // 이번 동작까지 반영했을 때 한도를 넘는가.
        guard current + adding <= limit else {
            return .blocked(LeeoGateReason(key: key, kind: .limitReached(limit: limit)))
        }

        let remaining = limit - (current + adding)
        if policy.warnWhenRemaining > 0, remaining <= policy.warnWhenRemaining {
            return .allowedNearLimit(remaining: remaining)
        }
        return .allowed
    }

    /// 개수 개념 없이 "이 기능 써도 되나"만 묻는 축약형.
    public func allows(_ key: String) -> Bool {
        evaluate(key, adding: 0).isAllowed
    }

    /// 남은 무료 여유분. 한도가 없거나 이미 해제됐으면 nil.
    public func remaining(_ key: String, current: Int) -> Int? {
        guard !isUnlocked, let limit = policy.freeLimits[key] else { return nil }
        return max(0, limit - current)
    }
}
