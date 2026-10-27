//
//  LeeoForeverPass.swift
//  LeeoKit
//
//  언제나 평생 패스가 이 앱에서 열려 있는가를 아는 곳. 규칙은 `LeeoForeverPassRule`.
//
//  · 이 앱에서 산 패스: StoreKit 이 바로 알려 준다. 그 결제(JWS)를 iCloud 에 남겨 다른 앱이 보게 한다.
//  · 다른 앱에서 산 패스: iCloud 의 기록을 읽어 Apple 서명을 확인한다.
//  · 둘 다 마지막으로 안 값을 캐시해 두어, 오프라인에서도 바로 열린다.
//
//  ⚠️ 연 구독 패스는 산 앱이 갱신을 볼 때마다 기록을 새 결제로 바꾼다. 산 앱을 오래 열지 않으면
//     다른 앱에서는 지난 만료일이 지나 닫힐 수 있다. 산 앱을 한 번 열면 다시 열린다.
//
//  사용:
//      @StateObject private var pass = LeeoForeverPass(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub")
//      let isPro = store.hasPro || pass.isActive
//

import Foundation
import CloudKit
#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
public final class LeeoForeverPass: ObservableObject {

    /// 패스가 이 앱을 열고 있는가(어느 앱에서 샀든).
    @Published public private(set) var isActive: Bool

    /// 이 앱에서 파는 패스 상품(평생 · 연 구독 · 올리기 · 졸업). 불러온 것만.
    @Published public private(set) var products: [Product] = []

    public let bundleID: String
    private let containerIdentifier: String
    private let defaults: UserDefaults
    private var listener: Task<Void, Never>?

    private static let cacheKey = "leeo.foreverPass.active"
    private static let recordType = "LeeoForeverPass"
    private static let recordName = "foreverpass"
    private static let jwsField = "passes"

    public var productIDs: [String] { LeeoForeverPassRule.productIDs(bundleID: bundleID) }

    /// - Parameters:
    ///   - containerIdentifier: 모든 앱이 함께 쓰는 CloudKit 컨테이너(피드백 허브). 앱 entitlements 에 있어야 한다.
    ///   - defaults: 캐시. 확장(키보드 · 위젯)이 같은 값을 보게 하려면 App Group 을 넘긴다.
    public init(containerIdentifier: String,
                defaults: UserDefaults = .standard,
                bundleID: String = Bundle.main.bundleIdentifier ?? "") {
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
        self.bundleID = bundleID
        self.isActive = defaults.bool(forKey: Self.cacheKey)
        #if canImport(StoreKit)
        listener = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refresh()
            }
        }
        #endif
    }

    deinit { listener?.cancel() }

    // MARK: - 확인

    /// 이 앱의 결제와 iCloud 의 기록을 다시 본다. 앱을 열 때 · 복원할 때 · 패스 화면을 열 때 부른다.
    public func refresh() async {
        #if canImport(StoreKit)
        let mine = await ownedHere()
        if let mine { await publish(mine) }
        let shared = await sharedPasses()
        set(mine != nil || shared)
        #endif
    }

    #if canImport(StoreKit)
    public func loadProducts() async {
        guard products.count < productIDs.count else { return }
        let fetched = (try? await Product.products(for: productIDs)) ?? []
        let order = Dictionary(uniqueKeysWithValues: productIDs.enumerated().map { ($1, $0) })
        products = fetched.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    public func product(_ kind: LeeoForeverPassRule.Kind) -> Product? {
        products.first { $0.id == LeeoForeverPassRule.productID(kind, bundleID: bundleID) }
    }

    /// 이 앱에서 산 패스 결제의 JWS. 없으면 nil.
    private func ownedHere() async -> String? {
        let ids = Set(productIDs)
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, ids.contains(tx.productID), tx.revocationDate == nil else { continue }
            return result.jwsRepresentation
        }
        return nil
    }
    #endif

    /// 출시 빌드는 실제 결제만 믿는다. 시험 빌드(디버그)는 샌드박스 결제도 받는다.
    private var acceptsSandbox: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - iCloud

    private var database: CKDatabase { CKContainer(identifier: containerIdentifier).privateCloudDatabase }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: Self.recordName) }

    /// 다른 앱이 남긴 패스 중 지금 이 앱을 여는 것이 있는가.
    private func sharedPasses() async -> Bool {
        guard !Self.runningTests,
              let record = try? await database.record(for: recordID),
              let list = record[Self.jwsField] as? [String] else { return false }
        return list.contains { jws in
            guard let tx = try? LeeoGiftJWS.verify(jws) else { return false }
            return LeeoForeverPassRule.opens(tx, acceptsSandbox: acceptsSandbox)
        }
    }

    /// 이 앱에서 산 패스를 남긴다. 같은 앱의 지난 기록은 새 결제로 바꾼다(연 구독 갱신).
    private func publish(_ jws: String) async {
        guard !Self.runningTests else { return }
        let record = (try? await database.record(for: recordID)) ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        var list = (record[Self.jwsField] as? [String]) ?? []
        guard !list.contains(jws) else { return }
        list.removeAll { (try? LeeoGiftJWS.decodeUnverified($0))?.bundleID == bundleID }
        list.append(jws)
        record[Self.jwsField] = list as CKRecordValue
        do {
            _ = try await database.save(record)
        } catch {
            print("⚠️ [LeeoForeverPass.publish] iCloud 에 패스를 남기지 못했다: \(error.localizedDescription)")
        }
    }

    private func set(_ active: Bool) {
        if isActive != active { isActive = active }
        defaults.set(active, forKey: Self.cacheKey)
    }

    /// 단위 시험 안에서는 iCloud 에 닿지 않는다(컨테이너 권한이 없어 그 자리에서 죽는다).
    private static var runningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
}
