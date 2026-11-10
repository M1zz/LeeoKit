//
//  LeeoVaultView.swift
//  LeeoKit
//
//  설정의 "백업 및 복원" 화면. `LeeoSupportSection` 이 행을 넣어 주므로 앱은 따로 할 일이 없다.
//  다른 자리에 두려면: `NavigationLink(LeeoVaultText.entry) { LeeoVaultView(appName: "앱") }`
//

// watchOS 에는 없다 — FileDocument 내보내기가 watchOS 에 없다.
#if !os(watchOS)
import SwiftUI
import UniformTypeIdentifiers

public enum LeeoVaultText {
    public static var entry: String { L("백업 및 복원", comment: "Vault: settings row and screen title") }
}

public struct LeeoVaultView: View {
    private let appName: String

    public init(appName: String) {
        self.appName = appName
    }

    @State private var snapshots: [LeeoVaultSnapshot] = []
    @State private var cloud: [LeeoVaultCloudBackup] = []
    @State private var cloudError: String?
    @State private var cloudOn = LeeoVault.iCloudEnabled
    @State private var pendingID = LeeoVault.pendingRestoreID
    @State private var busy = false
    @State private var message: String?
    @State private var confirmLocal: LeeoVaultSnapshot?
    @State private var confirmCloud: LeeoVaultCloudBackup?
    @State private var exportDoc: LeeoVaultFile?
    @State private var importing = false

    public var body: some View {
        List {
            Section {
                if pendingID != nil {
                    Label(L("앱을 닫았다가 다시 열면 복원이 끝납니다.", comment: "Vault: restore staged, relaunch"),
                          systemImage: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(.orange)
                    Button(L("복원 취소", comment: "Vault: cancel staged restore")) {
                        LeeoVault.cancelPendingRestore()
                        pendingID = nil
                    }
                }
                Button {
                    run { _ = try LeeoVault.backupNow(); return L("백업했어요", comment: "Vault: backup done") }
                } label: {
                    Label(L("지금 백업", comment: "Vault: back up now"), systemImage: "externaldrive.badge.checkmark")
                }
                Button {
                    run {
                        let snap = try LeeoVault.backupNow()
                        exportDoc = LeeoVaultFile(url: try LeeoVault.exportFile(snap, appName: appName))
                        return nil
                    }
                } label: {
                    Label(L("파일로 내보내기", comment: "Vault: export to file"), systemImage: "square.and.arrow.up")
                }
                Button {
                    importing = true
                } label: {
                    Label(L("파일에서 가져오기", comment: "Vault: import from file"), systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text(L("이 기기에 매일, 그리고 업데이트 직전에 자동으로 백업합니다.", comment: "Vault: how local backup works"))
            }

            Section {
                if snapshots.isEmpty {
                    Text(L("아직 백업이 없어요", comment: "Vault: no backups")).foregroundStyle(.secondary)
                }
                ForEach(snapshots) { snap in
                    Button { confirmLocal = snap } label: {
                        row(date: snap.createdAt, detail: reasonText(snap.reason), version: snap.appVersion,
                            current: snap.id == pendingID)
                    }
                }
            } header: {
                Text(L("이 기기의 백업", comment: "Vault: local backups header"))
            }

            if LeeoVault.supportsICloud {
                Section {
                    Toggle(L("iCloud에 자동 백업", comment: "Vault: iCloud auto backup toggle"), isOn: $cloudOn)
                        .onChange(of: cloudOn) { _, on in
                            LeeoVault.iCloudEnabled = on
                            if on { Task { try? await LeeoVault.uploadLatest(); await reload() } }
                        }
                    if let cloudError {
                        Text(cloudError).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(cloud) { item in
                        Button { confirmCloud = item } label: {
                            row(date: item.createdAt, detail: item.device, version: item.appVersion, current: false)
                        }
                    }
                } header: {
                    Text(L("iCloud 백업", comment: "Vault: iCloud backups header"))
                } footer: {
                    Text(L("하루 한 번 내 iCloud에 올려, 폰을 바꾸거나 앱을 지워도 되살릴 수 있습니다.", comment: "Vault: how iCloud backup works"))
                }
            }
        }
        .navigationTitle(LeeoVaultText.entry)
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
        .task { await reload() }
        .refreshable { await reload() }
        .alert(L("이 백업으로 되돌릴까요?", comment: "Vault: confirm restore title"),
               isPresented: Binding(get: { confirmLocal != nil || confirmCloud != nil },
                                    set: { if !$0 { confirmLocal = nil; confirmCloud = nil } })) {
            Button(L("되돌리기", comment: "Vault: restore action"), role: .destructive) {
                let local = confirmLocal, remote = confirmCloud
                run {
                    var snap = local
                    if let remote { snap = try await LeeoVault.download(remote) }
                    if let snap { try LeeoVault.stageRestore(snap); pendingID = snap.id }
                    return L("앱을 닫았다가 다시 열면 복원이 끝납니다.", comment: "Vault: restore staged, relaunch")
                }
            }
        } message: {
            Text(L("지금 상태도 따로 백업해 두므로 언제든 다시 돌아올 수 있어요.", comment: "Vault: restore is reversible"))
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
        .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                      document: exportDoc, contentType: .data,
                      defaultFilename: exportDoc?.url.lastPathComponent) { _ in exportDoc = nil }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            guard case .success(let url) = result else { return }
            run {
                let snap = try LeeoVault.importFile(url)
                confirmLocal = snap
                return nil
            }
        }
    }

    private func row(date: Date, detail: String, version: String, current: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.primary)
                Text([detail, version].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if current { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
    }

    private func reasonText(_ r: LeeoVaultSnapshot.Reason) -> String {
        switch r {
        case .daily: return L("자동", comment: "Vault reason: daily automatic backup")
        case .update: return L("업데이트 직전", comment: "Vault reason: just before an app update")
        case .manual: return L("직접 백업", comment: "Vault reason: user made it")
        case .beforeRestore: return L("복원 직전", comment: "Vault reason: just before a restore")
        case .imported: return L("가져온 파일", comment: "Vault reason: imported from a file")
        case .cloud: return L("iCloud에서 받음", comment: "Vault reason: downloaded from iCloud")
        }
    }

    private func reload() async {
        snapshots = LeeoVault.snapshots
        pendingID = LeeoVault.pendingRestoreID
        guard LeeoVault.supportsICloud else { return }
        do {
            cloud = try await LeeoVault.cloudBackups()
            cloudError = LeeoVault.cloudNote
        } catch {
            cloud = []
            cloudError = (error as? LeeoVaultError)?.errorDescription
                ?? L("iCloud에 로그인하면 사용할 수 있어요.", comment: "Vault: iCloud unavailable")
        }
    }

    private func run(_ work: @escaping () async throws -> String?) {
        busy = true
        Task {
            do {
                message = try await work()
            } catch {
                message = error.localizedDescription
            }
            busy = false
            await reload()
        }
    }
}

/// 내보낼 묶음 파일을 `fileExporter` 에 넘기는 그릇
struct LeeoVaultFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let url: URL

    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}
#endif
