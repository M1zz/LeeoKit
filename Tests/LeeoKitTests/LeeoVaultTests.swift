import XCTest
@testable import LeeoKit

final class LeeoVaultTests: XCTestCase {
    private var tmp: URL!
    private var docs: URL { tmp.appendingPathComponent("home/Documents") }
    private var support: URL { tmp.appendingPathComponent("home/Support") }
    private var group: URL { tmp.appendingPathComponent("group") }
    private let suite = "test.leeovault.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        for d in [docs, support, group.appendingPathComponent("Library/Caches")] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeStore(version: String = "1.0 (1)") -> LeeoVaultStore {
        LeeoVaultStore(
            base: tmp.appendingPathComponent("vault"),
            roots: [LeeoVaultRoot(key: "home/Documents", url: docs),
                    LeeoVaultRoot(key: "home/Application Support", url: support),
                    LeeoVaultRoot(key: "group/g", url: group, excluded: ["Library/Caches"])],
            groups: ["g"], defaults: [(suite, defaults)], appVersion: version, device: "Test")
    }

    private func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testSnapshotThenRestoreBringsBackFilesAndDefaults() throws {
        let store = makeStore()
        try write("기록 1", docs.appendingPathComponent("notes.json"))
        try write("db", support.appendingPathComponent("default.store"))
        try write("widget", group.appendingPathComponent("shared.json"))
        defaults.set("값", forKey: "memo")
        let snap = try store.take(.manual)

        // 기록이 깨지고, 새 파일이 생기고, 설정이 바뀌었다
        try write("깨짐", docs.appendingPathComponent("notes.json"))
        try write("새것", docs.appendingPathComponent("extra.json"))
        try FileManager.default.removeItem(at: support.appendingPathComponent("default.store"))
        defaults.set("다른 값", forKey: "memo")

        try store.restore(snap)
        XCTAssertEqual(read(docs.appendingPathComponent("notes.json")), "기록 1")
        XCTAssertNil(read(docs.appendingPathComponent("extra.json")), "백업 뒤에 생긴 파일은 사라진다")
        XCTAssertEqual(read(support.appendingPathComponent("default.store")), "db")
        XCTAssertEqual(read(group.appendingPathComponent("shared.json")), "widget")
        XCTAssertEqual(defaults.string(forKey: "memo"), "값")
    }

    func testExcludedFoldersAreNeitherCopiedNorCleared() throws {
        let store = makeStore()
        try write("cache", group.appendingPathComponent("Library/Caches/c.bin"))
        let snap = try store.take(.manual)
        let copied = store.directory(of: snap).appendingPathComponent("data/group/g/Library/Caches/c.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
        try store.restore(snap)
        XCTAssertEqual(read(group.appendingPathComponent("Library/Caches/c.bin")), "cache", "캐시는 건드리지 않는다")
    }

    func testPendingRestoreKeepsBeforeRestoreCopy() throws {
        let store = makeStore()
        try write("옛 기록", docs.appendingPathComponent("a.txt"))
        let old = try store.take(.daily)
        try write("새 기록", docs.appendingPathComponent("a.txt"))
        try store.stageRestore(old)
        XCTAssertEqual(store.pendingRestoreID, old.id)

        XCTAssertTrue(store.applyPendingRestore())
        XCTAssertNil(store.pendingRestoreID)
        XCTAssertEqual(read(docs.appendingPathComponent("a.txt")), "옛 기록")

        // 복원도 되돌릴 수 있다
        let before = try XCTUnwrap(store.snapshots().first { $0.reason == .beforeRestore })
        try store.restore(before)
        XCTAssertEqual(read(docs.appendingPathComponent("a.txt")), "새 기록")
    }

    func testArchiveRoundTripKeepsContentAndOriginalDate() throws {
        let store = makeStore()
        try write("기록", docs.appendingPathComponent("sub/a.txt"))
        defaults.set(42, forKey: "n")
        let snap = try store.take(.manual)
        let file = tmp.appendingPathComponent("x.leeobackup")
        try store.archive(snap, to: file)

        try FileManager.default.removeItem(at: docs.appendingPathComponent("sub"))
        defaults.removeObject(forKey: "n")
        let imported = try store.unarchive(file, as: .imported)
        XCTAssertEqual(imported.reason, .imported)
        XCTAssertEqual(imported.createdAt.timeIntervalSince1970, snap.createdAt.timeIntervalSince1970, accuracy: 1)
        try store.restore(imported)
        XCTAssertEqual(read(docs.appendingPathComponent("sub/a.txt")), "기록")
        XCTAssertEqual(defaults.integer(forKey: "n"), 42)
    }

    func testGarbageFileIsRejected() throws {
        let store = makeStore()
        let file = tmp.appendingPathComponent("bad.leeobackup")
        try write("not an archive", file)
        XCTAssertThrowsError(try store.unarchive(file, as: .imported))
        XCTAssertTrue(store.snapshots().isEmpty)
    }

    func testRetentionKeepsNewestPerReason() throws {
        let store = makeStore()
        for i in 0..<6 {
            try store.take(.daily, now: Date(timeIntervalSince1970: TimeInterval(1_000_000 + i * 100_000)))
        }
        try store.take(.update)
        let dailies = store.snapshots().filter { $0.reason == .daily }
        XCTAssertEqual(dailies.count, LeeoVaultStore.keep[.daily])
        XCTAssertEqual(store.snapshots().filter { $0.reason == .update }.count, 1, "다른 종류는 밀어내지 않는다")
    }

    func testFolderMissingAtSnapshotIsClearedOnRestore() throws {
        try FileManager.default.removeItem(at: support)
        let store = makeStore()
        let snap = try store.take(.manual)
        try write("나중에 생김", support.appendingPathComponent("x"))
        try store.restore(snap)
        XCTAssertNil(read(support.appendingPathComponent("x")))
    }
}
