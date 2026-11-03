//
//  LeeoVault.swift
//  LeeoKit
//
//  사용자의 기록이 날아가지 않게 하는 금고. 세 겹이다.
//
//    ① 이 기기 — 매일 한 번, 그리고 **업데이트 직후 첫 실행에서 저장소를 열기 전에** 앱의 데이터를
//       통째로 떠 둔다(Documents · Application Support · 앱 그룹 · UserDefaults).
//       APFS 복제(copy-on-write)라 순간에 끝나고, 바뀐 만큼만 자리를 차지한다.
//       구조 이전이 어긋나 기록을 못 읽게 되어도 "업데이트 직전" 상태로 되돌릴 수 있다.
//    ② iCloud — 하루 한 번 최신 백업을 묶어 **사용자 본인의 iCloud 개인 데이터베이스**에 올린다.
//       폰을 잃어버리거나 앱을 지워도 다시 깔고 되살린다. 개발자는 볼 수 없다.
//    ③ 파일 — 사용자가 직접 내보내고(파일 앱 · 컴퓨터 · 다른 클라우드) 가져온다.
//
//  복원은 **다음 실행의 맨 처음**, 저장소가 열리기 전에 한다. 복원 직전 상태도 따로 떠 두므로
//  복원 자체도 되돌릴 수 있다. 앱은 `LeeoKit.bootstrap` 을 앱 시작에서 가장 먼저 부르기만 하면 된다
//  (bootstrap 을 안 쓰는 앱은 `LeeoVault.start(MySpec.self)`).
//
//  iCloud 쪽은 피드백 허브 컨테이너(`Spec.feedback.containerIdentifier`)의 **private** DB 를 쓴다.
//  레코드 타입 `LeeoBackup` 을 Production 스키마에 배포해야 한다 (docs/VAULT.md).
//

import Foundation
import AppleArchive
import System
#if canImport(CloudKit)
import CloudKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 백업 한 벌

public struct LeeoVaultSnapshot: Codable, Identifiable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case daily, update, manual, beforeRestore, imported, cloud
    }
    public let id: String
    public let createdAt: Date
    public let appVersion: String
    public let reason: Reason
    public let device: String
    /// 담긴 파일의 크기 합(바이트). 복제라 기기에서 실제로 차지하는 자리는 이보다 훨씬 작다.
    public let bytes: Int64
    /// 떠 둔 폴더 열쇠 ("home/Documents" · "group/<id>") — 없던 폴더는 복원 때 비운다
    public let roots: [String]
    /// 떠 둔 UserDefaults 도메인
    public let defaults: [String]
    /// 그때 앱이 알고 있던 앱 그룹 — 여기 없는 그룹은 복원 때 건드리지 않는다
    public let groups: [String]
}

public enum LeeoVaultError: LocalizedError {
    case notStarted, unreadableArchive, tooLarge(Int64), cloudUnavailable, notFound

    public var errorDescription: String? {
        switch self {
        case .notStarted: return "LeeoVault.start 가 불리지 않았습니다"
        case .unreadableArchive: return L("백업 파일을 읽지 못했어요.", comment: "Vault: import failed")
        case .tooLarge: return L("용량이 커서 iCloud에는 올리지 못했어요. 파일로 내보내 보관해 주세요.", comment: "Vault: too large for iCloud")
        case .cloudUnavailable: return L("iCloud에 로그인하면 사용할 수 있어요.", comment: "Vault: iCloud unavailable")
        case .notFound: return L("백업을 찾지 못했어요.", comment: "Vault: backup not found")
        }
    }
}

// MARK: - 금고 (파일 시스템)

/// 폴더 하나를 금고 안팎으로 옮기는 단위. `excluded` 는 그 폴더 기준 상대 경로.
struct LeeoVaultRoot {
    let key: String
    let url: URL
    var excluded: Set<String> = []
}

/// 기록을 떠 두고 되돌리는 곳. 경로를 주입할 수 있어 시험에서 임시 폴더로 그대로 굴린다.
final class LeeoVaultStore: @unchecked Sendable {
    let base: URL
    let roots: [LeeoVaultRoot]
    let groups: [String]
    /// (도메인, UserDefaults) — standard 는 번들 ID 도메인
    let defaults: [(String, UserDefaults)]
    let appVersion: String
    let device: String

    private let fm = FileManager.default
    private let lock = NSRecursiveLock()

    /// 종류별로 남기는 개수. 복제라 개수가 늘어도 바뀐 만큼만 자리를 차지한다.
    static let keep: [LeeoVaultSnapshot.Reason: Int] = [
        .daily: 3, .update: 3, .manual: 5, .beforeRestore: 3, .imported: 2, .cloud: 2,
    ]

    init(base: URL, roots: [LeeoVaultRoot], groups: [String], defaults: [(String, UserDefaults)],
         appVersion: String, device: String) {
        self.base = base
        self.roots = roots
        self.groups = groups
        self.defaults = defaults
        self.appVersion = appVersion
        self.device = device
    }

    var snapshotsDir: URL { base.appendingPathComponent("snapshots", isDirectory: true) }
    private var pendingURL: URL { base.appendingPathComponent("pending-restore.json") }
    private var stateURL: URL { base.appendingPathComponent("state.json") }

    // MARK: 상태

    struct State: Codable {
        var lastVersion: String?
        var cloudEnabled: Bool = true
        var lastUpload: Date?
        var lastUploadedID: String?
        var cloudNote: String?
        var lastRestoredID: String?
        var lastRestoredAt: Date?
    }

    func state() -> State {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return s
    }

    func updateState(_ body: (inout State) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var s = state()
        body(&s)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        try? JSONEncoder().encode(s).write(to: stateURL, options: .atomic)
    }

    // MARK: 목록

    func snapshots() -> [LeeoVaultSnapshot] {
        lock.lock(); defer { lock.unlock() }
        let dirs = (try? fm.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { manifest(in: $0) }.sorted { $0.createdAt > $1.createdAt }
    }

    func manifest(in dir: URL) -> LeeoVaultSnapshot? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(LeeoVaultSnapshot.self, from: data)
    }

    func directory(of snapshot: LeeoVaultSnapshot) -> URL {
        snapshotsDir.appendingPathComponent(snapshot.id, isDirectory: true)
    }

    // MARK: 뜨기

    /// 지금 상태를 한 벌 떠 둔다. 저장소가 열리기 전(앱 시작 맨 처음)에 부르는 것이 가장 안전하다.
    @discardableResult
    func take(_ reason: LeeoVaultSnapshot.Reason, now: Date = Date()) throws -> LeeoVaultSnapshot {
        lock.lock(); defer { lock.unlock() }
        let id = Self.makeID(now, reason)
        let work = snapshotsDir.appendingPathComponent(".\(id)", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        var captured: [String] = []
        for root in roots where fm.fileExists(atPath: root.url.path) {
            let dest = work.appendingPathComponent("data", isDirectory: true).appendingPathComponent(root.key, isDirectory: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try copyContents(of: root.url, to: dest, excluded: root.excluded, prefix: "")
            captured.append(root.key)
        }
        var domains: [String] = []
        let defaultsDir = work.appendingPathComponent("defaults", isDirectory: true)
        try fm.createDirectory(at: defaultsDir, withIntermediateDirectories: true)
        for (domain, store) in defaults {
            guard let dict = store.persistentDomain(forName: domain), !dict.isEmpty else { continue }
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
            try data.write(to: defaultsDir.appendingPathComponent(Self.fileName(domain) + ".plist"))
            domains.append(domain)
        }
        let snap = LeeoVaultSnapshot(id: id, createdAt: now, appVersion: appVersion, reason: reason,
                                     device: device, bytes: Self.size(of: work), roots: captured,
                                     defaults: domains, groups: groups)
        try writeManifest(snap, in: work)
        // 다 뜬 뒤에야 이름을 붙인다 — 도중에 죽으면 점(.)으로 시작하는 반쪽짜리만 남고 목록에 안 뜬다
        try fm.moveItem(at: work, to: snapshotsDir.appendingPathComponent(id, isDirectory: true))
        prune()
        return snap
    }

    func writeManifest(_ snap: LeeoVaultSnapshot, in dir: URL) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(snap).write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// `excluded` 에 든 상대 경로는 건너뛰고, 그 위 폴더는 안으로 들어가 나머지만 복제한다.
    private func copyContents(of src: URL, to dest: URL, excluded: Set<String>, prefix: String) throws {
        for item in (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? [] {
            let rel = prefix + item.lastPathComponent
            if excluded.contains(rel) { continue }
            let target = dest.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            let merge = fm.fileExists(atPath: target.path, isDirectory: &isDir) && isDir.boolValue   // 복원 때 남겨 둔 폴더(캐시 위)
            if merge || excluded.contains(where: { $0.hasPrefix(rel + "/") }) {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                try copyContents(of: item, to: target, excluded: excluded, prefix: rel + "/")
            } else {
                try fm.copyItem(at: item, to: target)   // APFS 에서는 복제 — 즉시, 자리 거의 안 씀
            }
        }
    }

    private func prune() {
        let all = snapshots()
        for (reason, count) in Self.keep {
            for old in all.filter({ $0.reason == reason }).dropFirst(count) {
                try? fm.removeItem(at: directory(of: old))
            }
        }
        // 도중에 끊긴 반쪽짜리
        for item in (try? fm.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent.hasPrefix(".") {
            try? fm.removeItem(at: item)
        }
    }

    // MARK: 되돌리기

    /// 복원을 예약한다. 실제 복원은 다음 실행 맨 처음(`applyPendingRestore`)에 한다 —
    /// 지금은 저장소가 열려 있어서 파일을 바꾸면 그쪽이 덮어쓴다.
    func stageRestore(_ snapshot: LeeoVaultSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        guard manifest(in: directory(of: snapshot)) != nil else { throw LeeoVaultError.notFound }
        try JSONEncoder().encode(["id": snapshot.id]).write(to: pendingURL, options: .atomic)
    }

    var pendingRestoreID: String? {
        guard let data = try? Data(contentsOf: pendingURL) else { return nil }
        return (try? JSONDecoder().decode([String: String].self, from: data))?["id"]
    }

    func cancelPendingRestore() {
        try? fm.removeItem(at: pendingURL)
    }

    /// 예약된 복원이 있으면 한다. 먼저 지금 상태를 `beforeRestore` 로 떠 두므로 복원도 되돌릴 수 있다.
    /// 복원이 도중에 실패하면 그 직전 상태로 다시 돌려놓는다.
    @discardableResult
    func applyPendingRestore() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let id = pendingRestoreID else { return false }
        cancelPendingRestore()   // 복원하다 죽어도 매번 다시 하지 않게, 먼저 지운다
        guard let target = snapshots().first(where: { $0.id == id }) else { return false }
        guard let before = try? take(.beforeRestore) else { return false }   // 되돌릴 길이 없으면 손대지 않는다
        do {
            try restore(target)
            updateState { $0.lastRestoredID = target.id; $0.lastRestoredAt = Date() }
            return true
        } catch {
            try? restore(before)
            return false
        }
    }

    func restore(_ snap: LeeoVaultSnapshot) throws {
        let dir = directory(of: snap)
        for root in roots {
            if root.key.hasPrefix("group/"), !snap.groups.contains(String(root.key.dropFirst(6))) { continue }
            try clear(root.url, excluded: root.excluded, prefix: "")
            guard snap.roots.contains(root.key) else { continue }   // 그때 없던 폴더 → 비운 채로
            let src = dir.appendingPathComponent("data", isDirectory: true).appendingPathComponent(root.key, isDirectory: true)
            try fm.createDirectory(at: root.url, withIntermediateDirectories: true)
            try copyContents(of: src, to: root.url, excluded: root.excluded, prefix: "")
        }
        for (domain, store) in defaults {
            let file = dir.appendingPathComponent("defaults", isDirectory: true)
                .appendingPathComponent(Self.fileName(domain) + ".plist")
            if let data = try? Data(contentsOf: file),
               let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                store.setPersistentDomain(dict, forName: domain)
            } else if groups.contains(domain) ? snap.groups.contains(domain) : true {   // 그때 몰랐던 그룹은 건드리지 않는다
                store.removePersistentDomain(forName: domain)
            }
            store.synchronize()
        }
    }

    private func clear(_ dir: URL, excluded: Set<String>, prefix: String) throws {
        for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            let rel = prefix + item.lastPathComponent
            if excluded.contains(rel) { continue }
            if excluded.contains(where: { $0.hasPrefix(rel + "/") }) {
                try clear(item, excluded: excluded, prefix: rel + "/")
            } else {
                try fm.removeItem(at: item)
            }
        }
    }

    // MARK: 파일로 묶기 · 풀기

    /// 한 벌을 파일 하나(.leeobackup, Apple Archive + LZFSE)로 묶는다.
    func archive(_ snap: LeeoVaultSnapshot, to file: URL) throws {
        try? fm.removeItem(at: file)
        guard let out = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .writeOnly,
                                                     options: [.create, .truncate],
                                                     permissions: FilePermissions(rawValue: 0o644)) else {
            throw LeeoVaultError.unreadableArchive
        }
        defer { try? out.close() }
        guard let comp = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: out) else {
            throw LeeoVaultError.unreadableArchive
        }
        defer { try? comp.close() }
        guard let enc = ArchiveStream.encodeStream(writingTo: comp),
              let keys = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,MOD,FLG,MTM") else {
            throw LeeoVaultError.unreadableArchive
        }
        defer { try? enc.close() }
        try enc.writeDirectoryContents(archiveFrom: FilePath(directory(of: snap).path), keySet: keys)
    }

    /// 묶음 파일을 풀어 금고에 한 벌로 넣는다. 그 안의 기록(날짜 · 버전)은 그대로 두고 종류만 바꾼다.
    func unarchive(_ file: URL, as reason: LeeoVaultSnapshot.Reason) throws -> LeeoVaultSnapshot {
        lock.lock(); defer { lock.unlock() }
        let work = snapshotsDir.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        do {
            guard let input = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .readOnly, options: [],
                                                           permissions: FilePermissions(rawValue: 0o644)) else {
                throw LeeoVaultError.unreadableArchive
            }
            defer { try? input.close() }
            guard let dec = ArchiveByteStream.decompressionStream(readingFrom: input) else { throw LeeoVaultError.unreadableArchive }
            defer { try? dec.close() }
            guard let decode = ArchiveStream.decodeStream(readingFrom: dec) else { throw LeeoVaultError.unreadableArchive }
            defer { try? decode.close() }
            guard let extract = ArchiveStream.extractStream(extractingTo: FilePath(work.path),
                                                            flags: [.ignoreOperationNotPermitted]) else {
                throw LeeoVaultError.unreadableArchive
            }
            defer { try? extract.close() }
            _ = try ArchiveStream.process(readingFrom: decode, writingTo: extract)
        }
        guard let inner = manifest(in: work) else { throw LeeoVaultError.unreadableArchive }
        let snap = LeeoVaultSnapshot(id: Self.makeID(Date(), reason), createdAt: inner.createdAt,
                                     appVersion: inner.appVersion, reason: reason, device: inner.device,
                                     bytes: inner.bytes, roots: inner.roots, defaults: inner.defaults,
                                     groups: inner.groups)
        try writeManifest(snap, in: work)
        try fm.moveItem(at: work, to: snapshotsDir.appendingPathComponent(snap.id, isDirectory: true))
        prune()
        return snap
    }

    // MARK: 도우미

    static func makeID(_ date: Date, _ reason: LeeoVaultSnapshot.Reason) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(f.string(from: date))-\(reason.rawValue)-\(UUID().uuidString.prefix(4))"
    }

    static func fileName(_ domain: String) -> String {
        domain.replacingOccurrences(of: "/", with: "_")
    }

    static func size(of dir: URL) -> Int64 {
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        while let url = e?.nextObject() as? URL {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

// MARK: - 앱이 쓰는 입구

public enum LeeoVault {
    nonisolated(unsafe) static var store: LeeoVaultStore?
    nonisolated(unsafe) static var cloudContainer: String?
    /// 같은 실행에서 iCloud 올리기가 겹치지 않게
    nonisolated(unsafe) static var uploading = false

    /// iCloud 에 한 벌로 올리는 상한. CloudKit 에셋 한도(250MB) 안쪽으로 둔다.
    public static let cloudLimit: Int64 = 200 * 1024 * 1024

    /// 앱 시작 맨 처음에 한 번. `LeeoKit.bootstrap` 이 부른다.
    ///   1. 예약된 복원이 있으면 한다 (저장소가 열리기 전이라 안전하다)
    ///   2. 업데이트 직후면 "업데이트 직전" 상태를 떠 둔다 — 새 버전의 구조 이전이 손대기 전의 기록
    ///   3. 아니면 하루 한 번 떠 둔다
    ///   4. iCloud 로 하루 한 번 올린다 (뒤에서)
    public static func start<Spec: LeeoAppSpec>(_ spec: Spec.Type) {
        guard store == nil, !LeeoKit.isRunningUnitTests else { return }
        let container = Spec.vaultUsesICloud ? Spec.feedback.containerIdentifier : nil
        start(appGroups: Spec.appGroups, cloudContainer: container)
    }

    public static func start(appGroups: [String], cloudContainer: String?) {
        guard store == nil, let s = makeStore(appGroups: appGroups) else { return }
        store = s
        self.cloudContainer = cloudContainer
        s.applyPendingRestore()

        let current = s.appVersion
        let last = s.state().lastVersion
        let newest = s.snapshots().first { $0.reason == .daily || $0.reason == .update }
        if let last, last != current {
            try? s.take(.update)
        } else if newest.map({ Date().timeIntervalSince($0.createdAt) > 20 * 3600 }) ?? true {
            try? s.take(.daily)
        }
        s.updateState { $0.lastVersion = current }

        Task.detached(priority: .background) {
            try? await uploadIfDue()
        }
    }

    static func makeStore(appGroups: [String]) -> LeeoVaultStore? {
        let fm = FileManager.default
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first,
              let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var base = library.appendingPathComponent("LeeoVault", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        // 이 기기 금고는 기기 백업에서 뺀다 — 원본은 이미 백업되고, 복제본까지 올리면 사용자 iCloud 용량만 몇 배로 든다
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)

        var roots = [LeeoVaultRoot(key: "home/Documents", url: docs),
                     LeeoVaultRoot(key: "home/Application Support", url: support)]
        var defaults: [(String, UserDefaults)] = []
        if let id = Bundle.main.bundleIdentifier { defaults.append((id, .standard)) }
        var groups: [String] = []
        for g in appGroups {
            guard let url = fm.containerURL(forSecurityApplicationGroupIdentifier: g) else { continue }
            groups.append(g)
            roots.append(LeeoVaultRoot(key: "group/\(g)", url: url,
                                       excluded: ["Library/Caches", "Library/Preferences", "Library/LeeoVault"]))
            if let d = UserDefaults(suiteName: g) { defaults.append((g, d)) }
        }
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        return LeeoVaultStore(base: base, roots: roots, groups: groups, defaults: defaults,
                              appVersion: version, device: deviceName)
    }

    static var deviceName: String {
        #if canImport(UIKit) && !os(watchOS)
        guard Thread.isMainThread else { return "iPhone" }
        return MainActor.assumeIsolated { UIDevice.current.model }
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    // MARK: 화면에서 쓰는 것

    public static var isStarted: Bool { store != nil }
    public static var snapshots: [LeeoVaultSnapshot] { store?.snapshots() ?? [] }
    public static var pendingRestoreID: String? { store?.pendingRestoreID }
    public static var lastRestoredAt: Date? { store?.state().lastRestoredAt }
    public static var supportsICloud: Bool { cloudContainer != nil }
    public static var lastUpload: Date? { store?.state().lastUpload }
    public static var cloudNote: String? { store?.state().cloudNote }

    public static var iCloudEnabled: Bool {
        get { store?.state().cloudEnabled ?? false }
        set { store?.updateState { $0.cloudEnabled = newValue } }
    }

    @discardableResult
    public static func backupNow() throws -> LeeoVaultSnapshot {
        guard let s = store else { throw LeeoVaultError.notStarted }
        return try s.take(.manual)
    }

    public static func stageRestore(_ snap: LeeoVaultSnapshot) throws {
        guard let s = store else { throw LeeoVaultError.notStarted }
        try s.stageRestore(snap)
    }

    public static func cancelPendingRestore() { store?.cancelPendingRestore() }

    /// 내보낼 파일을 임시 폴더에 만든다. 이름: "<앱> 백업 2026-11-03.leeobackup"
    public static func exportFile(_ snap: LeeoVaultSnapshot, appName: String) throws -> URL {
        guard let s = store else { throw LeeoVaultError.notStarted }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        let name = "\(appName) \(f.string(from: snap.createdAt)).leeobackup"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try s.archive(snap, to: url)
        return url
    }

    public static func importFile(_ url: URL) throws -> LeeoVaultSnapshot {
        guard let s = store else { throw LeeoVaultError.notStarted }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // 파일 앱의 원본을 직접 풀지 않고 복사본을 푼다 (iCloud Drive 에서 아직 안 받은 파일도 여기서 받아진다)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            do { try FileManager.default.copyItem(at: readURL, to: local) } catch { copyError = error }
        }
        if let e = coordError ?? copyError { throw e }
        defer { try? FileManager.default.removeItem(at: local) }
        return try s.unarchive(local, as: .imported)
    }
}

// MARK: - iCloud

public struct LeeoVaultCloudBackup: Identifiable, Hashable, Sendable {
    public let id: String          // 레코드 이름
    public let createdAt: Date
    public let appVersion: String
    public let device: String
    public let bytes: Int64
}

#if canImport(CloudKit)
extension LeeoVault {
    static let recordType = "LeeoBackup"
    /// 앱마다 칸 세 개를 돌려 쓴다. 이름이 정해져 있어 조회(쿼리 · 인덱스) 없이 ID 로 바로 가져온다 —
    /// 새 폰에서 처음 열어도 어느 레코드를 찾을지 안다.
    static let slots = 3

    static func slotIDs() -> [CKRecord.ID] {
        let app = Bundle.main.bundleIdentifier ?? "app"
        return (0..<slots).map { CKRecord.ID(recordName: "\(recordType).\(app).\($0)") }
    }

    static func database() async throws -> CKDatabase {
        guard let id = cloudContainer else { throw LeeoVaultError.cloudUnavailable }
        let container = CKContainer(identifier: id)
        guard try await container.accountStatus() == .available else { throw LeeoVaultError.cloudUnavailable }
        return container.privateCloudDatabase
    }

    /// 하루가 지났으면 최신 한 벌을 올린다.
    static func uploadIfDue() async throws {
        guard let s = store, cloudContainer != nil, s.state().cloudEnabled else { return }
        if let last = s.state().lastUpload, Date().timeIntervalSince(last) < 20 * 3600 { return }
        try await uploadLatest()
    }

    /// 가장 최근 한 벌을 iCloud 에 올린다. 칸 세 개 중 비었거나 가장 오래된 칸에 덮어쓴다.
    public static func uploadLatest() async throws {
        guard let s = store else { throw LeeoVaultError.notStarted }
        guard !uploading else { return }
        uploading = true
        defer { uploading = false }
        guard let snap = s.snapshots().first(where: { $0.reason != .beforeRestore }) else { return }
        let db = try await database()

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(snap.id).leeobackup")
        defer { try? FileManager.default.removeItem(at: file) }
        try s.archive(snap, to: file)
        let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard size <= cloudLimit else {
            s.updateState { $0.cloudNote = LeeoVaultError.tooLarge(size).errorDescription }
            throw LeeoVaultError.tooLarge(size)
        }

        let existing = try await fetchSlots(db, withAsset: false)
        let slot = slotIDs().first { id in !existing.contains { $0.recordID == id } }
            ?? existing.min { ($0["createdAt"] as? Date ?? .distantPast) < ($1["createdAt"] as? Date ?? .distantPast) }!.recordID
        let record = CKRecord(recordType: recordType, recordID: slot)
        record["appId"] = Bundle.main.bundleIdentifier
        record["createdAt"] = snap.createdAt
        record["appVersion"] = snap.appVersion
        record["device"] = snap.device
        record["bytes"] = snap.bytes
        record["archive"] = CKAsset(fileURL: file)
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        s.updateState { $0.lastUpload = Date(); $0.lastUploadedID = snap.id; $0.cloudNote = nil }
    }

    static func fetchSlots(_ db: CKDatabase, withAsset: Bool) async throws -> [CKRecord] {
        let keys: [CKRecord.FieldKey]? = withAsset ? nil : ["createdAt", "appVersion", "device", "bytes"]
        let result = try await db.records(for: slotIDs(), desiredKeys: keys)
        return result.values.compactMap { try? $0.get() }
    }

    /// iCloud 에 있는 이 앱의 백업 (새 것부터). 다른 기기에서 올린 것도 나온다.
    public static func cloudBackups() async throws -> [LeeoVaultCloudBackup] {
        let db = try await database()
        return try await fetchSlots(db, withAsset: false).map {
            LeeoVaultCloudBackup(id: $0.recordID.recordName,
                                 createdAt: $0["createdAt"] as? Date ?? .distantPast,
                                 appVersion: $0["appVersion"] as? String ?? "?",
                                 device: $0["device"] as? String ?? "",
                                 bytes: $0["bytes"] as? Int64 ?? 0)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// iCloud 백업을 받아 이 기기 금고에 한 벌로 넣는다. 그다음 `stageRestore` 로 되돌린다.
    public static func download(_ backup: LeeoVaultCloudBackup) async throws -> LeeoVaultSnapshot {
        guard let s = store else { throw LeeoVaultError.notStarted }
        let db = try await database()
        let record = try await db.record(for: CKRecord.ID(recordName: backup.id))
        guard let url = (record["archive"] as? CKAsset)?.fileURL else { throw LeeoVaultError.notFound }
        return try s.unarchive(url, as: .cloud)
    }
}
#endif
