//
//  LeeoGiftConfig.swift
//  LeeoKit
//
//  Pro 를 **다른 사람에게 선물**하는 기능의 구성. 서버 없이 CloudKit 공개 DB 만으로 동작한다.
//
//  왜 이런 모양인가:
//   · App Store 의 "선물하기"는 유료 앱에만 있고 인앱 구매는 대상이 아니다. 한국에는 기프트 카드도 없다.
//   · 비소모성 Pro 는 산 사람의 Apple 계정에 묶여 넘길 수 없다.
//   · 그래서 보내는 사람이 **소모성 선물 상품**을 사고, 앱이 선물 코드를 만들어 공개 DB 에 올린다.
//     받는 사람이 코드를 넣으면 그 사람에게 `grantsProductID` 를 산 것과 같은 권한이 생긴다.
//     (심사 지침 3.1.1: 인앱 구매 항목을 선물할 수 있다. 환불은 산 사람에게만 된다.)
//
//  서버가 하던 일을 무엇이 대신하나:
//   · 결제가 진짜인가     → 선물 기록에 Apple 이 서명한 결제(JWS)를 싣고, 받는 앱이 Apple 루트 인증서로 확인한다
//   · 한 번만 쓰게        → 사용 기록의 이름을 결제 번호로 정한다. CloudKit 은 같은 이름을 두 번 못 만든다
//   · 다른 기기에서도      → 사용 기록은 받은 사람의 iCloud 계정이 만든 것이다. 비공개 DB 에 결제 번호를 적어 두고 다시 확인한다
//
//  ⚠️ CloudKit Dashboard (컨테이너마다 한 번):
//   · 개발 환경에서 한 번 주고받으면 레코드 타입 세 개가 생긴다
//     (`LeeoGift` · `LeeoGiftRedemption` 공개 DB, `LeeoGiftClaims` 비공개 DB)
//   · Security Roles: 공개 DB 기본값(World read · Authenticated create · Creator write) 그대로 둔다
//   · **스키마를 Production 으로 배포한다.** 배포 전에는 출시 빌드에서 코드를 만들지 못한다.
//     그래도 돈은 사라지지 않는다: 코드를 만들기 전에는 결제를 끝내지(finish) 않으므로, 배포 뒤 다시 열면 만들어진다.
//   · 쿼리 인덱스는 필요 없다. 모든 조회가 레코드 이름으로 바로 간다.
//
//  사용 예 (계약에서 한 줄):
//      LeeoPurchaseConfig(
//          productIDs: ["com.Ysoup.MyApp.pro"],
//          gift: LeeoGiftConfig(productID: "com.Ysoup.MyApp.gift.pro",
//                               grantsProductID: "com.Ysoup.MyApp.pro",
//                               containerIdentifier: "iCloud.com.Ysoup.FeedbackHub"))
//

import Foundation

public struct LeeoGiftConfig: Sendable {
    /// 선물로 파는 **소모성** 상품 ID. 몇 번이고 살 수 있어야 하므로 소모성이다.
    /// ⚠️ `productIDs` · `entitlementIDs` 에 넣지 않는다. 넣으면 선물을 산 사람 자신이 Pro 가 된다.
    public let productID: String

    /// 선물을 받은 사람이 "산 것으로 치는" 상품 ID. 보통 평생 Pro 상품.
    /// ⚠️ `entitlementIDs` 안에 있어야 한다. 없으면 받은 사람에게 아무것도 안 열린다(Preflight 가 잡는다).
    public let grantsProductID: String

    /// 선물 기록을 둘 CloudKit 컨테이너. 앱의 entitlements 에 있어야 한다.
    /// 여러 앱이 한 컨테이너(예: FeedbackHub)를 써도 된다. 기록이 번들 ID 로 갈린다.
    public let containerIdentifier: String

    /// 공개 DB 의 선물 기록 타입. 레코드 이름 = `gift-<코드>`.
    public let giftRecordType: String
    /// 공개 DB 의 사용 기록 타입. 레코드 이름 = `giftredeem-<번들 ID>-<결제 번호>`.
    public let redemptionRecordType: String
    /// 받은 사람 비공개 DB 의 "받은 선물 목록" 타입. 다른 기기에서 다시 찾는 데 쓴다.
    public let claimsRecordType: String

    public init(
        productID: String,
        grantsProductID: String,
        containerIdentifier: String,
        giftRecordType: String = "LeeoGift",
        redemptionRecordType: String = "LeeoGiftRedemption",
        claimsRecordType: String = "LeeoGiftClaims"
    ) {
        self.productID = productID
        self.grantsProductID = grantsProductID
        self.containerIdentifier = containerIdentifier
        self.giftRecordType = giftRecordType
        self.redemptionRecordType = redemptionRecordType
        self.claimsRecordType = claimsRecordType
    }

    // MARK: - 레코드 이름 (기기와 기기 사이의 계약 - 바꾸지 않는다)

    func giftRecordName(code: String) -> String { "gift-\(code)" }

    /// 결제 하나에 사용 기록 하나. 번들 ID 를 넣어 한 컨테이너를 여러 앱이 써도 겹치지 않게 한다.
    func redemptionRecordName(bundleID: String, transactionID: String) -> String {
        "giftredeem-\(bundleID)-\(transactionID)"
    }

    /// 비공개 DB 에서 앱마다 하나.
    func claimsRecordName(bundleID: String) -> String { "giftclaims-\(bundleID)" }
}
