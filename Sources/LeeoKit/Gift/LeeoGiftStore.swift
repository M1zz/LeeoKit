//
//  LeeoGiftStore.swift
//  LeeoKit
//
//  선물 주고받기의 엔진. `LeeoStore` 가 `config.gift` 를 보고 하나 만들어 `store.gift` 로 내준다.
//  받은 선물은 `grantedProductIDs` 로 LeeoStore 의 권한에 합쳐지므로, 앱의 Pro 판정은 고칠 것이 없다.
//
//  보내기:  소모성 결제 → 허브가 채운 App Store 오퍼 코드 묶음에서 한 장 가져오기(`offerclaim-` · `offerissue-`)
//           → 그다음에 finish. 못 가져오면 finish 하지 않는다. 다음에 앱을 열 때 `resumePending()` 이 다시 한다.
//  받기:    받는 사람이 App Store 사용 링크(또는 받기 화면의 코드 시트)에서 '사용'. Pro 를 여는 것은 App Store 다.
//  옛 자체 코드(`gift-<코드>`): 예전에 보낸 선물을 받는 길로만 남아 있다. 새로 만들지 않는다.
//
//  시험 선물 (개발자): 결제 없이 공개 DB 에 `gift-<코드>` 를 만들고, 받기도 같은 길(찾기 · 한 번만 쓰기)을 지난다.
//           **Pro 는 열지 않는다.** 출시 빌드의 CloudKit Production 이 제대로 도는지 보는 용도다.
//           (개발자 모드는 누구나 켤 수 있어서, 시험 코드가 Pro 를 열면 그게 곧 공짜 Pro 가 된다)
//
//  ⚠️ 한계 (서버가 없어서):
//   · 보낸 사람이 환불받아도, 이미 받은 사람의 Pro 는 그대로다. 오퍼 코드는 되돌릴 수 없고 누가 썼는지도
//     Apple 이 알려 주지 않는다 — 보낸 사람 기기가 `offerrefund-` 표시만 남기고 허브가 센다.
//   · 두 사람 모두 iCloud 에 로그인해야 한다.
//

import Foundation
import CloudKit
#if canImport(StoreKit)
import StoreKit
#endif

// MARK: - 기록

/// 내가 보낸 선물 하나 (이 기기에만 저장한다).
public struct LeeoSentGift: Codable, Identifiable, Equatable, Sendable {
    public let code: String
    public let transactionID: String
    public let createdAt: Date
    /// 받은 사람이 썼는가. 화면을 열 때 공개 DB 를 보고 갱신한다. 오퍼 코드는 알 길이 없어 늘 false.
    public var isRedeemed: Bool
    /// App Store 오퍼 코드인가(묶음에서 가져온 것). nil 이면 예전 LeeoKit 코드.
    public var isOfferCode: Bool? = nil
    public var id: String { transactionID }
}

/// 내가 받아서 쓰고 있는 선물.
public struct LeeoRedeemedGift: Codable, Equatable, Sendable {
    public let code: String
    public let transactionID: String
    public let redeemedAt: Date

    public init(code: String, transactionID: String, redeemedAt: Date) {
        self.code = code
        self.transactionID = transactionID
        self.redeemedAt = redeemedAt
    }
}

public enum LeeoGiftError: LocalizedError, Equatable {
    case productUnavailable
    case iCloudUnavailable
    case network
    case purchaseFailed
    case purchasePending
    /// 결제는 됐는데 코드를 아직 못 올렸다. 돈은 사라지지 않는다.
    case issuePending
    case invalidCode
    case notFound
    case alreadyUsed
    case alreadyPro
    case invalidGift
    case refunded
    /// 결제는 됐는데 묶음에 남은 오퍼 코드가 없다. 개발자가 채우면 다음에 열 때 나온다.
    case poolEmpty

    public var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return L("선물 상품을 불러오지 못했어요.", comment: "Gift error: product not loaded")
        case .iCloudUnavailable:
            return L("iCloud에 로그인해야 선물을 주고받을 수 있어요.", comment: "Gift error: iCloud signed out")
        case .network:
            return L("연결이 불안정해요. 잠시 후 다시 시도해 주세요.", comment: "Gift error: network")
        case .purchaseFailed:
            return L("결제를 마치지 못했어요. 잠시 후 다시 시도해 주세요.", comment: "Gift error: purchase failed")
        case .purchasePending:
            return L("결제가 승인 대기 중이에요. 승인되면 선물 코드가 만들어져요.", comment: "Gift error: purchase pending approval")
        case .issuePending:
            return L("결제는 됐어요. 연결되면 선물 코드를 만들어 드릴게요.", comment: "Gift error: paid but code not created yet")
        case .invalidCode:
            return L("코드를 다시 확인해 주세요. 영문과 숫자 8자리예요.", comment: "Gift error: code format")
        case .notFound:
            return L("이 코드로 된 선물을 찾지 못했어요.", comment: "Gift error: no such gift")
        case .alreadyUsed:
            return L("이미 다른 분이 받은 선물이에요.", comment: "Gift error: code already redeemed by someone else")
        case .alreadyPro:
            return L("이미 Pro를 쓰고 있어요. 이 코드는 다른 분께 보내 주세요.", comment: "Gift error: recipient already has Pro")
        case .invalidGift:
            return L("이 선물은 확인할 수 없어요. 보낸 분께 문의해 주세요.", comment: "Gift error: signature or product mismatch")
        case .refunded:
            return L("환불된 선물이에요.", comment: "Gift error: gift purchase refunded")
        case .poolEmpty:
            return L("결제는 됐어요. 선물 링크를 준비하고 있어요. 준비되면 이 화면에 나와요.",
                     comment: "Gift error: paid, but no App Store offer code is left in the pool yet")
        }
    }
}

// MARK: - 엔진

@MainActor
public final class LeeoGiftStore: ObservableObject {
    public nonisolated let config: LeeoGiftConfig

    #if canImport(StoreKit)
    /// 선물 상품. App Store Connect 에 없으면 nil 이고, 그동안 선물 화면의 문은 숨긴다(`isAvailable`).
    @Published public private(set) var product: Product?
    #endif
    @Published public private(set) var isWorking = false
    /// 내가 보낸 선물, 최근 것이 앞.
    @Published public private(set) var sentGifts: [LeeoSentGift] = []
    /// 내가 받아서 쓰고 있는 선물.
    @Published public private(set) var redeemed: LeeoRedeemedGift?
    /// 결제는 됐는데 아직 코드를 못 만든 선물 수.
    @Published public private(set) var pendingCount = 0
    @Published public var lastError: LeeoGiftError?

    /// 선물을 팔 수 있는가 — 계약이 열어 뒀고(`LeeoGiftConfig.sellsGifts`) 상품이 App Store 에서 왔는가.
    /// 보내기 화면(`LeeoGiftView`)의 문은 이것을 본다.
    public var isAvailable: Bool {
        #if canImport(StoreKit)
        return config.sellsGifts && product != nil
        #else
        return false
        #endif
    }

    /// App Store 오퍼 코드를 받을 수 있는가 — 받기 화면(`LeeoGiftRedeemView`)의 문은 이것을 본다.
    /// iOS · Catalyst 는 앱 안 시트, macOS 15 부터 앱 안 시트, 그 아래 macOS 는 App Store 링크.
    public var canRedeem: Bool {
        #if canImport(StoreKit) && (os(iOS) || os(macOS))
        return true
        #else
        return false
        #endif
    }

    /// 선물이 여는 상품(`grantsProductID`)을 App Store 에서 정식으로 갖고 있는가 — 오퍼 코드로 받았든 샀든.
    /// 받기 화면이 오퍼 코드를 넣은 뒤 "열렸다" 를 보여 줄 때 쓴다(`checkOwnership`).
    @Published public private(set) var ownsGrantedProduct = false

    /// 받은 선물이 여는 상품 ID. LeeoStore 가 권한에 합친다.
    public var grantedProductIDs: Set<String> { redeemed == nil ? [] : [config.grantsProductID] }

    /// 시험 선물을 끝까지 받은 코드. 받기 화면이 "끝까지 처리됐다" 를 보여 준다. Pro 와는 무관하다.
    @Published public private(set) var testRedeemedCode: String?

    /// 시험 선물을 만들고 받아도 되는가. 앱이 개발자 모드로 채운다. 기본은 막힘.
    public var allowsTestGifts: @MainActor () -> Bool = { false }

    /// 이미 권한이 있는가. 있으면 받기를 막고 코드는 다른 사람에게 넘기게 둔다.
    /// LeeoStore 가 "선물 말고 산 것 · 그랜드파더" 로 채운다. 앱에 다른 Pro 경로가 있으면 덮어써도 된다.
    public var alreadyEntitled: @MainActor () -> Bool = { false }

    /// 받은 선물이 생기거나 사라질 때 (LeeoStore 가 권한을 다시 합친다).
    var onChange: (@MainActor () -> Void)?

    private let defaults: UserDefaults
    private let bundleID: String
    private var pendingCodes: [String: String] = [:]   // 결제 번호 → 코드
    /// 문의에 붙일 미완료 선물(`supportLines`).
    var pendingSupportCodes: [String: String] { pendingCodes }

    private var keySent: String { "leeo.gift.sent." + config.productID }
    private var keyRedeemed: String { "leeo.gift.redeemed." + config.productID }
    private var keyPending: String { "leeo.gift.pending." + config.productID }

    /// ⚠️ 컨테이너는 쓸 때 만든다. entitlements 에 없는 컨테이너를 만들면 그 자리에서 죽는다(시험 · 미리보기 포함).
    private var container: CKContainer { CKContainer(identifier: config.containerIdentifier) }
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    public init(config: LeeoGiftConfig,
                defaults: UserDefaults = .standard,
                bundleID: String = Bundle.main.bundleIdentifier ?? "") {
        self.config = config
        self.defaults = defaults
        self.bundleID = bundleID
        sentGifts = decode([LeeoSentGift].self, keySent) ?? []
        redeemed = decode(LeeoRedeemedGift.self, keyRedeemed)
        pendingCodes = defaults.dictionary(forKey: keyPending) as? [String: String] ?? [:]
        pendingCount = pendingCodes.count
    }

    // MARK: - 보내기

    #if canImport(StoreKit)
    public func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [config.productID]).first
    }

    /// 선물을 사고 코드를 만든다. 만든 선물을 돌려준다(취소 · 실패면 nil, 까닭은 `lastError`).
    ///
    /// SwiftUI 에서는 `@Environment(\.purchase)` 를 넘긴다: `gift.purchase { try await purchaseAction($0) }`.
    /// (결제 시트를 띄울 창을 아는 쪽이 사야 아이패드에서 결제가 오류로 끝나지 않는다. `LeeoStore.purchase` 참고)
    @discardableResult
    public func purchase(using action: (Product) async throws -> Product.PurchaseResult) async -> LeeoSentGift? {
        // 선물 판매를 닫은 계약에서는 사지 않는다 — 받는 쪽이 LeeoKit 코드를 넣을 자리가 없다.
        guard config.sellsGifts else { return nil }
        guard !isWorking else { return nil }
        lastError = nil
        if product == nil { await loadProduct() }
        guard let product else { lastError = .productUnavailable; return nil }
        isWorking = true
        defer { isWorking = false }

        // 돈을 받기 전에 iCloud 를 본다. 로그인 안 한 사람은 코드를 올릴 수 없다.
        do { try await requireAccount() } catch { lastError = Self.map(error); return nil }

        let result: Product.PurchaseResult
        do { result = try await action(product) } catch {
            lastError = .purchaseFailed
            return nil
        }
        switch result {
        case .success(let verification):
            guard case .verified(let tx) = verification else { lastError = .invalidGift; return nil }
            return await issue(tx, jws: verification.jwsRepresentation)
        case .pending:
            lastError = .purchasePending
            return nil
        case .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    /// 끝나지 않은 선물 결제를 찾아 코드를 만든다. 앱을 열 때와 선물 화면을 열 때 부른다.
    public func resumePending() async {
        for await result in Transaction.unfinished {
            guard case .verified(let tx) = result, tx.productID == config.productID else { continue }
            if tx.revocationDate != nil {
                await revoke(tx)
            } else {
                _ = await issue(tx, jws: result.jwsRepresentation)
            }
        }
    }

    /// `Transaction.updates` 로 들어온 선물 결제 (승인 대기 뒤 결제, 환불). LeeoStore 리스너가 넘긴다.
    func handle(update result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result else { return }
        if tx.revocationDate != nil {
            await revoke(tx)
        } else {
            _ = await issue(tx, jws: result.jwsRepresentation)
        }
    }

    /// 묶음에서 App Store 오퍼 코드를 한 장 가져오고, 가져온 다음에만 결제를 끝낸다.
    /// 못 가져오면(묶음이 비었거나 연결 문제) 끝내지 않는다 — 다음에 열 때 `resumePending` 이 다시 한다.
    private func issue(_ tx: Transaction, jws: String) async -> LeeoSentGift? {
        let txid = String(tx.id)
        if let done = sentGifts.first(where: { $0.transactionID == txid }) {
            await tx.finish()
            return done
        }
        setPending(txid, pendingCodes[txid] ?? "")
        let code: String
        do {
            code = try await claimOfferCode(transactionID: txid)
        } catch {
            let mapped = Self.map(error)
            // 묶음 타입이 아직 없으면(한 번도 안 채움) CloudKit 은 "없음" 으로 답한다 — 빈 묶음과 같다.
            lastError = (mapped == .poolEmpty || mapped == .notFound) ? .poolEmpty : .issuePending
            print("❌ [LeeoGiftStore.issue] 오퍼 코드를 못 가져왔다 (결제는 끝내지 않음): \(error)")
            return nil
        }

        let gift = LeeoSentGift(code: code, transactionID: txid, createdAt: tx.purchaseDate,
                                isRedeemed: false, isOfferCode: true)
        if !sentGifts.contains(where: { $0.transactionID == txid }) {
            sentGifts.insert(gift, at: 0)
            encode(sentGifts, keySent)
        }
        setPending(txid, nil)
        await tx.finish()
        print("✅ [LeeoGiftStore.issue] 오퍼 코드 한 장 가져옴")
        return gift
    }

    /// 묶음에서 한 장. 같은 결제면 어느 기기에서 다시 불러도 같은 코드다(발급 기록).
    ///
    ///  1. 발급 기록 `offerissue-<번들>-<결제 번호>` 가 있으면 그 코드
    ///  2. 묶음(`LeeoOfferCode`, 이 앱 번들)에서 아직 아무도 안 가져간 것을 골라
    ///     가져감 기록 `offerclaim-<묶음 레코드 이름>` 을 만든다 — 이름이 하나라 한 장은 한 결제만 가진다
    ///  3. 발급 기록을 만든다. 다른 기기가 먼저 만들었으면 그쪽 코드를 쓴다
    private func claimOfferCode(transactionID txid: String) async throws -> String {
        try await requireAccount()
        let issueID = CKRecord.ID(recordName: config.offerIssueRecordName(bundleID: bundleID, transactionID: txid))
        if let existing = try? await publicDB.record(for: issueID), let code = existing["code"] as? String, !code.isEmpty {
            return code
        }

        let query = CKQuery(recordType: config.offerCodeRecordType,
                            predicate: NSPredicate(format: "bundleId == %@", bundleID))
        let (matches, _) = try await publicDB.records(matching: query, resultsLimit: LeeoOfferCodePool.fetchLimit)
        let pool = matches.compactMap { try? $0.1.get() }
        guard !pool.isEmpty else { throw LeeoGiftError.poolEmpty }

        let claimIDs = pool.map { CKRecord.ID(recordName: config.offerClaimRecordName(poolRecordName: $0.recordID.recordName)) }
        let claimResults = try await publicDB.records(for: claimIDs)
        let claimed = Set(claimResults.compactMap { id, result in (try? result.get()) != nil ? id.recordName : nil })
        let candidates = LeeoOfferCodePool.candidates(pool.map(\.recordID.recordName), claimedClaimNames: claimed,
                                                      claimName: config.offerClaimRecordName(poolRecordName:))
        let byName = Dictionary(pool.map { ($0.recordID.recordName, $0) }, uniquingKeysWith: { a, _ in a })

        for name in candidates.shuffled() {
            guard let record = byName[name], let code = record["code"] as? String, !code.isEmpty else { continue }
            let claim = CKRecord(recordType: config.offerClaimRecordType,
                                 recordID: CKRecord.ID(recordName: config.offerClaimRecordName(poolRecordName: name)))
            claim["transactionId"] = txid
            claim["bundleId"] = bundleID
            do {
                try await saveNew(claim, in: publicDB) { $0["transactionId"] as? String == txid }
            } catch LeeoGiftError.alreadyUsed {
                continue   // 다른 결제가 막 가져갔다
            }
            let issue = CKRecord(recordType: config.offerClaimRecordType, recordID: issueID)
            issue["code"] = code
            issue["transactionId"] = txid
            issue["bundleId"] = bundleID
            issue["poolRecord"] = name
            do {
                try await saveNew(issue, in: publicDB) { $0["code"] as? String == code }
            } catch LeeoGiftError.alreadyUsed {
                // 같은 결제를 다른 기기가 먼저 발급했다. 그쪽 코드를 쓴다(방금 가져간 한 장은 버린다).
                if let other = try? await publicDB.record(for: issueID), let otherCode = other["code"] as? String {
                    return otherCode
                }
                throw LeeoGiftError.network
            }
            return code
        }
        throw LeeoGiftError.poolEmpty
    }

    /// 보낸 선물이 환불됐다.
    ///  · 예전 자체 코드: 아직 안 받았으면 선물 기록을 지워 못 쓰게 한다.
    ///  · App Store 오퍼 코드: 이미 나간 코드는 되돌릴 수 없다. 환불 표시만 남겨 허브가 센다.
    ///    (누가 그 코드로 Pro 를 받았는지는 Apple 이 알려 주지 않는다.)
    private func revoke(_ tx: Transaction) async {
        let txid = String(tx.id)
        let sent = sentGifts.first(where: { $0.transactionID == txid })
        let code = sent?.code ?? pendingCodes[txid]
        if let code, sent?.isOfferCode == true {
            await markRefunded(code: code, transactionID: txid)
        } else if let code {
            try? await publicDB.deleteRecord(withID: CKRecord.ID(recordName: config.giftRecordName(code: code)))
        }
        sentGifts.removeAll { $0.transactionID == txid }
        encode(sentGifts, keySent)
        setPending(txid, nil)
        await tx.finish()
        print("🔄 [LeeoGiftStore.revoke] 환불된 선물 정리")
    }

    /// `offerrefund-<번들>-<결제 번호>` — 발급 기록과 같은 타입 · 같은 칸만 쓴다(Production 스키마에 새 칸을 못 더한다).
    private func markRefunded(code: String, transactionID txid: String) async {
        let record = CKRecord(recordType: config.offerClaimRecordType,
                              recordID: CKRecord.ID(recordName: config.offerRefundRecordName(bundleID: bundleID, transactionID: txid)))
        record["code"] = code
        record["transactionId"] = txid
        record["bundleId"] = bundleID
        do {
            try await saveNew(record, in: publicDB) { $0["transactionId"] as? String == txid }
        } catch {
            print("❌ [LeeoGiftStore.markRefunded] \(error)")
        }
    }
    #endif

    // MARK: - 시험 선물 (개발자)

    /// 결제 없이 시험 코드를 만든다. 만든 코드를 돌려준다(막혔거나 실패면 nil, 까닭은 `lastError`).
    ///
    /// ⚠️ 이미 Production 스키마에 있는 칸(`jws` · `transactionId` · `bundleId`)만 쓴다.
    ///    새 칸을 더하면 Production 에서는 저장이 거절된다(스키마는 개발 환경에서만 저절로 자란다).
    @discardableResult
    public func issueTestGift() async -> String? {
        guard allowsTestGifts(), !isWorking else { return nil }
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await requireAccount()
            let txid = Self.testTransactionPrefix + UUID().uuidString
            for attempt in 0..<2 {
                let code = LeeoGiftCode.generate()
                let record = CKRecord(recordType: config.giftRecordType,
                                      recordID: CKRecord.ID(recordName: config.giftRecordName(code: code)))
                record["jws"] = Self.testGiftMarker
                record["transactionId"] = txid
                record["bundleId"] = bundleID
                do {
                    try await saveNew(record, in: publicDB) { $0["transactionId"] as? String == txid }
                    print("🧪 [LeeoGiftStore.issueTestGift] 시험 코드 \(LeeoGiftCode.display(code))")
                    return code
                } catch LeeoGiftError.alreadyUsed where attempt == 0 {
                    continue
                }
            }
            throw LeeoGiftError.alreadyUsed
        } catch {
            print("❌ [LeeoGiftStore.issueTestGift] \(error)")
            lastError = Self.map(error)
            return nil
        }
    }

    /// 시험 결과를 지운다. 받기 화면을 떠날 때 부른다.
    public func clearTestResult() {
        testRedeemedCode = nil
    }

    /// 시험 선물 표시. 진짜 선물의 `jws` 는 서명된 결제라 이 값과 겹칠 수 없다.
    nonisolated static let testGiftMarker = "leeo-test-gift"
    /// 시험 선물의 결제 번호 머리. 진짜 결제 번호는 숫자뿐이라 겹치지 않는다.
    nonisolated static let testTransactionPrefix = "test-"

    /// 시험 선물을 받는다. 사용 기록을 만들어 "한 번만" 을 확인하되 **Pro 는 열지 않는다.**
    private func redeemTest(_ giftRecord: CKRecord, code: String) async throws {
        guard allowsTestGifts() else { throw LeeoGiftError.invalidGift }
        guard giftRecord["bundleId"] as? String == bundleID,
              let txid = giftRecord["transactionId"] as? String,
              txid.hasPrefix(Self.testTransactionPrefix) else { throw LeeoGiftError.invalidGift }
        let me = try await container.userRecordID()
        let redemption = CKRecord(
            recordType: config.redemptionRecordType,
            recordID: CKRecord.ID(recordName: config.redemptionRecordName(bundleID: bundleID, transactionID: txid)))
        redemption["jws"] = Self.testGiftMarker
        redemption["code"] = code
        try await saveNew(redemption, in: publicDB) { Self.isCreated(by: me, $0) }
        testRedeemedCode = code
        print("🧪 [LeeoGiftStore.redeem] 시험 선물을 끝까지 받음 \(LeeoGiftCode.display(code)) (Pro 는 열지 않음)")
    }

    // MARK: - 받기

    /// 코드를 넣어 선물을 받는다. 받은 메시지를 통째로 넣어도 된다. 성공하면 true.
    @discardableResult
    public func redeem(_ input: String) async -> Bool {
        guard !isWorking else { return false }
        lastError = nil
        guard let code = LeeoGiftCode.extract(from: input) else { lastError = .invalidCode; return false }
        testRedeemedCode = nil
        // ⚠️ 시험 선물은 이미 Pro 인 개발자도 받아 봐야 한다. 그래서 시험을 허락한 동안에는
        //    "이미 Pro" 를 선물 기록을 읽은 **뒤에** 본다. 보통 사람은 예전처럼 연결 전에 막는다.
        let testing = allowsTestGifts()
        if !testing, redeemed != nil || alreadyEntitled() { lastError = .alreadyPro; return false }
        isWorking = true
        defer { isWorking = false }

        do {
            try await requireAccount()
            let giftRecord: CKRecord
            do {
                giftRecord = try await publicDB.record(for: CKRecord.ID(recordName: config.giftRecordName(code: code)))
            } catch let error as CKError where error.code == .unknownItem {
                throw LeeoGiftError.notFound
            }
            guard let jws = giftRecord["jws"] as? String else { throw LeeoGiftError.invalidGift }
            if jws == Self.testGiftMarker {
                try await redeemTest(giftRecord, code: code)
                return true
            }
            if testing, redeemed != nil || alreadyEntitled() { throw LeeoGiftError.alreadyPro }
            let tx = try await check(jws)
            let me = try await container.userRecordID()

            // 사용 기록의 이름이 곧 "한 번만" 이다. 같은 이름은 두 번 못 만든다.
            let redemption = CKRecord(
                recordType: config.redemptionRecordType,
                recordID: CKRecord.ID(recordName: config.redemptionRecordName(bundleID: bundleID, transactionID: tx.transactionID)))
            // 서명된 결제를 사용 기록에도 싣는다. 보낸 사람이 선물 기록을 지워도 받은 것은 남는다.
            redemption["jws"] = jws
            redemption["code"] = code
            try await saveNew(redemption, in: publicDB) { Self.isCreated(by: me, $0) }

            await addClaim(tx.transactionID)
            setRedeemed(LeeoRedeemedGift(code: code, transactionID: tx.transactionID, redeemedAt: Date()))
            print("✅ [LeeoGiftStore.redeem] 선물 받음 \(LeeoGiftCode.display(code))")
            return true
        } catch {
            print("❌ [LeeoGiftStore.redeem] \(error)")
            lastError = Self.map(error)
            return false
        }
    }

    // MARK: - 다시 확인

    /// 받은 선물이 아직 유효한지, 다른 기기에서 받은 선물이 있는지, 보낸 선물을 누가 받았는지 본다.
    /// 앱을 열 때 · 구매 복원 때 부른다. 연결이 안 되면 마지막으로 확인한 상태를 그대로 둔다.
    /// `grantsProductID` 를 App Store 에서 갖고 있는지 다시 본다. 오퍼 코드 시트가 닫힌 뒤 부른다.
    /// 시트가 닫히는 때와 거래가 들어오는 때가 어긋날 수 있어, 못 찾으면 잠깐 뒤 한 번 더 본다.
    public func checkOwnership(retry: Bool = false) async {
        #if canImport(StoreKit)
        for attempt in 0..<(retry ? 3 : 1) {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1.5)) }
            var owns = false
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                if transaction.productID == config.grantsProductID, transaction.revocationDate == nil {
                    owns = true
                }
            }
            if owns != ownsGrantedProduct { ownsGrantedProduct = owns }
            if owns { return }
        }
        #endif
    }

    public func refresh() async {
        guard (try? await container.accountStatus()) == .available,
              let me = try? await container.userRecordID() else { return }
        if let current = redeemed {
            await revalidate(current, me: me)
        } else {
            await restoreFromClaims(me: me)
        }
        await refreshSentStatuses()
    }

    private func revalidate(_ gift: LeeoRedeemedGift, me: CKRecord.ID) async {
        let id = CKRecord.ID(recordName: config.redemptionRecordName(bundleID: bundleID, transactionID: gift.transactionID))
        do {
            let record = try await publicDB.record(for: id)
            guard Self.isCreated(by: me, record), let jws = record["jws"] as? String else {
                return setRedeemed(nil)   // 다른 iCloud 계정
            }
            do { _ = try await check(jws) } catch let error as LeeoGiftError where error == .invalidGift || error == .refunded {
                setRedeemed(nil)
            }
        } catch let error as CKError where error.code == .unknownItem {
            setRedeemed(nil)
        } catch {
            // 연결 문제. 마지막으로 확인된 것을 믿는다.
        }
    }

    private func restoreFromClaims(me: CKRecord.ID) async {
        let claimsID = CKRecord.ID(recordName: config.claimsRecordName(bundleID: bundleID))
        guard let claims = try? await privateDB.record(for: claimsID),
              let ids = claims["transactionIds"] as? [String] else { return }
        for txid in ids.reversed() {
            let id = CKRecord.ID(recordName: config.redemptionRecordName(bundleID: bundleID, transactionID: txid))
            guard let record = try? await publicDB.record(for: id),
                  Self.isCreated(by: me, record),
                  let jws = record["jws"] as? String,
                  (try? await check(jws)) != nil else { continue }
            setRedeemed(LeeoRedeemedGift(code: record["code"] as? String ?? "",
                                         transactionID: txid,
                                         redeemedAt: record.creationDate ?? Date()))
            print("✅ [LeeoGiftStore.refresh] 다른 기기에서 받은 선물을 찾음")
            return
        }
    }

    private func refreshSentStatuses() async {
        var changed = false
        for (i, gift) in sentGifts.enumerated() where !gift.isRedeemed && gift.isOfferCode != true {
            let id = CKRecord.ID(recordName: config.redemptionRecordName(bundleID: bundleID, transactionID: gift.transactionID))
            if (try? await publicDB.record(for: id)) != nil {
                sentGifts[i].isRedeemed = true
                changed = true
            }
        }
        if changed { encode(sentGifts, keySent) }
    }

    /// 받은 사람의 비공개 DB 에 결제 번호를 적는다. 실패해도 이 기기에서는 받은 것이 그대로다.
    private func addClaim(_ txid: String) async {
        let id = CKRecord.ID(recordName: config.claimsRecordName(bundleID: bundleID))
        for _ in 0..<2 {
            let record = (try? await privateDB.record(for: id)) ?? CKRecord(recordType: config.claimsRecordType, recordID: id)
            var ids = record["transactionIds"] as? [String] ?? []
            guard !ids.contains(txid) else { return }
            ids.append(txid)
            record["transactionIds"] = ids
            do {
                _ = try await privateDB.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            } catch {
                print("⚠️ [LeeoGiftStore.addClaim] 다른 기기용 기록을 못 남겼다: \(error)")
                return
            }
        }
    }

    // MARK: - 확인 (순수)

    /// 서명을 확인하고 이 앱의 선물인지 본다.
    private func check(_ jws: String) async throws -> LeeoSignedGiftTransaction {
        let environment = await Self.appEnvironment()
        let tx: LeeoSignedGiftTransaction
        do {
            tx = try await Self.decode(jws, environment: environment)
        } catch {
            throw LeeoGiftError.invalidGift
        }
        if let problem = Self.validate(tx, bundleID: bundleID, productID: config.productID, environment: environment) {
            throw problem
        }
        return tx
    }

    nonisolated private static func decode(_ jws: String, environment: String) async throws -> LeeoSignedGiftTransaction {
        #if DEBUG
        // Xcode StoreKit 시험 결제는 Apple 이 서명하지 않는다. 디버그 빌드에서만 내용을 그대로 읽는다.
        if environment == "Xcode" { return try LeeoGiftJWS.decodeUnverified(jws) }
        #endif
        // 인증서 확인은 막힐 수 있는 일이라 메인 스레드 밖에서.
        return try await Task.detached { try LeeoGiftJWS.verify(jws) }.value
    }

    /// 서명이 맞은 결제가 **이 앱 · 이 상품 · 이 환경**의 선물인지.
    /// 환경을 맞추는 까닭: TestFlight(Sandbox) 결제는 돈이 들지 않는다. 그 코드로 출시판 Pro 가 열리면 안 된다.
    nonisolated static func validate(_ tx: LeeoSignedGiftTransaction,
                                     bundleID: String,
                                     productID: String,
                                     environment: String) -> LeeoGiftError? {
        guard tx.bundleID == bundleID, tx.productID == productID, tx.type == "Consumable" else { return .invalidGift }
        guard tx.environment == environment else { return .invalidGift }
        guard tx.revocationDate == nil else { return .refunded }
        return nil
    }

    /// 이 앱이 도는 App Store 환경. "Production" · "Sandbox" · "Xcode".
    private static var cachedEnvironment: String?
    private static func appEnvironment() async -> String {
        if let cachedEnvironment { return cachedEnvironment }
        var value = "Production"
        #if canImport(StoreKit)
        if let result = try? await AppTransaction.shared {
            switch result {
            case .verified(let app), .unverified(let app, _): value = app.environment.rawValue
            }
        }
        #endif
        cachedEnvironment = value
        return value
    }

    nonisolated static func isCreated(by me: CKRecord.ID, _ record: CKRecord) -> Bool {
        guard let creator = record.creatorUserRecordID?.recordName else { return false }
        return creator == CKCurrentUserDefaultName || creator == me.recordName
    }

    // MARK: - 내부

    private func requireAccount() async throws {
        let status: CKAccountStatus
        do { status = try await container.accountStatus() } catch { throw LeeoGiftError.iCloudUnavailable }
        guard status == .available else { throw LeeoGiftError.iCloudUnavailable }
    }

    /// 새 레코드를 만든다. 같은 이름이 이미 있으면 `isOurs` 로 내가 앞서 만든 것인지 본다
    /// (응답을 못 받고 다시 보낸 경우). 아니면 `alreadyUsed`.
    private func saveNew(_ record: CKRecord, in db: CKDatabase, isOurs: (CKRecord) -> Bool) async throws {
        do {
            _ = try await db.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let existing: CKRecord
            if let server = error.serverRecord { existing = server } else { existing = try await db.record(for: record.recordID) }
            guard isOurs(existing) else { throw LeeoGiftError.alreadyUsed }
        } catch let error as CKError where error.code == .permissionFailure {
            // 남이 만든 같은 이름의 기록에 쓰려 하면 공개 DB 는 "충돌" 대신 "권한 없음" 으로 거절하기도 한다.
            // 이미 있으면 그건 "이미 쓴 코드" 다. 없는데 권한이 없다면 진짜 권한 문제다.
            guard let existing = try? await db.record(for: record.recordID) else { throw error }
            guard isOurs(existing) else { throw LeeoGiftError.alreadyUsed }
        }
    }

    nonisolated static func map(_ error: Error) -> LeeoGiftError {
        if let gift = error as? LeeoGiftError { return gift }
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return .iCloudUnavailable
            case .unknownItem:      return .notFound
            default:                return .network
            }
        }
        if error is LeeoGiftJWS.Failure { return .invalidGift }
        return .network
    }

    private func setPending(_ txid: String, _ code: String?) {
        pendingCodes[txid] = code
        defaults.set(pendingCodes, forKey: keyPending)
        pendingCount = pendingCodes.count
    }

    private func setRedeemed(_ gift: LeeoRedeemedGift?) {
        guard gift != redeemed else { return }
        redeemed = gift
        if let gift { encode(gift, keyRedeemed) } else { defaults.removeObject(forKey: keyRedeemed) }
        onChange?()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
