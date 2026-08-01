//
//  LeeoLegalConfig.swift
//  LeeoKit
//
//  모든 앱이 반드시 갖춰야 하는 법적/지원 링크. "나중에 넣지" 하다가 심사 직전에
//  급하게 만드는 항목들을 계약 필수로 끌어올린다.
//
//  - privacyURL : App Store 등록 필수. 데이터를 안 모아도 방침 페이지는 있어야 한다.
//  - supportURL : App Store 등록 필수. 지원 페이지가 없으면 사용자는 리뷰란에 항의한다.
//  - termsURL   : 구독을 팔면 필수 (그 경우 LeeoSubscriptionConfig 가 별도로 강제한다).
//  - dataDeletionURL : 계정을 만드는 앱이면 필수 (계정 삭제 경로).
//
//  사용 예:
//      static let legal = LeeoLegalConfig(
//          privacyURL: URL(string: "https://ysoup.io/myapp/privacy")!,
//          supportURL: URL(string: "https://ysoup.io/myapp/support")!)
//

import Foundation

public struct LeeoLegalConfig: Sendable {
    /// 개인정보 처리방침 — 모든 앱 필수.
    public let privacyURL: URL

    /// 지원(문의) 페이지 — 모든 앱 필수.
    public let supportURL: URL

    /// 이용약관. 구독 앱이면 `LeeoSubscriptionConfig.termsURL` 이 우선한다.
    public let termsURL: URL?

    /// 계정·데이터 삭제 안내 페이지. 계정을 만드는 앱이면 심사 필수.
    /// 계정 개념이 없는 앱은 nil 로 두면 된다 (`createsAccounts` 를 false 로).
    public let dataDeletionURL: URL?

    /// 이 앱이 사용자 계정을 만드는가. true 인데 `dataDeletionURL` 이 없으면 Preflight 가 오류로 잡는다.
    public let createsAccounts: Bool

    /// 마케팅/소개 랜딩 페이지 (선택). 탐색기의 "지원·랜딩 페이지" 항목에 쓰인다.
    public let marketingURL: URL?

    public init(
        privacyURL: URL,
        supportURL: URL,
        termsURL: URL? = nil,
        dataDeletionURL: URL? = nil,
        createsAccounts: Bool = false,
        marketingURL: URL? = nil
    ) {
        self.privacyURL = privacyURL
        self.supportURL = supportURL
        self.termsURL = termsURL
        self.dataDeletionURL = dataDeletionURL
        self.createsAccounts = createsAccounts
        self.marketingURL = marketingURL
    }

    /// 설정 화면 등에 노출할 링크 목록 (제목, URL).
    public var displayLinks: [(title: String, url: URL)] {
        var out: [(String, URL)] = [
            (L("개인정보 처리방침", comment: "Legal link: privacy policy"), privacyURL),
            (L("지원 페이지", comment: "Legal link: support"), supportURL),
        ]
        if let termsURL { out.append((L("이용약관", comment: "Legal link: terms"), termsURL)) }
        if let dataDeletionURL {
            out.append((L("계정·데이터 삭제", comment: "Legal link: data deletion"), dataDeletionURL))
        }
        return out
    }
}
