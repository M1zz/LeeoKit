//
//  LeeoTier.swift
//  LeeoKit
//
//  유료 등급(예: 플러스 · 프로). 등급이 없는 앱은 지금처럼 "프로냐 아니냐" 하나로 판정한다.
//  등급을 쓰면 `LeeoGatePolicy.tiers` 에 **낮은 등급부터** 적는다. 높은 등급은 아래 등급의 기능을 모두 연다.
//
//  사용 예:
//      gate: LeeoGatePolicy(
//          freeLimits: ["groupCreate": 1],
//          tiers: [
//              LeeoTier(id: "plus", name: "플러스",
//                       productIDs: ["app.plus.yearly", "app.plus.monthly", "app.plus.lifetime"],
//                       features: ["groupCreate", "insights"],
//                       highlights: ["그룹을 여러 개 만들어요", "자세한 통계를 봐요"]),
//              LeeoTier(id: "pro", name: "프로",
//                       productIDs: ["app.pro.yearly", "app.pro.monthly", "app.pro.lifetime"],
//                       features: ["map"],
//                       highlights: ["식사 지도를 봐요"]),
//          ])
//
//  구독 상품은 App Store Connect 에서 **한 구독 그룹**에 넣고 높은 등급을 위 레벨로 둔다.
//  그래야 올리고 내릴 때 App Store 가 남은 기간을 알아서 정산한다.
//

import Foundation

public struct LeeoTier: Sendable, Equatable, Identifiable {
    /// 바꾸지 않는 식별자 (분석 · 판정용). 예: "plus", "pro"
    public let id: String
    /// 결제 화면에 보이는 이름. 예: "플러스"
    public let name: String
    /// 이 등급을 여는 상품 (보이는 순서 = 이 순서, 첫 상품이 기본 선택)
    public let productIDs: [String]
    /// 이 등급에서 **새로** 열리는 기능 키. 아래 등급의 기능은 다시 적지 않는다.
    public let features: Set<String>
    /// 결제 화면의 혜택 문구 (이 등급에서 새로 열리는 것만)
    public let highlights: [String]

    public init(id: String, name: String, productIDs: [String], features: Set<String>, highlights: [String] = []) {
        self.id = id
        self.name = name
        self.productIDs = productIDs
        self.features = features
        self.highlights = highlights
    }
}

public extension LeeoGatePolicy {
    /// 이 기능을 여는 가장 낮은 등급의 순번. 등급과 상관없는 기능이면 nil.
    func requiredTierIndex(for key: String) -> Int? {
        tiers.firstIndex { $0.features.contains(key) }
    }

    /// 가진 상품이 여는 가장 높은 등급의 순번. 등급 상품이 하나도 없으면 nil.
    func tierIndex(owning productIDs: Set<String>) -> Int? {
        tiers.lastIndex { !productIDs.isDisjoint(with: $0.productIDs) }
    }
}
