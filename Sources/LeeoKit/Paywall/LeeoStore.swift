//
//  LeeoStore.swift
//  LeeoKit
//
//  StoreKit 2 를 감싼 인앱 결제 코어(비소비성/구독). 상품 로드 · 구매 · 복원 · 권한(entitlement)
//  추적을 한 곳에서 처리하고, 앱은 `hasPro` 만 관찰하면 된다. 앱마다 반복되던
//  StoreManager 보일러플레이트(트랜잭션 리스너·검증·캐시)를 여기로 흡수한다.
//
//  각 앱이 실제로 필요로 하던 것들을 옵션으로 흡수:
//   - 오프라인 즉시 잠금 해제  : config.cacheSuiteName (앱 그룹) 에 권한 캐시
//   - 개발/샌드박스/맥앱 언락    : unlockOverride 로 앱이 정책을 주입 (true=해제, false=강제잠금)
//   - 유료→프리 전환 그랜드파더링: grandfather 로 앱이 판정(AppTransaction/사용흔적 등)
//   - 외부 트랜잭션(환불·가족공유·타기기): 상시 리스너가 자동 반영
//
//  사용 예:
//      // 앱 전역에서 한 번 생성해 주입
//      @StateObject private var store = LeeoStore(config: MyAppSpec.paywall!)
//      WindowGroup { RootView().environmentObject(store) }
//      // 어디서든:  if store.hasPro { ... } else { showPaywall = true }
//
//  페이월 UI 만 필요하면 LeeoPaywallView 가 내부에서 스토어를 스스로 만든다.
//

import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
public final class LeeoStore: ObservableObject {
    /// 로드된 판매 상품 (config.productIDs 순서를 따른다).
    @Published public private(set) var products: [Product] = []

    /// 현재 유효한 권한을 가진 상품 ID 집합 (환불/만료/취소는 제외).
    @Published public private(set) var purchasedProductIDs: Set<String> = []

    /// 상품 로딩 중 여부.
    @Published public private(set) var isLoadingProducts = false

    /// 구매 진행 중인 상품 ID (버튼 스피너 표시용). 없으면 nil.
    @Published public private(set) var purchasingProductID: String?

    /// 복원 진행 중 여부.
    @Published public private(set) var isRestoring = false

    /// 마지막 오류 메시지 (사용자 노출용). 성공 흐름에서 nil 로 지워진다.
    @Published public var lastError: String?

    /// 유료→프리 전환 시 기존 구매자 보호(그랜드파더링)로 권한을 부여받았는지.
    @Published public private(set) var isGrandfathered = false

    /// 프로/유료 권한 보유 여부.
    /// unlockOverride(개발/샌드박스/맥앱) → 그랜드파더링 → 실제 구매 순으로 판정한다.
    public var hasPro: Bool {
        if let forced = unlockOverride?() { return forced }
        if isGrandfathered { return true }
        return !purchasedProductIDs.isDisjoint(with: config.entitlementIDs)
    }

    public let config: LeeoPaywallConfig

    /// 앱이 주입하는 언락 정책. true=강제 해제(개발/맥앱), false=강제 잠금(페이월 테스트), nil=정상 판정.
    private let unlockOverride: (@MainActor () -> Bool?)?
    /// 앱이 주입하는 그랜드파더링 판정 (구매가 없을 때 1회 확인, 결과 캐시).
    private let grandfather: (@MainActor () async -> Bool)?

    private let defaults: UserDefaults
    private let cacheKeyOwned: String
    private let cacheKeyGrandfather: String
    private var grandfatherChecked = false
    private var updatesListener: Task<Void, Never>?

    /// - Parameters:
    ///   - config: 상품/캐시 구성. 보통 `MyAppSpec.paywall!` 를 넘긴다.
    ///   - unlockOverride: 개발/샌드박스/맥앱 등에서 권한을 강제할 정책 (없으면 실제 구매만).
    ///   - grandfather: 유료→프리 전환 기존 사용자에게 Pro 를 부여할 판정 (없으면 미적용).
    public init(
        config: LeeoPaywallConfig,
        unlockOverride: (@MainActor () -> Bool?)? = nil,
        grandfather: (@MainActor () async -> Bool)? = nil
    ) {
        self.config = config
        self.unlockOverride = unlockOverride
        self.grandfather = grandfather
        self.defaults = config.cacheSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        // 캐시 키를 상품 ID 로 네임스페이스화 — 한 앱/한 suite 에 LeeoStore 가 여러 개(구독·팩·프리미엄 등)
        // 있어도 서로의 캐시를 덮어쓰지 않는다. (이 캐시는 StoreKit 에서 재도출 가능한 값이라 키가 바뀌어도 손실 없음.)
        let ns = Self.namespace(for: config.productIDs)
        self.cacheKeyOwned = "leeo.paywall.owned." + ns
        self.cacheKeyGrandfather = "leeo.paywall.grandfathered." + ns

        // 네트워크 응답 전까지는 마지막으로 알던 권한으로 시작해 기능 깜빡임을 막는다.
        if let cached = defaults.array(forKey: cacheKeyOwned) as? [String] {
            purchasedProductIDs = Set(cached)
        }
        isGrandfathered = defaults.bool(forKey: cacheKeyGrandfather)

        // 앱 실행 중 발생하는 트랜잭션 갱신(다른 기기 구매·환불·가족 공유)을 항상 반영.
        updatesListener = Self.makeListener(store: self)
        Task { await refreshEntitlements() }
    }

    deinit { updatesListener?.cancel() }

    // MARK: - 상품 로드

    /// config.productIDs 에 해당하는 상품을 App Store 에서 불러온다.
    public func loadProducts() async {
        #if canImport(StoreKit)
        guard !isLoadingProducts else { return }
        // 상품이 App Store Connect 에서 하나씩 전파되므로, 일부만 온 동안엔 다시 시도한다.
        guard products.count < config.productIDs.count else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
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

    // MARK: - 구매 / 복원

    /// 상품을 구매한다. 성공(권한 획득)하면 true.
    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        #if canImport(StoreKit)
        guard purchasingProductID == nil else { return false }
        purchasingProductID = product.id
        lastError = nil
        defer { purchasingProductID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = Self.verified(verification) else {
                    lastError = L("구매를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.", comment: "Paywall: unverified purchase")
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return hasPro
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

    /// 첫 상품(보통 대표 상품)을 구매하는 편의 메서드. 상품이 없으면 먼저 로드한다.
    @discardableResult
    public func purchasePrimary() async -> Bool {
        if products.isEmpty { await loadProducts() }
        guard let product = products.first else {
            lastError = L("상품을 불러오지 못했어요.", comment: "Paywall: load failed")
            return false
        }
        return await purchase(product)
    }

    /// 이전 구매를 복원한다 (App Store 계정 동기화 후 권한 재확인).
    public func restore() async {
        #if canImport(StoreKit)
        guard !isRestoring else { return }
        isRestoring = true
        lastError = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            // sync 실패해도 currentEntitlements 는 확인해 본다 (이미 캐시된 권한이 있을 수 있음).
            lastError = error.localizedDescription
        }
        grandfatherChecked = false   // 동기화로 영수증이 갱신됐으니 그랜드파더링도 다시 확인
        await refreshEntitlements()
        #endif
    }

    // MARK: - 권한 판정

    /// 현재 유효한 모든 권한을 다시 훑어 상태를 갱신하고 캐시한다.
    public func refreshEntitlements() async {
        #if canImport(StoreKit)
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.verified(result) else { continue }
            if transaction.revocationDate == nil { owned.insert(transaction.productID) }
        }
        purchasedProductIDs = owned

        // 실제 구매가 없을 때만 그랜드파더링을 (앱 정책에 따라) 1회 확인한다.
        let entitledNow = !owned.isDisjoint(with: config.entitlementIDs)
        if !entitledNow, !isGrandfathered, !grandfatherChecked, let grandfather {
            grandfatherChecked = true
            if await grandfather() { isGrandfathered = true }
        }

        // 캐시: override 는 매 실행 즉시 재평가되므로 캐시하지 않는다.
        defaults.set(Array(owned), forKey: cacheKeyOwned)
        defaults.set(isGrandfathered, forKey: cacheKeyGrandfather)
        #endif
    }

    // MARK: - 내부

    /// 상품 ID 집합에서 안정적인(실행 간 동일) 짧은 네임스페이스를 만든다 — 캐시 키 충돌 방지용.
    /// Swift 의 Hasher 는 실행마다 시드가 달라 못 쓰므로 FNV-1a 로 직접 계산한다.
    nonisolated private static func namespace(for ids: [String]) -> String {
        let joined = ids.sorted().joined(separator: ",")
        var hash: UInt64 = 1469598103934665603   // FNV-1a offset basis
        for byte in joined.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return String(hash, radix: 36)
    }

    #if canImport(StoreKit)
    /// 서명 검증을 통과한 트랜잭션만 꺼낸다 (변조/미검증은 버림).
    nonisolated private static func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let safe): return safe
        case .unverified: return nil
        }
    }

    /// 앱 생존 기간 동안 트랜잭션 갱신을 수신해 권한을 반영하는 리스너.
    private static func makeListener(store: LeeoStore) -> Task<Void, Never> {
        Task.detached {
            for await update in Transaction.updates {
                guard let transaction = verified(update) else { continue }
                await transaction.finish()
                await store.refreshEntitlements()
            }
        }
    }
    #else
    private static func makeListener(store: LeeoStore) -> Task<Void, Never> { Task {} }
    #endif
}
