//
//  LeeoMonetization.swift
//  LeeoKit
//
//  수익모델을 **판단이 아니라 선언**으로 바꾸는 타입.
//
//  "이 앱에 페이월이 필요한가?" 를 앱마다 다시 고민하지 않는다. 계약에 모델 하나를 고르면
//  ① 페이월 필요 여부 ② 복원 버튼 노출 여부 ③ 약관 링크 의무 ④ 게이트 정책까지
//  전부 따라온다. 표현 불가능한 상태(구독인데 약관 없음, 무료인데 상품 ID 있음)는
//  타입 차원에서 만들 수 없다.
//
//  사용 예:
//      enum MyAppSpec: LeeoAppSpec {
//          static let appName = "MyApp"
//          static let developerEmail = "leeo@kakao.com"
//          static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.MyApp")
//          static let legal = LeeoLegalConfig(privacyURL: ..., supportURL: ...)
//
//          // 이 한 줄이 "페이월이 필요한가"의 답이다
//          static let monetization = LeeoMonetization.freemium(
//              LeeoPurchaseConfig(
//                  productIDs: ["com.Ysoup.MyApp.pro"],
//                  gate: LeeoGatePolicy(freeLimits: ["memo": 10], proOnly: ["export"])))
//      }
//

import Foundation

// MARK: - 모델

/// 앱의 수익모델. 포트폴리오 완성도 탐색기의 모델 분류와 1:1로 대응한다.
public enum LeeoMonetization: Sendable {
    /// 완전 무료. 페이월·결제 코드가 존재하지 않는다.
    case free

    /// 스토어 유료 다운로드. 앱 안에는 결제가 없다 (페이월 불필요).
    case paidUpfront

    /// 유료 다운로드 + 구독. 다운로드 값을 받고도 구독 상품을 추가로 판다.
    case paidUpfrontSubscription(LeeoSubscriptionConfig)

    /// 부분유료 — 무료로 쓰다가 1회 구매로 영구 해제.
    case freemium(LeeoPurchaseConfig)

    /// 부분유료 + 구독 — 무료로 쓰다가 구독(또는 평생 상품)으로 해제.
    case freemiumSubscription(LeeoSubscriptionConfig)

    /// 소비성 크레딧/코인 — 쓸 때마다 차감되는 모델.
    case credits(LeeoConsumableConfig)

    // MARK: 파생 정보 — 앱이 다시 판단할 필요가 없는 것들

    /// 앱 안에 페이월(상품 판매 화면)이 있어야 하는가.
    public var requiresPaywall: Bool {
        switch self {
        case .free, .paidUpfront:                             return false
        case .paidUpfrontSubscription, .freemium,
             .freemiumSubscription, .credits:                 return true
        }
    }

    /// 자동 갱신 구독을 파는가 — 약관 링크·갱신 고지가 심사 필수가 되는 조건.
    public var sellsSubscription: Bool {
        switch self {
        case .paidUpfrontSubscription, .freemiumSubscription: return true
        default:                                              return false
        }
    }

    /// "구매 복원" 경로가 필요한가 (비소모성/구독을 파는 경우 App Store 심사 필수).
    /// 소비성 크레딧은 복원 대상이 아니다.
    public var requiresRestore: Bool {
        switch self {
        case .freemium, .freemiumSubscription, .paidUpfrontSubscription: return true
        case .free, .paidUpfront, .credits:                              return false
        }
    }

    /// 무료 사용자가 존재하는가 (= 게이트 정책이 의미를 갖는가).
    public var hasFreeTier: Bool {
        switch self {
        case .free, .freemium, .freemiumSubscription, .credits: return true
        case .paidUpfront, .paidUpfrontSubscription:            return false
        }
    }

    /// 판매 상품 ID 전체.
    public var productIDs: [String] {
        switch self {
        case .free, .paidUpfront:                       return []
        case .freemium(let c):                          return c.productIDs
        case .paidUpfrontSubscription(let c),
             .freemiumSubscription(let c):              return c.productIDs
        case .credits(let c):                           return c.productIDs
        }
    }

    /// 무료 한도/프로 전용 기능 정책. 게이트가 없는 모델은 `.none`.
    public var gate: LeeoGatePolicy {
        switch self {
        case .free, .paidUpfront:                       return .none
        case .freemium(let c):                          return c.gate
        case .paidUpfrontSubscription(let c),
             .freemiumSubscription(let c):              return c.gate
        case .credits:                                  return .none   // 크레딧은 잔액이 곧 게이트
        }
    }

    /// 구독일 때의 이용약관 URL (타입이 보장하므로 옵셔널이 아니다). 그 외엔 nil.
    public var subscriptionTermsURL: URL? {
        switch self {
        case .paidUpfrontSubscription(let c), .freemiumSubscription(let c): return c.termsURL
        default:                                                           return nil
        }
    }

    /// 포트폴리오 탐색기(`portfolio-explorer.html`)가 쓰는 모델 문자열.
    public var explorerModel: String {
        switch self {
        case .free:                      return "free"
        case .paidUpfront:               return "paid"
        case .paidUpfrontSubscription:   return "paid+subscription"
        case .freemium:                  return "freemium"
        case .freemiumSubscription:      return "freemium-subscription"
        case .credits:                   return "freemium"   // 무료 설치 + 소비성 결제
        }
    }

    /// 사람이 읽는 이름.
    public var displayName: String {
        switch self {
        case .free:                    return L("무료", comment: "Monetization: free")
        case .paidUpfront:             return L("유료", comment: "Monetization: paid")
        case .paidUpfrontSubscription: return L("유료 + 구독", comment: "Monetization: paid + subscription")
        case .freemium:                return L("부분유료", comment: "Monetization: freemium")
        case .freemiumSubscription:    return L("부분유료 + 구독", comment: "Monetization: freemium + subscription")
        case .credits:                 return L("크레딧", comment: "Monetization: credits")
        }
    }
}

// MARK: - 1회 구매 구성

/// 비소모성 1회 구매(영구 해제) 구성.
public struct LeeoPurchaseConfig: Sendable {
    /// 판매할 StoreKit 상품 ID (배열 순서 = 화면 노출 순서).
    public let productIDs: [String]
    /// "프로 권한 있음"으로 인정할 ID. 기본은 판매 상품 전체.
    public let entitlementIDs: Set<String>
    /// 무료 한도·프로 전용 기능 정책 — 페이월에 도달하는 경로를 정의한다.
    public let gate: LeeoGatePolicy
    /// 권한 캐시 suite (앱 그룹). 위젯/확장과 Pro 상태를 공유하고 오프라인에서도 즉시 해제한다.
    public let cacheSuiteName: String?
    /// 첫 진입 시 상품 자동 로드 여부.
    public let autoLoad: Bool

    public init(
        productIDs: [String],
        entitlementIDs: Set<String>? = nil,
        gate: LeeoGatePolicy = .none,
        cacheSuiteName: String? = nil,
        autoLoad: Bool = true
    ) {
        self.productIDs = productIDs
        self.entitlementIDs = entitlementIDs ?? Set(productIDs)
        self.gate = gate
        self.cacheSuiteName = cacheSuiteName
        self.autoLoad = autoLoad
    }
}

// MARK: - 구독 구성

/// 자동 갱신 구독 구성.
///
/// `termsURL` 이 **옵셔널이 아니다** — 구독을 판다고 선언하는 순간 이용약관 링크는
/// App Store 심사 필수 항목이 되므로, 없으면 아예 컴파일되지 않게 한다.
/// (개인정보 처리방침은 `LeeoLegalConfig.privacyURL` 에서 온다 — 모든 앱의 공통 의무라 중복 선언하지 않는다.)
public struct LeeoSubscriptionConfig: Sendable {
    /// 판매할 상품 ID. 평생 해제(비소모성) 상품을 함께 팔면 여기에 같이 넣는다.
    public let productIDs: [String]
    /// "프로 권한 있음"으로 인정할 ID. 기본은 판매 상품 전체.
    public let entitlementIDs: Set<String>
    /// 이용약관 URL — 구독 앱의 심사 필수 항목.
    public let termsURL: URL
    /// 무료 한도·프로 전용 기능 정책.
    public let gate: LeeoGatePolicy
    /// 권한 캐시 suite (앱 그룹).
    public let cacheSuiteName: String?
    /// 첫 진입 시 상품 자동 로드 여부.
    public let autoLoad: Bool

    public init(
        productIDs: [String],
        termsURL: URL,
        entitlementIDs: Set<String>? = nil,
        gate: LeeoGatePolicy = .none,
        cacheSuiteName: String? = nil,
        autoLoad: Bool = true
    ) {
        self.productIDs = productIDs
        self.termsURL = termsURL
        self.entitlementIDs = entitlementIDs ?? Set(productIDs)
        self.gate = gate
        self.cacheSuiteName = cacheSuiteName
        self.autoLoad = autoLoad
    }
}

// MARK: - 페이월 구성으로의 파생

public extension LeeoMonetization {
    /// 선언된 모델에서 페이월/스토어 구성을 유도한다. 페이월이 필요 없는 모델은 nil.
    /// 앱이 `LeeoPaywallConfig` 를 직접 만들 일은 없다 — 모델 선언 하나면 충분하다.
    ///
    /// - Parameter legal: 개인정보 처리방침 링크의 출처 (페이월 하단 노출).
    func paywallConfig(legal: LeeoLegalConfig) -> LeeoPaywallConfig? {
        switch self {
        case .free, .paidUpfront:
            return nil

        case .freemium(let c):
            return LeeoPaywallConfig(
                productIDs: c.productIDs,
                entitlementIDs: c.entitlementIDs,
                termsURL: legal.termsURL,
                privacyURL: legal.privacyURL,
                autoLoad: c.autoLoad,
                cacheSuiteName: c.cacheSuiteName,
                gate: c.gate
            )

        case .paidUpfrontSubscription(let c), .freemiumSubscription(let c):
            return LeeoPaywallConfig(
                productIDs: c.productIDs,
                entitlementIDs: c.entitlementIDs,
                termsURL: c.termsURL,          // 구독은 타입이 보장한 약관 URL 을 쓴다
                privacyURL: legal.privacyURL,
                autoLoad: c.autoLoad,
                cacheSuiteName: c.cacheSuiteName,
                gate: c.gate
            )

        case .credits:
            // 소비성은 LeeoConsumableStore 가 담당한다 — 비소모성 페이월 구성이 아니다.
            return nil
        }
    }

    /// 소비성 결제 구성 (크레딧 모델에만 존재).
    var consumableConfig: LeeoConsumableConfig? {
        if case .credits(let c) = self { return c }
        return nil
    }
}
