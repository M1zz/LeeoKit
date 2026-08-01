//
//  LeeoPaywallConfig.swift
//  LeeoKit
//
//  인앱 결제(페이월)의 상품/권한 구성. 앱마다 페이월을 새로 짜지 않도록,
//  판매할 StoreKit 상품 ID와 "프로 권한으로 인정할" ID만 여기 채우면
//  로드·구매·복원·권한 판정은 LeeoStore/LeeoPaywallView 가 대신 처리한다.
//
//  사용 예:
//      enum MyAppSpec: LeeoAppSpec {
//          static let appName = "MyApp"
//          static let developerEmail = "leeo@kakao.com"
//          static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.MyApp")
//          static let paywall = LeeoPaywallConfig(
//              productIDs: ["com.Ysoup.MyApp.pro.monthly", "com.Ysoup.MyApp.pro.yearly"],
//              termsURL: URL(string: "https://ysoup.io/terms"),
//              privacyURL: URL(string: "https://ysoup.io/privacy")
//          )
//      }
//

import Foundation

/// 페이월이 다룰 상품과 "프로 권한" 판정 규칙.
public struct LeeoPaywallConfig: Sendable {
    /// 페이월에서 로드·판매할 StoreKit 상품 ID 목록 (App Store Connect / .storekit 파일과 일치).
    /// 배열 순서가 화면 노출 순서가 된다.
    public let productIDs: [String]

    /// "프로/유료 권한이 있다"고 인정할 상품 ID 집합.
    /// 기본은 `productIDs` 전체 — 별도 평생 상품 등 판매하지 않지만 권한만 인정할 ID가 있으면 여기 추가한다.
    public let entitlementIDs: Set<String>

    /// 이용약관 링크 (페이월 하단). 미지정이면 링크를 숨긴다.
    public let termsURL: URL?

    /// 개인정보처리방침 링크 (페이월 하단). 미지정이면 링크를 숨긴다.
    public let privacyURL: URL?

    /// 첫 진입 시 상품을 자동으로 미리 불러올지 여부.
    public let autoLoad: Bool

    /// 권한 캐시를 저장할 UserDefaults suite (앱 그룹). 지정하면 위젯/확장과 Pro 상태를 공유하고,
    /// 네트워크 응답 전/오프라인에도 마지막으로 확인된 권한으로 즉시 잠금 해제한다.
    /// nil이면 `.standard` 를 쓴다.
    public let cacheSuiteName: String?

    /// 무료 한도·프로 전용 기능 정책 — "언제 페이월을 띄울지"의 선언.
    /// 보통 `LeeoMonetization` 이 채워 넣는다 (`LeeoStore.gate` 로 판정에 쓰인다).
    public let gate: LeeoGatePolicy

    public init(
        productIDs: [String],
        entitlementIDs: Set<String>? = nil,
        termsURL: URL? = nil,
        privacyURL: URL? = nil,
        autoLoad: Bool = true,
        cacheSuiteName: String? = nil,
        gate: LeeoGatePolicy = .none
    ) {
        self.gate = gate
        self.productIDs = productIDs
        self.entitlementIDs = entitlementIDs ?? Set(productIDs)
        self.termsURL = termsURL
        self.privacyURL = privacyURL
        self.autoLoad = autoLoad
        self.cacheSuiteName = cacheSuiteName
    }
}
