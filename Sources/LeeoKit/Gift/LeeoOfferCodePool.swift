//
//  LeeoOfferCodePool.swift
//  LeeoKit
//
//  App Store 오퍼 코드 묶음의 규칙 — 서버 없이 공개 DB 로 한 장씩 나눠 준다.
//
//  왜 이 모양인가:
//   · 선물을 사면 받는 사람에게 갈 **App Store 오퍼 코드**가 한 장 있어야 한다. Pro 를 여는 것은 App Store 라
//     심사 3.1.1 에 걸리지 않는다. 코드는 App Store Connect 에서 만들고, 앱이 만들 수는 없다.
//   · 그래서 개발자가 FeedbackHub 에서 앱마다 **100장**을 공개 DB 에 올려 두고, 산 사람의 앱이 한 장 가져간다.
//   · 공개 DB 라 앱을 뜯는 사람은 묶음을 읽을 수 있다. 작게 두고 채우는 까닭이다 — 뚫려도 100장.
//
//  기록 (기기 사이 · 허브와의 계약 — 이름을 바꾸지 않는다):
//   · `offercode-<번들>-<UUID>`          (LeeoOfferCode)       bundleId · code               허브가 만들고 지운다
//   · `offerclaim-<묶음 레코드 이름>`     (LeeoOfferCodeClaim)  transactionId · bundleId      가져간 결제
//   · `offerissue-<번들>-<결제 번호>`      (LeeoOfferCodeClaim)  code · transactionId · bundleId · poolRecord
//
//  ⚠️ CloudKit Dashboard (컨테이너마다 한 번): 개발 환경에서 한 번 채우고 한 번 사면 두 타입이 생긴다.
//     `LeeoOfferCode.bundleId` 를 **Queryable** 로, 그다음 스키마를 Production 으로 배포한다.
//     Security Roles 는 기본값(World read · Authenticated create · Creator write) 그대로.
//

import Foundation

public enum LeeoOfferCodePool {

    /// 앱마다 채워 두는 장 수. FeedbackHub 가 이만큼까지 채운다.
    public static let targetSize = 100

    /// 한 번에 묶음에서 읽어 오는 수. 가져간 장이 아직 안 지워져 섞여 있어도 남은 장을 찾게 넉넉히.
    static let fetchLimit = 200

    /// 아직 아무도 안 가져간 묶음 레코드 이름.
    static func candidates(_ poolNames: [String], claimedClaimNames: Set<String>,
                           claimName: (String) -> String) -> [String] {
        poolNames.filter { !claimedClaimNames.contains(claimName($0)) }
    }

    /// 받는 사람이 누르는 App Store 사용 링크. 코드가 채워진 "코드 사용" 창이 뜬다.
    /// 앱 ID 가 없으면 App Store 의 일반 코드 사용 링크로 대신한다.
    public static func redeemURL(code: String, appStoreID: String?) -> URL? {
        var components = URLComponents(string: "https://apps.apple.com/redeem")
        var items: [URLQueryItem] = []
        if let appStoreID, !appStoreID.isEmpty {
            items.append(URLQueryItem(name: "ctx", value: "offercodes"))
            items.append(URLQueryItem(name: "id", value: appStoreID))
        }
        items.append(URLQueryItem(name: "code", value: code))
        components?.queryItems = items
        return components?.url
    }

    /// App Store Connect 에서 내려받은 일회용 코드 파일(CSV · 텍스트)에서 코드만 고른다.
    /// 머리줄 · 빈 줄 · 겹친 것은 버린다. 일회용 코드는 영문과 숫자가 섞여 있다 — 둘 다 있어야 코드로 본다
    /// (날짜 · 상품 ID · "Active" 같은 칸이 섞여 들어오지 않게).
    public static func parseCodes(_ text: String) -> [String] {
        var seen = Set<String>()
        var codes: [String] = []
        for line in text.components(separatedBy: .newlines) {
            for cell in line.components(separatedBy: CharacterSet(charactersIn: ",;\t ")) {
                let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).uppercased()
                guard value.count >= 6, value.count <= 64,
                      value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }),
                      value.contains(where: \.isNumber), value.contains(where: \.isLetter),
                      !["CODE", "CODES", "OFFERCODE"].contains(value),
                      seen.insert(value).inserted else { continue }
                codes.append(value)
            }
        }
        return codes
    }
}
