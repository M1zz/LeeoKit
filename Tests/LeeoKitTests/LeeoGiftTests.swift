//
//  LeeoGiftTests.swift
//  LeeoKitTests
//
//  선물하기: 코드 · 서명 확인 · 이 앱의 선물인지 · 구성 점검.
//
//  서명 시험은 Apple 과 같은 모양의 **가짜 사슬**(시험용 루트 → 중간 → 영수증 서명)을 쓴다.
//  진짜 Apple 루트를 믿는 기본 경로에서는 이 사슬이 거절되어야 하고, 시험 루트를 믿게 하면 통과해야 한다.
//  인증서는 2046년까지 유효하다 (openssl 로 만든 것, 개인키는 이 시험 밖에서 쓰이지 않는다).
//

import XCTest
import CryptoKit
import Security
@testable import LeeoKit

final class LeeoGiftCodeTests: XCTestCase {
    func test_만든_코드는_8자리이고_헷갈리는_글자가_없다() {
        for _ in 0..<200 {
            let code = LeeoGiftCode.generate()
            XCTAssertEqual(code.count, 8)
            XCTAssertNil(code.first { "ILOU".contains($0) })
            XCTAssertEqual(LeeoGiftCode.normalize(code), code)
        }
    }

    func test_사람이_잘못_친_글자도_알아듣는다() {
        XCTAssertEqual(LeeoGiftCode.extract(from: "abcd-efgh"), "ABCDEFGH")
        XCTAssertEqual(LeeoGiftCode.extract(from: " AB CD EF GH "), "ABCDEFGH")
        XCTAssertEqual(LeeoGiftCode.extract(from: "o1l2-i3o4"), "0112-1304".replacingOccurrences(of: "-", with: ""))
        XCTAssertNil(LeeoGiftCode.extract(from: "ABCDEFG"))      // 7자리
        XCTAssertNil(LeeoGiftCode.extract(from: "ABCDEFGU"))     // U 는 없는 글자
    }

    func test_받은_메시지를_통째로_넣어도_코드를_찾는다() {
        let message = LeeoGiftText.shareMessage(appName: "ClipKeyboard", code: "7KQ2M9XA", appStoreID: "1543660502")
        XCTAssertEqual(LeeoGiftCode.extract(from: message), "7KQ2M9XA")
        XCTAssertTrue(message.contains("7KQ2-M9XA"))
        XCTAssertTrue(message.hasSuffix("https://apps.apple.com/app/id1543660502"))
    }

    /// 여덟 칸에 치는 글. 줄표는 칠 필요가 없고, 쳐도 버린다.
    func test_칸에_치는_글은_코드_글자만_8자까지_남는다() {
        XCTAssertEqual(LeeoGiftCode.typed("abcd-ef"), "ABCDEF")
        XCTAssertEqual(LeeoGiftCode.typed("ABCD-EFGH"), "ABCDEFGH")
        XCTAssertEqual(LeeoGiftCode.typed("ABCDEFGHJK"), "ABCDEFGH")
        XCTAssertEqual(LeeoGiftCode.typed("o1l2 u"), "0112")       // U 는 없는 글자라 버린다
        XCTAssertEqual(LeeoGiftCode.typed(""), "")
    }

    func test_칸에_메시지를_통째로_붙여넣어도_코드만_들어간다() {
        let message = LeeoGiftText.shareMessage(appName: "ClipKeyboard", code: "7KQ2M9XA", appStoreID: "1543660502")
        XCTAssertEqual(LeeoGiftCode.typed(message), "7KQ2M9XA")
    }

    /// 시험 선물 표시는 진짜 선물의 서명된 결제와 겹치지 않는다(서명된 결제는 점 두 개로 나뉜 JWS 다).
    func test_시험_선물_표시는_진짜_결제와_겹치지_않는다() {
        XCTAssertFalse(LeeoGiftStore.testGiftMarker.contains("."))
        XCTAssertFalse(LeeoGiftStore.testTransactionPrefix.allSatisfy(\.isNumber))
    }
}

final class LeeoGiftJWSTests: XCTestCase {
    // MARK: 시험용 사슬

    static let rootDER = "MIIBbDCCARKgAwIBAgIUXLMY4Hr3qMUcJjA8CP3VhxpmGqkwCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJVGVzdCBSb290MB4XDTI2MTAxNjA4NDUzMFoXDTQ2MTAxMTA4NDUzMFowFDESMBAGA1UEAwwJVGVzdCBSb290MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE6EZ+w06TsSUYxKblKNXoI1yOSjEMN2kyxt6TGpwpWkjlEqB7hz1JFrieLpU2hU1M1hN1fybRwle9h6grmIOjEaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFJLjQsLQNdUlrAsiQZvf7XV3j427MAoGCCqGSM49BAMCA0gAMEUCIQCLx0w72loE+jJE7ByprL5VJOr7iDHbxynhFnT64Xa2hgIgKhwmA/pnTSgta6aRYtFYGnlT86sLiYeyjgbkapnkfYQ="
    static let interDER = "MIIBojCCAUigAwIBAgIUeG88lbEyyYEfXIxd0JNtlLmLL70wCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJVGVzdCBSb290MB4XDTI2MTAxNjA4NDUzMFoXDTQ2MTAxMTA4NDUzMFowFDESMBAGA1UEAwwJVGVzdCBXV0RSMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE6BjqPhyk8bz/G69Plstm2HjPfOqg+wp3Cg1WSnPfpRM71lN0vMoFOfIItYewmuNWXh2DU527hufgPn4gPj+2nqN4MHYwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFNLqfjzpn6kxgbXsLP2ryHl+2C4LMB8GA1UdIwQYMBaAFJLjQsLQNdUlrAsiQZvf7XV3j427MBAGCiqGSIb3Y2QGAgEEAgUAMAoGCCqGSM49BAMCA0gAMEUCIEpbfgwV3Wh+OdkP/fURVNk7/042aknJaa7p3/WnAbc2AiEA4ZwypU3AvRz2FSvtNdPw3Fi6+Ppuvlh+5KDnJLxVBgQ="
    static let leafDER = "MIIBpzCCAU2gAwIBAgIUJOnjn+E9RLLqMs3Z2UwWO1t+QB0wCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJVGVzdCBXV0RSMB4XDTI2MTAxNjA4NDUzMFoXDTQ2MTAxMTA4NDUzMFowHzEdMBsGA1UEAwwUVGVzdCBSZWNlaXB0IFNpZ25pbmcwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARF/VillGxfswBa0M4LrVze56oJ6Gu1xfOWgCMTRoTAVQ45XYo8eIeSxAlt/Tp9Ti/wb6xEwFU+9pBsAdlLuDBto3IwcDAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUA/iGG/egOFnFASmhw1r+zFLSYUcwHwYDVR0jBBgwFoAU0up+POmfqTGBtews/avIeX7YLgswEAYKKoZIhvdjZAYLAQQCBQAwCgYIKoZIzj0EAwIDSAAwRQIgGuYxkqsamgO4VZb0M20TA/bP8U2qT/jdon4yPeWqWSYCIQDHnqQWG+2/ZrS2q/Xtg/RyKsLitiuvfb0qtM5SNuogcw=="
    /// 같은 키지만 "영수증 서명" 표시(OID)가 없는 leaf. 개발자 인증서 흉내.
    static let plainLeafDER = "MIIBljCCATugAwIBAgIUJOnjn+E9RLLqMs3Z2UwWO1t+QB4wCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJVGVzdCBXV0RSMB4XDTI2MTAxNjA4NDUzMFoXDTQ2MTAxMTA4NDUzMFowHzEdMBsGA1UEAwwUVGVzdCBSZWNlaXB0IFNpZ25pbmcwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARF/VillGxfswBa0M4LrVze56oJ6Gu1xfOWgCMTRoTAVQ45XYo8eIeSxAlt/Tp9Ti/wb6xEwFU+9pBsAdlLuDBto2AwXjAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUA/iGG/egOFnFASmhw1r+zFLSYUcwHwYDVR0jBBgwFoAU0up+POmfqTGBtews/avIeX7YLgswCgYIKoZIzj0EAwIDSQAwRgIhAP0C6JWgORKCllxbBX9WMTpEv+ccQ+lOYi8ThWr9iMjbAiEA/VHylK40RywFysxm5185ovjszyVzlrUxCJCLATMbAnM="
    static let leafKeyPEM = """
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg5cMn5hruZ9lsNItl
XeaDi75/4BFH7/8YIMZ/eLEYS8+hRANCAARF/VillGxfswBa0M4LrVze56oJ6Gu1
xfOWgCMTRoTAVQ45XYo8eIeSxAlt/Tp9Ti/wb6xEwFU+9pBsAdlLuDBt
-----END PRIVATE KEY-----
"""

    private func cert(_ b64: String) -> SecCertificate {
        SecCertificateCreateWithData(nil, Data(base64Encoded: b64)! as CFData)!
    }

    private func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func payload(product: String = "com.test.gift",
                         bundle: String = "com.test.app",
                         environment: String = "Production",
                         revoked: Bool = false) -> [String: Any] {
        var p: [String: Any] = [
            "transactionId": "2000000123456789",
            "originalTransactionId": "2000000123456789",
            "bundleId": bundle,
            "productId": product,
            "type": "Consumable",
            "environment": environment,
            "purchaseDate": 1_760_000_000_000,
            "signedDate": Date().timeIntervalSince1970 * 1000,
        ]
        if revoked { p["revocationDate"] = 1_760_000_100_000 }
        return p
    }

    private func sign(_ payload: [String: Any],
                      chain: [String]? = nil,
                      alg: String = "ES256") throws -> String {
        let header: [String: Any] = ["alg": alg, "x5c": chain ?? [Self.leafDER, Self.interDER, Self.rootDER]]
        let h = b64url(try JSONSerialization.data(withJSONObject: header))
        let p = b64url(try JSONSerialization.data(withJSONObject: payload))
        let key = try P256.Signing.PrivateKey(pemRepresentation: Self.leafKeyPEM)
        let sig = try key.signature(for: Data("\(h).\(p)".utf8))
        return "\(h).\(p).\(b64url(sig.rawRepresentation))"
    }

    private var testAnchors: [SecCertificate] { [cert(Self.rootDER)] }

    // MARK: 시험

    func test_Apple_루트_인증서가_제대로_박혀_있다() {
        let der = SecCertificateCopyData(LeeoGiftJWS.appleRootCAG3) as Data
        let digest = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined()
        XCTAssertEqual(digest, "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179")
    }

    func test_믿는_사슬로_서명된_결제는_통과한다() throws {
        let tx = try LeeoGiftJWS.verify(sign(payload()), anchors: testAnchors)
        XCTAssertEqual(tx.transactionID, "2000000123456789")
        XCTAssertEqual(tx.productID, "com.test.gift")
        XCTAssertEqual(tx.bundleID, "com.test.app")
        XCTAssertEqual(tx.type, "Consumable")
        XCTAssertNil(tx.revocationDate)
    }

    func test_Apple_이_아닌_루트로_서명된_결제는_거절한다() throws {
        // 기본 = Apple Root CA G3 만 믿는다
        XCTAssertThrowsError(try LeeoGiftJWS.verify(sign(payload()))) {
            XCTAssertEqual($0 as? LeeoGiftJWS.Failure, .untrustedChain)
        }
    }

    func test_내용을_고친_결제는_거절한다() throws {
        let jws = try sign(payload())
        var parts = jws.split(separator: ".").map(String.init)
        var p = payload()
        p["bundleId"] = "com.other.app"
        parts[1] = b64url(try JSONSerialization.data(withJSONObject: p))
        XCTAssertThrowsError(try LeeoGiftJWS.verify(parts.joined(separator: "."), anchors: testAnchors)) {
            XCTAssertEqual($0 as? LeeoGiftJWS.Failure, .badSignature)
        }
    }

    func test_영수증_서명_표시가_없는_인증서는_거절한다() throws {
        let jws = try sign(payload(), chain: [Self.plainLeafDER, Self.interDER, Self.rootDER])
        XCTAssertThrowsError(try LeeoGiftJWS.verify(jws, anchors: testAnchors)) {
            XCTAssertEqual($0 as? LeeoGiftJWS.Failure, .notStoreKitCertificate)
        }
    }

    func test_ES256_이_아니면_거절한다() throws {
        XCTAssertThrowsError(try LeeoGiftJWS.verify(sign(payload(), alg: "none"), anchors: testAnchors)) {
            XCTAssertEqual($0 as? LeeoGiftJWS.Failure, .unsupportedAlgorithm)
        }
        XCTAssertThrowsError(try LeeoGiftJWS.verify("a.b", anchors: testAnchors))
    }

    // MARK: 이 앱의 선물인가

    func test_다른_앱_다른_상품_다른_환경의_선물은_받지_않는다() throws {
        func check(_ p: [String: Any], env: String = "Production") throws -> LeeoGiftError? {
            let tx = try LeeoGiftJWS.verify(sign(p), anchors: testAnchors)
            return LeeoGiftStore.validate(tx, bundleID: "com.test.app", productID: "com.test.gift", environment: env)
        }
        XCTAssertNil(try check(payload()))
        XCTAssertEqual(try check(payload(product: "com.test.pro")), .invalidGift)
        XCTAssertEqual(try check(payload(bundle: "com.other.app")), .invalidGift)
        // TestFlight 결제는 돈이 들지 않는다. 출시판에서 받으면 안 된다.
        XCTAssertEqual(try check(payload(environment: "Sandbox")), .invalidGift)
        XCTAssertNil(try check(payload(environment: "Sandbox"), env: "Sandbox"))
        XCTAssertEqual(try check(payload(revoked: true)), .refunded)
    }
}

final class LeeoGiftConfigTests: XCTestCase {
    func test_레코드_이름은_기기_사이의_계약이다() {
        let c = LeeoGiftConfig(productID: "com.a.gift", grantsProductID: "com.a.pro", containerIdentifier: "iCloud.com.a")
        XCTAssertEqual(c.giftRecordName(code: "ABCDEFGH"), "gift-ABCDEFGH")
        XCTAssertEqual(c.redemptionRecordName(bundleID: "com.a", transactionID: "42"), "giftredeem-com.a-42")
        XCTAssertEqual(c.claimsRecordName(bundleID: "com.a"), "giftclaims-com.a")
    }

    func test_선물은_권한_목록으로_흘러간다() {
        let gift = LeeoGiftConfig(productID: "com.a.gift", grantsProductID: "com.a.pro", containerIdentifier: "iCloud.com.a")
        let money = LeeoMonetization.freemium(LeeoPurchaseConfig(productIDs: ["com.a.pro"], gift: gift))
        let legal = LeeoLegalConfig(privacyURL: URL(string: "https://a.com/p")!, supportURL: URL(string: "https://a.com/s")!)
        XCTAssertEqual(money.paywallConfig(legal: legal)?.gift?.productID, "com.a.gift")
    }

    @MainActor
    func test_받은_선물이_없으면_아무것도_열지_않는다() {
        let suite = "leeo.test.gift.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LeeoGiftStore(
            config: LeeoGiftConfig(productID: "com.a.gift", grantsProductID: "com.a.pro", containerIdentifier: "iCloud.com.a"),
            defaults: defaults, bundleID: "com.a")
        XCTAssertTrue(store.grantedProductIDs.isEmpty)
        XCTAssertTrue(store.sentGifts.isEmpty)
        XCTAssertEqual(store.pendingCount, 0)
    }

    @MainActor
    func test_받아_둔_선물은_다시_켜도_Pro_를_연다() throws {
        let suite = "leeo.test.gift.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = LeeoRedeemedGift(code: "ABCDEFGH", transactionID: "42", redeemedAt: Date())
        defaults.set(try JSONEncoder().encode(saved), forKey: "leeo.gift.redeemed.com.a.gift")
        let store = LeeoGiftStore(
            config: LeeoGiftConfig(productID: "com.a.gift", grantsProductID: "com.a.pro", containerIdentifier: "iCloud.com.a"),
            defaults: defaults, bundleID: "com.a")
        XCTAssertEqual(store.grantedProductIDs, ["com.a.pro"])
    }
}

@MainActor
final class LeeoGiftSupportTests: XCTestCase {
    func test_문의에는_결제_번호와_코드가_붙고_서명_원문은_붙지_않는다() throws {
        let suite = "leeo.test.giftsupport.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = LeeoGiftConfig(productID: "com.a.gift", grantsProductID: "com.a.pro", containerIdentifier: "iCloud.com.a")

        let empty = LeeoGiftStore(config: config, defaults: defaults)
        XCTAssertEqual(empty.supportLines, ["gift.none"])
        XCTAssertFalse(empty.needsSupport)

        let sent = LeeoSentGift(code: "7KQ2M9XA", transactionID: "2000000123", createdAt: Date(), isRedeemed: false)
        defaults.set(try JSONEncoder().encode([sent]), forKey: "leeo.gift.sent.com.a.gift")
        let store = LeeoGiftStore(config: config, defaults: defaults)
        let lines = store.supportLines.joined(separator: "\n")
        XCTAssertTrue(lines.contains("7KQ2-M9XA"))
        XCTAssertTrue(lines.contains("tx=2000000123"))
        XCTAssertTrue(lines.contains("redeemed=no"))
        XCTAssertFalse(lines.contains("jws"))
    }
}
