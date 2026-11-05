//
//  LeeoOfferCodePoolTests.swift
//  LeeoKitTests
//
//  오퍼 코드 묶음 규칙.
//
//  잠그는 계약:
//  1. 기록 이름 — 허브와 앱이 같은 이름을 써야 한 장을 한 결제만 갖는다.
//  2. 이미 가져간 장은 고르지 않는다.
//  3. 사용 링크에 코드 · 앱 ID 가 들어간다.
//  4. App Store Connect 코드 파일에서 코드만 고른다(머리줄 · 날짜 · 겹친 것 버림).
//  5. 예전 선물 기록(isOfferCode 없음)도 그대로 읽힌다.
//

import XCTest
@testable import LeeoKit

final class LeeoOfferCodePoolTests: XCTestCase {

    private let config = LeeoGiftConfig(productID: "com.x.gift", grantsProductID: "com.x.pro",
                                        containerIdentifier: "iCloud.com.x", sellsGifts: true)

    func testRecordNamesAreTheContract() {
        XCTAssertEqual(config.offerClaimRecordName(poolRecordName: "offercode-com.x-1"), "offerclaim-offercode-com.x-1")
        XCTAssertEqual(config.offerIssueRecordName(bundleID: "com.x", transactionID: "42"), "offerissue-com.x-42")
        XCTAssertEqual(config.offerCodeRecordType, "LeeoOfferCode")
        XCTAssertEqual(LeeoOfferCodePool.targetSize, 100)
    }

    func testClaimedCodesAreSkipped() {
        let names = ["offercode-a-1", "offercode-a-2", "offercode-a-3"]
        let claimed: Set<String> = ["offerclaim-offercode-a-2"]
        let left = LeeoOfferCodePool.candidates(names, claimedClaimNames: claimed,
                                                claimName: config.offerClaimRecordName(poolRecordName:))
        XCTAssertEqual(left, ["offercode-a-1", "offercode-a-3"])
    }

    func testRedeemLinkCarriesCodeAndAppID() throws {
        let url = try XCTUnwrap(LeeoOfferCodePool.redeemURL(code: "7K2QX9MPLA", appStoreID: "123456"))
        XCTAssertEqual(url.absoluteString, "https://apps.apple.com/redeem?ctx=offercodes&id=123456&code=7K2QX9MPLA")
        let noID = try XCTUnwrap(LeeoOfferCodePool.redeemURL(code: "7K2QX9MPLA", appStoreID: nil))
        XCTAssertEqual(noID.absoluteString, "https://apps.apple.com/redeem?code=7K2QX9MPLA")
    }

    func testParsesCodesFromAppStoreConnectFile() {
        let csv = """
        Code,Expiration Date,Product
        7K2QX9MPLA,2027-01-31,com.x.pro
        "AB12CD34EF",2027-01-31,com.x.pro
        7k2qx9mpla,2027-01-31,com.x.pro

        Active
        """
        XCTAssertEqual(LeeoOfferCodePool.parseCodes(csv), ["7K2QX9MPLA", "AB12CD34EF"])
    }

    func testOldSentGiftsStillDecode() throws {
        let old = #"{"code":"ABCDEFGH","transactionID":"1","createdAt":0,"isRedeemed":false}"#
        let gift = try JSONDecoder().decode(LeeoSentGift.self, from: Data(old.utf8))
        XCTAssertNil(gift.isOfferCode)
        XCTAssertEqual(LeeoGiftText.displayCode(gift), "ABCD-EFGH")
    }

    func testOfferCodeShareMessageUsesLink() {
        let gift = LeeoSentGift(code: "7K2QX9MPLA", transactionID: "1", createdAt: Date(),
                                isRedeemed: false, isOfferCode: true)
        let message = LeeoGiftText.shareMessage(appName: "골드위크", gift: gift, appStoreID: "123456")
        XCTAssertTrue(message.contains("https://apps.apple.com/redeem?ctx=offercodes&id=123456&code=7K2QX9MPLA"))
        XCTAssertEqual(LeeoGiftText.displayCode(gift), "7K2QX9MPLA")
    }

    func testSellingIsOffByDefault() {
        let closed = LeeoGiftConfig(productID: "a", grantsProductID: "b", containerIdentifier: "c")
        XCTAssertFalse(closed.sellsGifts)
    }
}
