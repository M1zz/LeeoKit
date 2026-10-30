//
//  LeeoTipJar.swift
//  LeeoKit
//
//  **이미 다 가진 사람이 조금 더 내고 싶을 때** 내는 곳(팁). 기능을 열지 않는다.
//
//  - 상품은 소모성(Consumable)이다. 몇 번이든 낼 수 있다.
//  - 낸 것은 이 기기에 횟수로만 남는다(고마움을 말하는 데 쓴다). 권한이 아니므로 복원할 것이 없다.
//  - ⚠️ 팁 상품을 `productIDs` · `entitlementIDs` 에 넣으면 낸 사람이 Pro 가 된다. 사전 점검이 막는다(`tip.sellsPro`).
//
//  계약에서 한 줄:
//      .freemium(LeeoPurchaseConfig(productIDs: [...], tipJar: LeeoTipJarConfig(productIDs: [
//          "com.example.tip.small", "com.example.tip.medium", "com.example.tip.large"])))
//

import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

// MARK: - 구성

public struct LeeoTipJarConfig: Sendable, Equatable {
    /// 팁 상품 ID. **작은 것부터 큰 것 순**(화면도 이 순서다). 소모성 상품이어야 한다.
    public let productIDs: [String]
    /// 앱 소개 페이지의 '고마운 사람들' 자리(예: `https://m1zz.github.io/Rereminder/#leeo-thanks`).
    /// 있으면 한 번이라도 응원한 사람에게 팁 화면에서 '이름 올리기'(개발자에게 메일)와 '보기'를 보여 준다.
    /// 이름은 app-portfolio 의 docs/thanks.json 에 손으로 올린다. 없으면 그 칸을 그리지 않는다.
    public let thanksPage: URL?

    public init(productIDs: [String], thanksPage: URL? = nil) {
        self.productIDs = productIDs
        self.thanksPage = thanksPage
    }
}

// MARK: - 엔진

@MainActor
public final class LeeoTipJar: ObservableObject {

    public let config: LeeoTipJarConfig

    #if canImport(StoreKit)
    /// 불러온 팁 상품. `config.productIDs` 순서.
    @Published public private(set) var products: [Product] = []
    #endif
    @Published public private(set) var isWorking = false
    /// 이 기기에서 낸 팁 횟수.
    @Published public private(set) var tipCount: Int
    /// 방금 냈다. 화면이 고맙다고 말할 차례.
    @Published public var justTipped = false
    @Published public private(set) var lastError: String?

    #if canImport(StoreKit)
    /// 혼자 쓰는 팁(`startStandalone()`)의 결제 갱신 리스너.
    private var updatesTask: Task<Void, Never>?
    #endif

    let defaults: UserDefaults
    private let countKey: String
    private let seenKey: String
    private let lastTipKey: String
    let askSeenKey: String
    let askLastKey: String
    let askLatersKey: String

    public init(config: LeeoTipJarConfig, defaults: UserDefaults = .standard) {
        self.config = config
        self.defaults = defaults
        let ns = config.productIDs.first ?? "tip"
        countKey = "leeo.tips.count." + ns
        seenKey = "leeo.tips.seen." + ns
        lastTipKey = "leeo.tips.last." + ns
        askSeenKey = "leeo.tips.ask.seen." + ns
        askLastKey = "leeo.tips.ask.last." + ns
        askLatersKey = "leeo.tips.ask.laters." + ns
        tipCount = defaults.integer(forKey: countKey)
    }

    /// 판매 중인 팁이 하나라도 있는가. 없으면 설정에 줄을 세우지 않는다.
    public var isAvailable: Bool {
        #if canImport(StoreKit)
        return !products.isEmpty
        #else
        return false
        #endif
    }

    /// 이 상품의 칸 이름. 계약(`config.productIDs`)의 자리로 정한다. 계약에 없는 상품이면 불러온 순서로.
    func tier(for productID: String, fallbackIndex: Int) -> LeeoTipTier {
        let order = config.productIDs
        guard let index = order.firstIndex(of: productID) else {
            return LeeoTipTier(index: fallbackIndex, of: max(order.count, fallbackIndex + 1))
        }
        return LeeoTipTier(index: index, of: order.count)
    }

    /// 한 번이라도 냈는가.
    public var hasTipped: Bool { tipCount > 0 }

    /// 마지막으로 낸 때. 낸 사람에게는 한동안 다시 부탁하지 않는다(`LeeoTipAskPolicy`).
    public var lastTipAt: Date? { defaults.object(forKey: lastTipKey) as? Date }

    // MARK: 기록

    /// 결제 하나를 센다. 같은 결제를 두 번 세지 않는다(구매 응답과 `Transaction.updates` 가 같은 결제를 줄 수 있다).
    /// - Returns: 처음 본 결제면 true.
    @discardableResult
    func record(transactionID: String, at date: Date = Date()) -> Bool {
        var seen = defaults.stringArray(forKey: seenKey) ?? []
        guard !seen.contains(transactionID) else { return false }
        seen.append(transactionID)
        defaults.set(Array(seen.suffix(100)), forKey: seenKey)
        tipCount += 1
        defaults.set(tipCount, forKey: countKey)
        defaults.set(date, forKey: lastTipKey)
        return true
    }

    #if canImport(StoreKit)
    // MARK: 상품

    public func loadProducts() async {
        guard products.count < config.productIDs.count else { return }
        do {
            let fetched = try await Product.products(for: config.productIDs)
            let order = Dictionary(uniqueKeysWithValues: config.productIDs.enumerated().map { ($1, $0) })
            products = fetched.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        } catch {
            print("❌ [LeeoTipJar.loadProducts] \(error)")
        }
    }

    // MARK: 내기

    /// 팁을 낸다. `using` 은 SwiftUI 의 `@Environment(\.purchase)` (장면에 붙은 결제 창).
    public func purchase(_ product: Product,
                         using action: (Product) async throws -> Product.PurchaseResult) async {
        guard !isWorking else { return }
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await action(product) {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    lastError = L("결제를 확인하지 못했어요.", comment: "Tip jar: unverified transaction")
                    return
                }
                await accept(tx)
            case .pending:
                lastError = L("결제가 승인 대기 중이에요. 승인되면 반영돼요.", comment: "Tip jar: purchase pending (Ask to Buy)")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = L("결제를 마치지 못했어요. 잠시 후 다시 시도해 주세요.", comment: "Gift: purchase failed")
        }
    }

    /// `Transaction.updates` 로 들어온 팁(승인 대기 뒤 결제). LeeoStore 리스너가 넘긴다.
    func handle(update: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = update, config.productIDs.contains(tx.productID) else { return }
        await accept(tx)
    }

    /// 끝나지 않은 팁 결제를 마저 센다. 앱을 열 때 부른다.
    public func resumePending() async {
        for await result in Transaction.unfinished {
            guard case .verified(let tx) = result, config.productIDs.contains(tx.productID) else { continue }
            await accept(tx)
        }
    }

    /// **LeeoStore 없이** 팁만 받는 앱(무료 앱)에서 앱을 열 때 한 번 부른다.
    /// 상품을 불러오고, 끝나지 않은 팁을 마저 세고, 승인 대기 뒤에 온 결제를 듣는다.
    /// ⚠️ 계약(`LeeoPurchaseConfig.tipJar`)으로 만든 팁에는 부르지 않는다. LeeoStore 가 이미 이 일을 한다.
    public func startStandalone() async {
        if updatesTask == nil {
            let ids = Set(config.productIDs)
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    guard case .verified(let tx) = update, ids.contains(tx.productID) else { continue }
                    await self?.accept(tx)
                }
            }
        }
        await loadProducts()
        await resumePending()
    }

    private func accept(_ tx: Transaction) async {
        // 환불된 팁은 세지 않고 닫기만 한다.
        if tx.revocationDate == nil, record(transactionID: String(tx.id)) {
            justTipped = true
            print("✅ [LeeoTipJar] 팁 \(tx.productID), 지금까지 \(tipCount)번")
        }
        await tx.finish()
    }
    #endif
}
