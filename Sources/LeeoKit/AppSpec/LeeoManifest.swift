//
//  LeeoManifest.swift
//  LeeoKit
//
//  계약 선언을 기계가 읽을 수 있는 형태로 내보낸다.
//
//  포트폴리오 완성도 탐색기(`docs/portfolio-explorer.html`)는 지금까지 소스를 grep 해서
//  완성도를 **추정**했다. 그래서 46개 앱 중 21개만 스캔되고 나머지는 "미확인"이었다.
//  앱이 매니페스트를 내보내면 추정이 실측이 된다.
//
//  사용 예:
//      // 어디서든 (테스트 타깃이 가장 흔하다)
//      let json = try LeeoManifest(spec: MyAppSpec.self).jsonString()
//      print(json)
//
//      // 또는 디버그 메뉴에서 공유 시트로 내보내기
//      LeeoManifest(spec: MyAppSpec.self).summaryLines.forEach { print($0) }
//

import Foundation

// MARK: - 매니페스트

public struct LeeoManifest: Sendable {
    /// 스키마 버전 — 탐색기가 파싱 규칙을 고정할 수 있게 한다.
    public static let schema = "leeo.manifest/1"

    public let appName: String
    public let appStoreID: String?
    public let developerEmail: String

    public let monetizationModel: String
    public let productIDs: [String]
    public let requiresPaywall: Bool
    public let sellsSubscription: Bool
    public let hasFreeTier: Bool
    public let gate: LeeoGatePolicy

    public let privacyURL: URL
    public let supportURL: URL
    public let termsURL: URL?
    public let dataDeletionURL: URL?
    public let marketingURL: URL?

    /// 앱 선언 + LeeoKit 파생값을 합친 최종 상태 (앱 선언이 우선).
    public let capabilities: [LeeoCapability: LeeoCapabilityState]

    /// 프리플라이트 감사 결과.
    public let issues: [LeeoPreflightIssue]

    public init<Spec: LeeoAppSpec>(spec: Spec.Type) {
        self.appName = Spec.appName
        self.appStoreID = Spec.appStoreID
        self.developerEmail = Spec.developerEmail

        let money = Spec.monetization
        self.monetizationModel = money.explorerModel
        self.productIDs = money.productIDs
        self.requiresPaywall = money.requiresPaywall
        self.sellsSubscription = money.sellsSubscription
        self.hasFreeTier = money.hasFreeTier
        self.gate = money.gate

        let legal = Spec.legal
        self.privacyURL = legal.privacyURL
        self.supportURL = legal.supportURL
        self.termsURL = money.subscriptionTermsURL ?? legal.termsURL
        self.dataDeletionURL = legal.dataDeletionURL
        self.marketingURL = legal.marketingURL

        self.capabilities = Spec.capabilities
            .merging(Self.derivedCapabilities(spec: spec))
            .declared
        self.issues = LeeoPreflight.audit(spec)
    }

    // MARK: - LeeoKit 이 계약만 보고 채울 수 있는 항목

    /// 앱이 적을 필요가 없는 항목들. 계약 선언에서 그대로 유도된다.
    /// 앱이 같은 항목을 명시하면 앱 선언이 이긴다 (`LeeoCapabilities.merging`).
    static func derivedCapabilities<Spec: LeeoAppSpec>(spec: Spec.Type) -> [LeeoCapability: LeeoCapabilityState] {
        var out: [LeeoCapability: LeeoCapabilityState] = [:]
        let money = Spec.monetization
        let legal = Spec.legal

        // 피드백: LeeoKit 이 CloudKit 접수 + 이메일 폴백 + 인박스를 제공한다.
        out[.feedbackChannel] = .providedByLeeoKit

        // 리뷰요청: LeeoReviewGate/LeeoEngagement 가 제공한다.
        out[.reviewPrompt] = .providedByLeeoKit

        // 정책 링크: 계약이 URL 을 강제하므로 항상 존재한다.
        out[.policyLinks] = .providedByLeeoKit

        // 지원 페이지: 계약 필수.
        out[.supportPage] = .providedByLeeoKit

        // 분석: 싱크를 꽂았을 때만.
        out[.analytics] = Spec.analytics is LeeoNoopAnalytics ? .unknown : .providedByLeeoKit

        // 결제 안정성: LeeoStore 가 트랜잭션 리스너·복원·환불 반영을 담당한다.
        // 파는 게 없으면 "해당 없음".
        out[.purchaseReliability] = money.requiresPaywall
            ? .providedByLeeoKit
            : .notApplicable(reason: L("판매하는 상품이 없음", comment: "Capability N/A: no products"))

        // 계정·데이터 삭제: 계정을 안 만드는 앱은 해당 없음.
        out[.accountDeletion] = legal.createsAccounts
            ? (legal.dataDeletionURL != nil ? .implemented : .unknown)
            : .notApplicable(reason: L("계정 개념 없음", comment: "Capability N/A: no accounts"))

        // App Store 등록 / 쇼케이스.
        out[.appStoreListing] = Spec.appStoreID != nil ? .implemented : .unknown
        if legal.marketingURL != nil { out[.showcaseSite] = .implemented }

        // 이번 실행에서 실제로 켠 것들만 추가로 인정한다 — 모듈이 있다는 것과
        // 앱이 그걸 켰다는 것은 다르다. (켜지 않았으면 `.unknown` 그대로 둔다.)
        let live = LeeoKit.activation
        if live.diagnostics { out[.crashReporting] = .providedByLeeoKit }
        if live.remoteFlags { out[.killSwitch] = .providedByLeeoKit }

        return out
    }

    // MARK: - 집계

    public func state(_ capability: LeeoCapability) -> LeeoCapabilityState {
        capabilities[capability] ?? .unknown
    }

    /// 영역별 집계.
    public struct CategorySummary: Sendable {
        public let category: LeeoCapabilityCategory
        public let satisfied: Int      // 구현됨 + LeeoKit 제공
        public let measured: Int       // 판정된 항목 수 (해당없음·미판단 제외)
        public let notApplicable: Int
        public let unknown: Int
        public var total: Int { measured + notApplicable + unknown }
        /// 판정된 항목 대비 충족률. 판정된 게 없으면 0.
        public var percent: Int { measured > 0 ? Int((Double(satisfied) / Double(measured) * 100).rounded()) : 0 }
    }

    public var categorySummaries: [CategorySummary] {
        LeeoCapabilityCategory.allCases.map { category in
            let items = LeeoCapability.allCases.filter { $0.category == category }
            var satisfied = 0, measured = 0, na = 0, unknown = 0
            for item in items {
                let s = state(item)
                if s.isMeasured { measured += 1; if s.counts { satisfied += 1 } }
                if case .notApplicable = s { na += 1 }
                if case .unknown = s { unknown += 1 }
            }
            return CategorySummary(category: category, satisfied: satisfied,
                                   measured: measured, notApplicable: na, unknown: unknown)
        }
    }

    /// 전체 완성도(%) — 판정된 항목 대비 충족률. 탐색기의 계산식과 같다.
    public var completeness: Int {
        let all = LeeoCapability.allCases.map { state($0) }
        let measured = all.filter(\.isMeasured).count
        let satisfied = all.filter(\.counts).count
        return measured > 0 ? Int((Double(satisfied) / Double(measured) * 100).rounded()) : 0
    }

    /// 아직 판단하지 않은 항목 수 — 이 숫자가 0이 되는 것이 "완성도 점검을 마쳤다"의 정의다.
    public var unknownCount: Int {
        LeeoCapability.allCases.filter { if case .unknown = state($0) { return true }; return false }.count
    }

    // MARK: - 내보내기

    /// 탐색기가 읽는 JSON. 키는 `LeeoManifest.schema` 버전에 고정된다.
    public func jsonObject() -> [String: Any] {
        var capsOut: [String: Any] = [:]
        for capability in LeeoCapability.allCases {
            let s = state(capability)
            var entry: [String: Any] = [
                "state": s.rawLabel,
                "category": capability.category.rawValue,
                "label": capability.label,
            ]
            if case .notApplicable(let reason) = s { entry["reason"] = reason }
            capsOut[capability.rawValue] = entry
        }

        let categories: [[String: Any]] = categorySummaries.map {
            [
                "key": $0.category.rawValue,
                "label": $0.category.label,
                "satisfied": $0.satisfied,
                "measured": $0.measured,
                "notApplicable": $0.notApplicable,
                "unknown": $0.unknown,
                "percent": $0.percent,
            ]
        }

        return [
            "schema": Self.schema,
            "app": [
                "name": appName,
                "appStoreID": appStoreID as Any,
                "developerEmail": developerEmail,
            ],
            "monetization": [
                "model": monetizationModel,
                "productIDs": productIDs,
                "requiresPaywall": requiresPaywall,
                "sellsSubscription": sellsSubscription,
                "hasFreeTier": hasFreeTier,
                "gate": [
                    "freeLimits": gate.freeLimits,
                    "proOnly": Array(gate.proOnly).sorted(),
                    "hasAnyGate": gate.hasAnyGate,
                ],
            ],
            "legal": [
                "privacyURL": privacyURL.absoluteString,
                "supportURL": supportURL.absoluteString,
                "termsURL": termsURL?.absoluteString as Any,
                "dataDeletionURL": dataDeletionURL?.absoluteString as Any,
                "marketingURL": marketingURL?.absoluteString as Any,
            ],
            "capabilities": capsOut,
            "categories": categories,
            "completeness": completeness,
            "unknownCount": unknownCount,
            "preflight": [
                "errors": issues.filter { $0.severity == .error }.count,
                "warnings": issues.filter { $0.severity == .warning }.count,
                "issues": issues.map { ["severity": $0.severity.rawValue, "code": $0.code, "message": $0.message] },
            ],
        ]
    }

    public func jsonString(prettyPrinted: Bool = true) throws -> String {
        let options: JSONSerialization.WritingOptions = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        let data = try JSONSerialization.data(withJSONObject: jsonObject(), options: options)
        return String(decoding: data, as: UTF8.self)
    }

    /// 콘솔에 바로 찍어 볼 요약.
    public var summaryLines: [String] {
        var lines = [
            "── \(appName) ──",
            "수익모델: \(monetizationModel)  페이월: \(requiresPaywall ? "필요" : "불필요")",
            "완성도: \(completeness)%  (미판단 \(unknownCount)개)",
        ]
        for s in categorySummaries {
            lines.append("  \(s.category.emoji) \(s.category.label): \(s.satisfied)/\(s.measured) (\(s.percent)%)"
                         + (s.unknown > 0 ? "  미판단 \(s.unknown)" : ""))
        }
        if !issues.isEmpty {
            lines.append("  ⚠︎ 프리플라이트 \(issues.count)건")
            lines.append(contentsOf: issues.map { "    \($0.severity.symbol) \($0.message)" })
        }
        return lines
    }
}
