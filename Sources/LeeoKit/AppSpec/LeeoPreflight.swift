//
//  LeeoPreflight.swift
//  LeeoKit
//
//  타입으로 못 막는 것을 잡아내는 감사기. 컴파일 타임 제약(계약)과 짝을 이룬다.
//
//  - 컴파일 타임: 구독인데 약관 URL 없음 → 애초에 만들 수 없다
//  - 프리플라이트: 유료 상품은 파는데 무료 사용자가 페이월에 닿을 경로가 없음 → 여기서 잡는다
//
//  실행 위치:
//      #if DEBUG
//      LeeoPreflight.report(MyAppSpec.self)     // 앱 시작 시 1회, 콘솔 경고
//      #endif
//
//      // 테스트에서 회귀 방지 (권장 — 앱마다 최소 1개 테스트를 공짜로 얻는다)
//      func testSpecIsSound() {
//          XCTAssertTrue(LeeoPreflight.audit(MyAppSpec.self).contains { $0.severity == .error } == false)
//      }
//

import Foundation

// MARK: - 결과

public struct LeeoPreflightIssue: Sendable, Equatable {
    public enum Severity: String, Sendable, Comparable {
        /// 출시하면 안 되는 상태 (심사 리젝·기능 고장으로 이어짐).
        case error
        /// 의도한 게 맞는지 확인이 필요한 상태.
        case warning
        /// 참고.
        case info

        public var symbol: String {
            switch self { case .error: return "✗"; case .warning: return "⚠︎"; case .info: return "·" }
        }

        private var rank: Int {
            switch self { case .error: return 0; case .warning: return 1; case .info: return 2 }
        }
        public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
    }

    public let severity: Severity
    /// 안정적인 코드 — 테스트에서 특정 이슈만 예외 처리할 때 쓴다.
    public let code: String
    public let message: String

    public init(_ severity: Severity, _ code: String, _ message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

public extension Array where Element == LeeoPreflightIssue {
    var errors: [LeeoPreflightIssue] { filter { $0.severity == .error } }
    var warnings: [LeeoPreflightIssue] { filter { $0.severity == .warning } }
    /// 출시 가능한 상태인지.
    var isReleasable: Bool { errors.isEmpty }
}

// MARK: - 감사기

public enum LeeoPreflight {

    /// 계약을 감사해 문제 목록을 돌려준다. 순수 함수 — 테스트에서 그대로 쓸 수 있다.
    public static func audit<Spec: LeeoAppSpec>(_ spec: Spec.Type) -> [LeeoPreflightIssue] {
        var issues: [LeeoPreflightIssue] = []
        let money = Spec.monetization
        let legal = Spec.legal

        // MARK: 수익모델 ↔ 페이월 정합성

        let actual = Spec.paywall
        // 소비성 크레딧은 LeeoConsumableStore 가 담당하므로 비소모성 페이월 구성이 없는 게 정상이다.
        let isCredits: Bool = { if case .credits = money { return true }; return false }()

        if money.requiresPaywall, !isCredits, actual == nil {
            issues.append(.init(.error, "paywall.missing",
                "\(money.displayName) 모델인데 페이월 구성이 없습니다. monetization 선언을 확인하세요."))
        }
        if !money.requiresPaywall, actual != nil {
            issues.append(.init(.error, "paywall.contradiction",
                "\(money.displayName) 모델인데 paywall 을 직접 선언했습니다. 둘 중 하나가 틀렸습니다 — monetization 선언만 남기세요."))
        }
        if money.requiresPaywall, !isCredits, let actual, actual.productIDs.isEmpty {
            issues.append(.init(.error, "paywall.noProducts",
                "판매 상품 ID가 비어 있습니다. 페이월을 열어도 살 수 있는 게 없습니다."))
        }
        if isCredits, money.productIDs.isEmpty {
            issues.append(.init(.error, "credits.noProducts",
                "크레딧 모델인데 판매할 소비성 상품이 없습니다."))
        }
        if let actual, !actual.entitlementIDs.isSubset(of: Set(actual.productIDs)),
           actual.entitlementIDs.isDisjoint(with: Set(actual.productIDs)) {
            issues.append(.init(.warning, "paywall.entitlementMismatch",
                "entitlementIDs 가 판매 상품과 하나도 겹치지 않습니다. 오타를 의심하세요."))
        }

        // MARK: 게이트 — 팔 물건은 있는데 살 이유가 없는 상태

        if money.hasFreeTier, money.requiresPaywall, !money.gate.hasAnyGate {
            issues.append(.init(.warning, "gate.noPath",
                "무료 사용자가 페이월에 도달할 경로가 없습니다. freeLimits 나 proOnly 를 선언하세요."))
        }
        if !money.hasFreeTier, money.gate.hasAnyGate {
            issues.append(.init(.warning, "gate.unreachable",
                "무료 사용자가 없는 모델인데 게이트 정책이 선언돼 있습니다 — 아무 효과가 없습니다."))
        }
        for (key, limit) in money.gate.freeLimits where limit <= 0 {
            issues.append(.init(.warning, "gate.zeroLimit",
                "freeLimits[\"\(key)\"] 가 \(limit) 입니다 — 무료로 아무것도 못 하는 정책이 맞나요?"))
        }
        let overlap = Set(money.gate.freeLimits.keys).intersection(money.gate.proOnly)
        if !overlap.isEmpty {
            issues.append(.init(.warning, "gate.overlappingKeys",
                "\(overlap.sorted().joined(separator: ", ")) 가 freeLimits 와 proOnly 양쪽에 있습니다 — proOnly 가 이깁니다."))
        }

        // MARK: 법적/지원 링크

        for (name, url) in [("privacyURL", legal.privacyURL), ("supportURL", legal.supportURL)] {
            if url.scheme?.lowercased() != "https" {
                issues.append(.init(.error, "legal.insecureURL", "\(name) 이 https 가 아닙니다: \(url.absoluteString)"))
            }
        }
        if legal.createsAccounts, legal.dataDeletionURL == nil {
            issues.append(.init(.error, "legal.noDeletionPath",
                "계정을 만드는 앱은 계정·데이터 삭제 경로가 심사 필수입니다 (dataDeletionURL)."))
        }
        if money.sellsSubscription, money.subscriptionTermsURL == nil {
            // 타입상 도달 불가지만, 직접 선언한 paywall 로 우회한 경우를 잡는다.
            issues.append(.init(.error, "legal.noTerms", "구독을 파는 앱은 이용약관 링크가 필수입니다."))
        }

        // MARK: 스토어 등록 / 리뷰

        if Spec.appStoreID == nil {
            issues.append(.init(.info, "store.noAppStoreID",
                "appStoreID 가 없어 '리뷰 남기기'는 시스템 평점 프롬프트로만 동작합니다."))
        }

        // MARK: 피드백

        if !Spec.feedback.containerIdentifier.hasPrefix("iCloud.") {
            issues.append(.init(.error, "feedback.badContainer",
                "CloudKit 컨테이너 식별자는 'iCloud.' 로 시작해야 합니다: \(Spec.feedback.containerIdentifier)"))
        }
        if !Spec.developerEmail.contains("@") {
            issues.append(.init(.error, "feedback.badEmail", "developerEmail 형식이 올바르지 않습니다."))
        }

        // MARK: 관측성

        if Spec.analytics is LeeoNoopAnalytics {
            issues.append(.init(.warning, "analytics.noSink",
                "분석 싱크가 없습니다 — 페이월 노출·구매 전환을 아무도 보고 있지 않습니다. "
                + "LeeoUsageAnalytics(spec:) 만 꽂아도 됩니다."))
        }

        // MARK: 완성도 선언

        let unknown = LeeoCapability.allCases.filter {
            if case .unknown = Spec.capabilities[$0] { return !$0.isDerivable }
            return false
        }
        if !unknown.isEmpty {
            issues.append(.init(.info, "capabilities.unknown",
                "완성도 체크리스트에서 아직 판단하지 않은 항목이 \(unknown.count)개 있습니다."))
        }

        return issues.sorted { $0.severity < $1.severity }
    }

    /// 런타임 사용량까지 함께 본다 — 계약은 맞는데 **실제로 호출하지 않은** 경우를 잡는다.
    /// (예: 리뷰 장치를 계약상 갖췄지만 `registerLaunch()` 를 한 번도 부르지 않아 영원히 안 뜨는 상태)
    public static func runtimeAudit<Spec: LeeoAppSpec>(
        _ spec: Spec.Type,
        engagement: LeeoEngagement = .shared
    ) -> [LeeoPreflightIssue] {
        var issues = audit(spec)
        let live = LeeoKit.activation

        if !live.engagement, engagement.launchCount == 0 {
            issues.append(.init(.error, "bootstrap.missing",
                "LeeoKit.bootstrap(_:) 이 호출되지 않았습니다 — 계약은 채웠지만 아무것도 켜지지 않은 상태입니다."))
        }
        if !live.diagnostics {
            issues.append(.init(.warning, "diagnostics.off",
                "크래시·행 진단이 꺼져 있습니다 — 사용자가 겪는 크래시를 아무도 보고 있지 않습니다."))
        }
        if !live.remoteFlags {
            issues.append(.init(.info, "flags.off",
                "원격 킬스위치가 없습니다 — 사고가 나면 심사를 통과할 때까지 손쓸 방법이 없습니다."))
        }
        return issues.sorted { $0.severity < $1.severity }
    }

    /// DEBUG 빌드에서 콘솔로 결과를 출력한다. 릴리즈 빌드에서는 아무 일도 하지 않는다.
    public static func report<Spec: LeeoAppSpec>(
        _ spec: Spec.Type,
        engagement: LeeoEngagement = .shared
    ) {
        #if DEBUG
        let issues = runtimeAudit(spec, engagement: engagement)
        guard !issues.isEmpty else {
            print("✓ [LeeoPreflight] \(Spec.appName) — 문제 없음")
            return
        }
        print("── [LeeoPreflight] \(Spec.appName) ──")
        for issue in issues {
            print("  \(issue.severity.symbol) [\(issue.code)] \(issue.message)")
        }
        #endif
    }
}
