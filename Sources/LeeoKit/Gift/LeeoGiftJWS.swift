//
//  LeeoGiftJWS.swift
//  LeeoKit
//
//  App Store 가 서명한 결제(JWS)를 **다른 기기에서** 확인한다.
//
//  StoreKit 은 자기 기기의 결제만 확인해 준다(VerificationResult). 선물을 받는 사람의 기기는
//  보낸 사람의 결제를 직접 확인해야 하므로, Apple 의 App Store Server Library 가 하는 일을 그대로 한다:
//
//   1. 헤더가 ES256 이고 인증서 사슬(x5c)을 싣고 있다
//   2. 맨 앞 인증서(leaf)의 공개키로 서명이 맞는다
//   3. 사슬이 Apple Root CA - G3 에 닿는다 (이 파일에 박아 둔 인증서만 믿는다)
//   4. leaf 는 App Store 영수증 서명용(OID 1.2.840.113635.100.6.11.1),
//      그 위는 Apple WWDR 중간 인증서(OID 1.2.840.113635.100.6.2.1)다.
//      ⚠️ 4가 없으면 Apple 이 개발자에게 내준 인증서로도 가짜 결제를 서명할 수 있다.
//

import Foundation
import Security
import CryptoKit

/// 확인을 마친 결제에서 선물에 필요한 것만.
struct LeeoSignedGiftTransaction: Equatable, Sendable {
    let transactionID: String
    let originalTransactionID: String
    let bundleID: String
    let productID: String
    let type: String
    /// "Production" · "Sandbox" · "Xcode"
    let environment: String
    let signedDate: Date?
    let revocationDate: Date?
    /// 구독의 끝(평생 상품은 nil). 언제나 패스 연 구독이 아직 살아 있는지 볼 때 쓴다.
    var expiresDate: Date? = nil
}

enum LeeoGiftJWS {
    enum Failure: Error, Equatable {
        case malformed
        case unsupportedAlgorithm
        case badSignature
        case untrustedChain
        case notStoreKitCertificate
    }

    // MARK: - 확인

    /// 서명과 인증서 사슬을 확인하고 결제 내용을 꺼낸다.
    /// - Parameter anchors: 믿을 루트. 시험에서만 바꾼다.
    static func verify(_ jws: String, anchors: [SecCertificate]? = nil) throws -> LeeoSignedGiftTransaction {
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = base64URLDecode(parts[0]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let signature = base64URLDecode(parts[2])
        else { throw Failure.malformed }

        guard header["alg"] as? String == "ES256" else { throw Failure.unsupportedAlgorithm }
        guard let x5c = header["x5c"] as? [String], x5c.count >= 2 else { throw Failure.malformed }
        let ders = x5c.compactMap { Data(base64Encoded: $0) }
        let certs = ders.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard certs.count == x5c.count else { throw Failure.malformed }

        // 2. 서명
        guard let key = SecCertificateCopyKey(certs[0]),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let publicKey = try? P256.Signing.PublicKey(x963Representation: raw),
              let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
        else { throw Failure.badSignature }
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        guard publicKey.isValidSignature(ecdsa, for: signingInput) else { throw Failure.badSignature }

        // 서명이 맞았으니 내용을 믿고 읽는다 (사슬 확인에 서명 시각이 필요하다).
        let tx = try decodePayload(parts[1])

        // 4. 인증서의 쓰임새 표시
        guard ders[0].containsBytes(leafMarker), ders[1].containsBytes(intermediateMarker) else {
            throw Failure.notStoreKitCertificate
        }

        // 3. 사슬
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certs as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else { throw Failure.untrustedChain }
        SecTrustSetAnchorCertificates(trust, (anchors ?? [appleRootCAG3]) as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetNetworkFetchAllowed(trust, false)
        // 결제를 서명한 그때 인증서가 유효했는가를 본다 (leaf 가 나중에 만료돼도 지난 결제는 진짜다).
        SecTrustSetVerifyDate(trust, (tx.signedDate ?? Date()) as CFDate)
        guard SecTrustEvaluateWithError(trust, nil) else { throw Failure.untrustedChain }
        // 사슬의 맨 앞이 서명한 그 인증서인지
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let first = chain.first,
              SecCertificateCopyData(first) as Data == ders[0]
        else { throw Failure.untrustedChain }

        return tx
    }

    /// 서명을 보지 않고 내용만 읽는다. Xcode StoreKit 시험 결제는 기기 안의 인증서로 서명돼 사슬이 없다.
    /// ⚠️ DEBUG 빌드의 Xcode 환경에서만 부른다(`LeeoGiftStore`).
    static func decodeUnverified(_ jws: String) throws -> LeeoSignedGiftTransaction {
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { throw Failure.malformed }
        return try decodePayload(parts[1])
    }

    static func decodePayload(_ part: String) throws -> LeeoSignedGiftTransaction {
        guard let data = base64URLDecode(part),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.malformed }

        func string(_ key: String) -> String? {
            if let s = json[key] as? String { return s }
            if let n = json[key] as? NSNumber { return n.stringValue }
            return nil
        }
        func date(_ key: String) -> Date? {
            (json[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
        guard let id = string("transactionId"),
              let bundle = string("bundleId"),
              let product = string("productId")
        else { throw Failure.malformed }

        return LeeoSignedGiftTransaction(
            transactionID: id,
            originalTransactionID: string("originalTransactionId") ?? id,
            bundleID: bundle,
            productID: product,
            type: string("type") ?? "",
            environment: string("environment") ?? "",
            signedDate: date("signedDate"),
            revocationDate: date("revocationDate"),
            expiresDate: date("expiresDate"))
    }

    // MARK: - 내부

    static func base64URLDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }

    /// DER 로 적힌 OID 1.2.840.113635.100.6.11.1 (App Store 영수증 서명)
    static let leafMarker: [UInt8] = [0x06, 0x0A, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x63, 0x64, 0x06, 0x0B, 0x01]
    /// DER 로 적힌 OID 1.2.840.113635.100.6.2.1 (Apple WWDR 중간 인증서)
    static let intermediateMarker: [UInt8] = [0x06, 0x0A, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x63, 0x64, 0x06, 0x02, 0x01]

    /// Apple Root CA - G3. https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
    /// SHA-256 63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179, 2039-04-30 까지.
    static let appleRootCAG3: SecCertificate = {
        let b64 = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA=="
        // 박아 둔 상수라 실패할 수 없다. 실패하면 시험(`LeeoGiftJWSTests`)이 먼저 잡는다.
        return SecCertificateCreateWithData(nil, Data(base64Encoded: b64)! as CFData)!
    }()
}

private extension Data {
    func containsBytes(_ needle: [UInt8]) -> Bool {
        range(of: Data(needle)) != nil
    }
}
