//
//  LeeoTipJar.swift
//  LeeoKit
//
//  **이미 다 가진 사람이 조금 더 내고 싶을 때** 내는 곳(팁). 기능을 열지 않는다.
//
//  - 상품은 소모성(Consumable)이다. 몇 번이든 낼 수 있다.
//  - 낸 것은 점수 장부로 남는다(`LeeoSupporter`): 작은 칸 1 · 중간 3 · 큰 10점, iCloud 로 기기와 앱을 넘어 합친다.
//    점수는 단계(응원자 · 단골 · 후견인)와 보상을 정할 뿐, 권한이 아니므로 기능을 열지 않는다.
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
    /// 단골(10점)부터 쓸 수 있는 후원자 전용 앱 아이콘 이름(Asset Catalog 의 대체 아이콘). 없으면 그 보상을 그리지 않는다.
    /// ⚠️ 앱 타깃의 'Include all app icon assets' 를 켜거나 CFBundleAlternateIcons 에 넣어야 바뀐다.
    public let supporterIcon: String?
    /// 후견인(30점)의 베타 초대 — 공개 TestFlight 링크. 없으면 개발자에게 베타 신청 메일을 쓴다.
    public let betaURL: URL?

    public init(productIDs: [String], thanksPage: URL? = nil, supporterIcon: String? = nil, betaURL: URL? = nil) {
        self.productIDs = productIDs
        self.thanksPage = thanksPage
        self.supporterIcon = supporterIcon
        self.betaURL = betaURL
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
    /// 이 앱에서 낸 팁 횟수(다른 기기에서 낸 것도 iCloud 로 합친다).
    @Published public private(set) var tipCount: Int
    /// 리이오의 모든 앱에서 쌓은 후원 점수(`LeeoSupporterLedger`).
    @Published public private(set) var points: Int
    /// 방금 냈다. 화면이 고맙다고 말할 차례.
    @Published public var justTipped = false
    @Published public private(set) var lastError: String?

    #if canImport(StoreKit)
    /// 혼자 쓰는 팁(`startStandalone()`)의 결제 갱신 리스너.
    private var updatesTask: Task<Void, Never>?
    #endif

    let defaults: UserDefaults
    /// 장부에 적는 이 앱의 이름.
    let bundleID: String
    /// 점수를 맞출 iCloud 컨테이너. 화면(`LeeoTipJarView` · `LeeoTipJarLink`)이 처음 맞출 때 알려 준다.
    private var containerIdentifier: String?
    private let countKey: String
    private let ledgerKey: String
    private let sharedKey: String
    private let seenKey: String
    private let lastTipKey: String
    let askSeenKey: String
    let askLastKey: String
    let askLatersKey: String

    public init(config: LeeoTipJarConfig, defaults: UserDefaults = .standard,
                bundleID: String = Bundle.main.bundleIdentifier ?? "") {
        self.config = config
        self.defaults = defaults
        let ns = config.productIDs.first ?? "tip"
        self.bundleID = bundleID.isEmpty ? ns : bundleID
        countKey = "leeo.tips.count." + ns
        ledgerKey = "leeo.tips.ledger." + ns
        sharedKey = "leeo.tips.shared"
        seenKey = "leeo.tips.seen." + ns
        lastTipKey = "leeo.tips.last." + ns
        askSeenKey = "leeo.tips.ask.seen." + ns
        askLastKey = "leeo.tips.ask.last." + ns
        askLatersKey = "leeo.tips.ask.laters." + ns
        tipCount = defaults.integer(forKey: countKey)
        points = 0
        // 장부가 생기기 전에 센 팁은 칸을 몰라 작은 칸(1점)으로 친다. 기기마다 따로 센 것이라 기기 이름을 붙인다.
        if defaults.stringArray(forKey: ledgerKey) == nil {
            let device = UUID().uuidString.prefix(8)
            defaults.set((0..<tipCount).map {
                LeeoSupporterLedger.entry(bundleID: self.bundleID, transactionID: "legacy.\(device).\($0)", points: 1)
            }, forKey: ledgerKey)
        }
        refreshPoints()
    }

    // MARK: 후원 단계

    /// 지금 단계. 아직 내지 않았으면 nil.
    public var level: LeeoSupporterLevel? { LeeoSupporterLevel.of(points: points) }

    /// 최근 `days` 일 안에 냈는가. 무료로 쓰다 후원한 사람에게 업그레이드 배너를 쉬게 할 때 쓴다(기본 30일).
    public func tippedRecently(days: Int = 30, now: Date = Date()) -> Bool {
        guard let lastTipAt else { return false }
        return now.timeIntervalSince(lastTipAt) < TimeInterval(days) * 24 * 60 * 60
    }

    /// 이 앱이 따로 세던 옛 후원(예: 앱 자체 팁 화면 · 옛 비소모성 커피)을 한 번만 장부로 옮긴다. 한 번에 1점씩.
    /// 번호가 기기와 상관없이 같아(`adopted.0` …) 여러 기기에서 불러도 두 번 세지 않는다.
    public func adoptLegacyTips(_ count: Int) {
        let lines = (0..<max(count, 0)).map {
            LeeoSupporterLedger.entry(bundleID: bundleID, transactionID: "adopted.\($0)", points: 1)
        }
        setLedger(LeeoSupporterLedger.merge(ledger, lines))
    }

    /// 다른 기기 · 다른 앱의 장부와 맞춘다. 화면이 열릴 때와 팁을 낸 뒤에 부른다.
    public func syncSupporter(containerIdentifier: String) async {
        self.containerIdentifier = containerIdentifier
        let local = LeeoSupporterLedger.merge(ledger, shared)
        guard let merged = await LeeoSupporterCloud.sync(local, containerIdentifier: containerIdentifier) else { return }
        defaults.set(merged, forKey: sharedKey)
        setLedger(LeeoSupporterLedger.merge(ledger, LeeoSupporterLedger.lines(merged, of: bundleID)))
    }

    private var ledger: [String] { defaults.stringArray(forKey: ledgerKey) ?? [] }
    private var shared: [String] { defaults.stringArray(forKey: sharedKey) ?? [] }

    private func setLedger(_ lines: [String]) {
        defaults.set(lines, forKey: ledgerKey)
        let count = max(defaults.integer(forKey: countKey), lines.count)
        if tipCount != count { tipCount = count }
        defaults.set(count, forKey: countKey)
        refreshPoints()
    }

    private func refreshPoints() {
        let total = LeeoSupporterLedger.total(LeeoSupporterLedger.merge(ledger, shared))
        if points != total { points = total }
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
    func record(transactionID: String, productID: String? = nil, at date: Date = Date()) -> Bool {
        var seen = defaults.stringArray(forKey: seenKey) ?? []
        guard !seen.contains(transactionID) else { return false }
        seen.append(transactionID)
        defaults.set(Array(seen.suffix(100)), forKey: seenKey)
        tipCount += 1
        defaults.set(tipCount, forKey: countKey)
        defaults.set(date, forKey: lastTipKey)
        let size = productID.map { tier(for: $0, fallbackIndex: 0).size } ?? .small
        setLedger(LeeoSupporterLedger.merge(ledger, [LeeoSupporterLedger.entry(
            bundleID: bundleID, transactionID: transactionID, points: LeeoSupporterLedger.points(for: size))]))
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
        if tx.revocationDate == nil, record(transactionID: String(tx.id), productID: tx.productID) {
            justTipped = true
            print("✅ [LeeoTipJar] 팁 \(tx.productID), 지금까지 \(tipCount)번 · \(points)점")
        }
        await tx.finish()
        if let containerIdentifier { await syncSupporter(containerIdentifier: containerIdentifier) }
    }
    #endif
}
