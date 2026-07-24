//
//  LeeoConsumableStore.swift
//  LeeoKit
//
//  소비성 인앱 결제(코인/크레딧) 코어. RoutineCamera·PixelMe 처럼 "구매 → 잔액 충전 → 사용 시 차감"
//  모델을 앱마다 새로 짜지 않도록 공용화한다. 비소비성/구독은 LeeoStore 를 쓴다.
//
//  StoreKit 소비성은 currentEntitlements 에 남지 않으므로, 잔액은 앱이 소유한 값이다.
//  이 스토어는 (1) 소비성 상품 로드/구매 → 지급량만큼 잔액 증가, (2) 잔액 차감(spend),
//  (3) 미완료(중단) 트랜잭션 복구까지 담당하고, 잔액은 지정 suite(앱 그룹)에 영속화한다.
//
//  사용 예:
//      let store = LeeoConsumableStore(config: LeeoConsumableConfig(
//          products: [
//              .init(id: "com.app.coins.10",  grants: 10),
//              .init(id: "com.app.coins.50",  grants: 55),   // 보너스 포함
//          ],
//          cacheSuiteName: "group.com.app"
//      ))
//      if store.spend(3) { /* 기능 실행 */ } else { showCoinShop = true }
//

import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// 소비성 상품 하나 — 상품 ID 와 구매 시 지급할 수량.
public struct LeeoConsumableProduct: Sendable, Identifiable {
    public let id: String
    /// 이 상품을 구매하면 잔액에 더해질 수량 (보너스 포함 최종 지급량).
    public let grants: Int
    public init(id: String, grants: Int) {
        self.id = id
        self.grants = grants
    }
}

/// 소비성 결제 구성.
public struct LeeoConsumableConfig: Sendable {
    /// 판매할 소비성 상품 목록 (배열 순서가 상점 노출 순서).
    public let products: [LeeoConsumableProduct]
    /// 잔액을 저장할 UserDefaults suite (앱 그룹). nil이면 `.standard`.
    public let cacheSuiteName: String?
    /// 신규 설치에 지급할 최초 무료 잔액 (없으면 0).
    public let initialGrant: Int
    /// 한 앱에 서로 다른 잔액(예: 코인 원장과 별도 크레딧 원장)이 여럿일 때 구분하는 식별자.
    /// nil이면 기본 원장. ⚠️ 잔액은 재도출 불가한 실제 값이므로, 배포 후 ledgerID 를 바꾸면 잔액이 분리된다 —
    /// 상품 ID 로 자동 유도하지 않고 앱이 명시적으로 고정한다.
    public let ledgerID: String?

    public init(products: [LeeoConsumableProduct], cacheSuiteName: String? = nil, initialGrant: Int = 0, ledgerID: String? = nil) {
        self.products = products
        self.cacheSuiteName = cacheSuiteName
        self.initialGrant = initialGrant
        self.ledgerID = ledgerID
    }

    var productIDs: [String] { products.map(\.id) }
    func grants(for id: String) -> Int { products.first { $0.id == id }?.grants ?? 0 }
}

@MainActor
public final class LeeoConsumableStore: ObservableObject {
    /// 현재 코인/크레딧 잔액.
    @Published public private(set) var balance: Int = 0
    /// 로드된 소비성 상품.
    @Published public private(set) var products: [Product] = []
    /// 구매 진행 중인 상품 ID.
    @Published public private(set) var purchasingProductID: String?
    /// 마지막 오류 메시지.
    @Published public var lastError: String?

    public let config: LeeoConsumableConfig
    private let defaults: UserDefaults
    private let balanceKey: String
    private let seededKey: String
    private var updatesListener: Task<Void, Never>?

    public init(config: LeeoConsumableConfig) {
        self.config = config
        self.defaults = config.cacheSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        // 원장 식별자로 키를 분리 — 한 앱에 원장이 여럿이어도 잔액이 섞이지 않는다. (기본 원장은 접미사 없음.)
        let suffix = config.ledgerID.map { "." + $0 } ?? ""
        self.balanceKey = "leeo.consumable.balance" + suffix
        self.seededKey = "leeo.consumable.seeded" + suffix

        // 최초 1회 무료 지급.
        if config.initialGrant > 0, !defaults.bool(forKey: seededKey) {
            defaults.set(true, forKey: seededKey)
            defaults.set(config.initialGrant, forKey: balanceKey)
        }
        balance = defaults.integer(forKey: balanceKey)

        updatesListener = Self.makeListener(store: self)
    }

    deinit { updatesListener?.cancel() }

    // MARK: - 잔액

    /// 잔액이 충분하면 차감하고 true. 부족하면 그대로 두고 false.
    @discardableResult
    public func spend(_ amount: Int) -> Bool {
        guard amount > 0 else { return true }
        guard balance >= amount else { return false }
        setBalance(balance - amount)
        return true
    }

    /// 잔액을 더한다 (보상/프로모션 등).
    public func credit(_ amount: Int) {
        guard amount > 0 else { return }
        setBalance(balance + amount)
    }

    public func canAfford(_ amount: Int) -> Bool { balance >= amount }

    private func setBalance(_ value: Int) {
        balance = max(0, value)
        defaults.set(balance, forKey: balanceKey)
    }

    // MARK: - StoreKit

    public func loadProducts() async {
        #if canImport(StoreKit)
        do {
            let fetched = try await Product.products(for: config.productIDs)
            let order = Dictionary(uniqueKeysWithValues: config.productIDs.enumerated().map { ($1, $0) })
            products = fetched.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
            if products.isEmpty {
                lastError = L("판매 중인 상품을 찾지 못했어요.", comment: "Paywall: no products found")
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        #endif
    }

    /// 소비성 상품을 구매하고, 검증되면 지급량만큼 잔액을 올린다.
    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        #if canImport(StoreKit)
        guard purchasingProductID == nil else { return false }
        purchasingProductID = product.id
        lastError = nil
        defer { purchasingProductID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard let transaction = Self.verified(verification) else {
                    lastError = L("구매를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.", comment: "Paywall: unverified purchase")
                    return false
                }
                credit(config.grants(for: transaction.productID))
                await transaction.finish()   // 소비성은 지급 후 반드시 finish
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = L("구매가 승인 대기 중이에요. 승인되면 자동으로 반영됩니다.", comment: "Paywall: pending purchase")
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - 내부

    #if canImport(StoreKit)
    nonisolated private static func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let safe): return safe
        case .unverified: return nil
        }
    }

    /// 앱이 죽어 지급 전에 끊긴 소비성 트랜잭션을 다음 실행에서 복구해 지급한다.
    private static func makeListener(store: LeeoConsumableStore) -> Task<Void, Never> {
        Task.detached {
            for await update in Transaction.updates {
                guard let transaction = verified(update) else { continue }
                await store.creditUnfinished(transaction)
            }
        }
    }

    private func creditUnfinished(_ transaction: Transaction) async {
        let grant = config.grants(for: transaction.productID)
        if grant > 0 { credit(grant) }
        await transaction.finish()
    }
    #else
    private static func makeListener(store: LeeoConsumableStore) -> Task<Void, Never> { Task {} }
    #endif
}
