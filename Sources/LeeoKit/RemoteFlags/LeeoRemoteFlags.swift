//
//  LeeoRemoteFlags.swift
//  LeeoKit
//
//  원격 킬스위치 — 심사 없이 문제 기능을 끌 수 있는 최소 장치.
//
//  왜 필요한가: 기능 하나가 사고를 내면 고쳐서 심사를 통과할 때까지(며칠) 손쓸 방법이 없다.
//  피드백/통계용 CloudKit 공개 DB가 이미 있으므로 레코드 하나만 더 두면 되고,
//  새 인프라 비용이 사실상 0이다.
//
//  설계 원칙 (바꾸지 말 것)
//   ⚠️ **가용성 우선**: 조회에 실패하면 전부 "켬"으로 둔다. 네트워크가 없다고 앱 기능이
//      꺼지면 킬스위치가 오히려 장애 원인이 된다.
//   ⚠️ **읽기는 네트워크를 타지 않는다**: 캐시(App Group 또는 standard UserDefaults)만 본다.
//      갱신은 `refreshInBackground()` 가 따로 한다 → 런치가 느려지지 않는다.
//   ⚠️ 여기서 끄는 건 **기능**이지 사용자 데이터가 아니다. 꺼져도 데이터는 남는다.
//
//  사용 예:
//      enum MyFlag: String, LeeoRemoteFlag {
//          case syncEnabled, paywallEnabled
//      }
//
//      // 앱 시작 시 1회
//      LeeoRemoteFlags(spec: MyAppSpec.self).refreshInBackground(MyFlag.self)
//
//      // 사용하는 곳 (네트워크 없음, 즉시 반환)
//      guard LeeoRemoteFlags.isEnabled(MyFlag.syncEnabled) else { return }
//
//  CloudKit Dashboard 준비 (1회)
//   레코드 타입 `RemoteFlags` / recordName `flags_<appIdentifier>`
//   필드: 각 플래그 rawValue 를 **Int64**(1=켬, 0=끔)로 추가 → Production 배포.
//   ⚠️ 필드를 안 만들어도 된다 — 없으면 "켬"으로 동작한다(안전 기본값).
//

import Foundation
import CloudKit

/// 원격으로 끌 수 있는 기능을 나타내는 타입.
/// ⚠️ `rawValue` 가 **CloudKit 필드명과 정확히 같아야** 한다. 이름을 바꾸면 대시보드에서
///    아무리 꺼도 앱은 켠 채로 동작한다(조용한 실패).
public protocol LeeoRemoteFlag {
    var rawValue: String { get }
}

public final class LeeoRemoteFlags: @unchecked Sendable {

    public static let recordType = "RemoteFlags"

    private static let cachePrefix = "leeo.flag."
    private static let lastFetchPrefix = "leeo.flags.lastFetchAt."

    /// 캐시를 둘 곳. App Group 을 주면 익스텐션(키보드·위젯)도 같은 값을 읽는다.
    private static var sharedSuiteName: String?

    private let config: LeeoFeedbackConfig
    /// 조회 실패가 반복될 때 매 실행마다 네트워크를 때리지 않도록 하는 최소 간격.
    private let refreshInterval: TimeInterval

    public init(config: LeeoFeedbackConfig,
                appGroupSuiteName: String? = nil,
                refreshInterval: TimeInterval = 6 * 3600) {
        self.config = config
        self.refreshInterval = refreshInterval
        if let appGroupSuiteName { Self.sharedSuiteName = appGroupSuiteName }
    }

    /// Spec 기반 편의 생성자 — 피드백과 같은 컨테이너·appId 를 재사용한다.
    public convenience init<Spec: LeeoAppSpec>(spec: Spec.Type,
                                               appGroupSuiteName: String? = nil,
                                               refreshInterval: TimeInterval = 6 * 3600) {
        self.init(config: Spec.feedback,
                  appGroupSuiteName: appGroupSuiteName,
                  refreshInterval: refreshInterval)
    }

    // MARK: - 읽기 (네트워크 없음)

    /// 플래그 값. 캐시에 없으면 **켬**으로 본다.
    /// `static` 인 이유: 익스텐션·백그라운드 등 인스턴스를 만들기 애매한 곳에서도 읽어야 한다.
    public static func isEnabled(_ flag: LeeoRemoteFlag) -> Bool {
        let key = cachePrefix + flag.rawValue
        for defaults in candidateDefaults() where defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return true   // 한 번도 못 받아봤다 → 켬
    }

    /// App Group 을 쓰는 앱이 익스텐션에서 읽을 때 필요 — 앱 실행 전에 호출해도 된다.
    public static func configure(appGroupSuiteName: String?) {
        sharedSuiteName = appGroupSuiteName
    }

    private static func candidateDefaults() -> [UserDefaults] {
        var list: [UserDefaults] = []
        if let name = sharedSuiteName, let group = UserDefaults(suiteName: name) { list.append(group) }
        list.append(.standard)
        return list
    }

    private static var writeDefaults: UserDefaults {
        if let name = sharedSuiteName, let group = UserDefaults(suiteName: name) { return group }
        return .standard
    }

    // MARK: - 갱신

    /// 앱 시작 시 호출. 쓰로틀 간격 안이면 아무것도 하지 않는다.
    /// 실패해도 조용히 넘어간다 — 캐시(또는 기본값 켬)로 계속 동작한다.
    public func refreshInBackground<F>(_ flags: F.Type)
    where F: LeeoRemoteFlag & CaseIterable & RawRepresentable, F.RawValue == String {
        let key = Self.lastFetchPrefix + (config.appIdentifier ?? "-")
        let last = Self.writeDefaults.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > refreshInterval else { return }

        Task(priority: .utility) { [weak self] in
            await self?.fetch(flags)
        }
    }

    /// 실제 조회. 성공한 필드만 캐시에 반영한다(부분 성공 허용).
    public func fetch<F>(_ flags: F.Type) async
    where F: LeeoRemoteFlag & CaseIterable & RawRepresentable, F.RawValue == String {
        let database = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        let recordName = "flags_\(config.appIdentifier ?? "default")"
        let fetchedAtKey = Self.lastFetchPrefix + (config.appIdentifier ?? "-")

        do {
            let record = try await database.record(for: CKRecord.ID(recordName: recordName))
            for flag in F.allCases {
                // 필드가 없으면 건드리지 않는다 — 기존 캐시(또는 기본 켬)를 유지.
                guard let raw = record[flag.rawValue] as? Int64 else { continue }
                Self.writeDefaults.set(raw != 0, forKey: Self.cachePrefix + flag.rawValue)
            }
            Self.writeDefaults.set(Date().timeIntervalSince1970, forKey: fetchedAtKey)
        } catch let error as CKError where error.code == .unknownItem {
            // 레코드를 아직 안 만든 정상 상태 — 전부 켬으로 두고 다음 주기까지 조용히 지낸다.
            Self.writeDefaults.set(Date().timeIntervalSince1970, forKey: fetchedAtKey)
        } catch {
            // 네트워크·권한 실패. **캐시를 건드리지 않는다** — 마지막으로 알던 값을 유지.
        }
    }
}
