//
//  LeeoFeedbackInboxView.swift
//  LeeoKit
//
//  개발자 전용 피드백 인박스 (마스터 모드) — CloudKit Public DB의 피드백 레코드를
//  앱 안에서 바로 확인한다. 진입점 노출(마스터 모드 게이트)은 앱이 책임진다.
//
//  ⚠️ 다른 사용자의 레코드를 읽으려면 CloudKit Dashboard에서 admin 역할을 만들어
//  read 권한과 본인 userRecordName을 등록해야 한다.
//

import SwiftUI

public struct LeeoFeedbackInboxView<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var theme

    @State private var records: [LeeoFeedbackService.FeedbackRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var userRecordName: String?
    @State private var didCopyId = false
    @State private var pendingDelete: LeeoFeedbackService.FeedbackRecord?
    // 새 피드백 푸시 알림 (CKQuerySubscription — 서버 기준 상태)
    @State private var notifyEnabled = false
    @State private var notifyLoaded = false

    private var service: LeeoFeedbackService { LeeoFeedbackService(spec: Spec.self) }

    public init() {}

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("yyMMdjmm")
        return f
    }

    public var body: some View {
        List {
            // 새 피드백 푸시 알림 토글
            Section {
                Toggle(isOn: Binding(
                    get: { notifyEnabled },
                    set: { setNotify($0) }
                )) {
                    Label(L("새 피드백 알림", comment: "Feedback inbox: push notification toggle"),
                          systemImage: "bell.badge")
                }
                .disabled(!notifyLoaded)
            } footer: {
                Text(L("새 피드백이 접수되면 이 기기로 푸시 알림이 와요. CloudKit admin 역할의 read 권한 설정 후에 동작해요.", comment: "Feedback inbox: push notification footer"))
                    .font(.body)
            }

            if isLoading && records.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("불러오는 중…", comment: "Feedback inbox loading"))
                            .font(.body)
                            .foregroundColor(theme.textMuted)
                    }
                }
            } else if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.red)
                } footer: {
                    Text(L("권한 오류라면 CloudKit Dashboard에서 admin 역할에 read 권한과 아래 사용자 ID를 등록했는지 확인하세요.", comment: "Feedback inbox permission hint"))
                        .font(.body)
                }
            } else if records.isEmpty {
                Section {
                    Text(L("아직 접수된 피드백이 없어요", comment: "Feedback inbox empty"))
                        .font(.body)
                        .foregroundColor(theme.textMuted)
                }
            } else {
                Section {
                    ForEach(records) { record in
                        recordRow(record)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    toggleDone(record)
                                } label: {
                                    Label(record.isDone
                                          ? L("완료 해제", comment: "Feedback inbox: unmark done")
                                          : L("완료 표시", comment: "Feedback inbox: mark done"),
                                          systemImage: record.isDone ? "arrow.uturn.backward" : "checkmark")
                                }
                                .tint(record.isDone ? .orange : .green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = record
                                } label: {
                                    Label(L("삭제", comment: "Delete"), systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(String(format: L("접수 %d건 · 완료 %d건", comment: "Feedback inbox count header (total, done)"),
                                records.count, records.filter(\.isDone).count))
                } footer: {
                    Text(L("왼쪽으로 밀면 삭제, 오른쪽으로 밀면 완료 표시. 완료/삭제는 CloudKit admin 역할에 쓰기 권한이 있어야 반영돼요.", comment: "Feedback inbox actions footer"))
                        .font(.body)
                }
            }

            // Dashboard admin 역할 등록용 내 사용자 ID
            if let userRecordName {
                Section {
                    Button {
                        copyToPasteboard(userRecordName)
                        withAnimation { didCopyId = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { didCopyId = false }
                        }
                    } label: {
                        HStack {
                            Text(userRecordName)
                                .font(.caption.monospaced())
                                .foregroundColor(theme.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: didCopyId ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(didCopyId ? .green : theme.accent)
                        }
                    }
                } header: {
                    Text(L("내 사용자 ID", comment: "Feedback inbox: my user record id header"))
                } footer: {
                    Text(L("CloudKit Dashboard의 admin 역할에 이 ID를 추가하면 앱에서 모든 피드백을 읽을 수 있어요. 탭하면 복사됩니다.", comment: "Feedback inbox: user record id footer"))
                        .font(.body)
                }
            }
        }
        .navigationTitle(L("접수된 피드백", comment: "Feedback inbox title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable { await load() }
        .task { await load() }
        .alert(
            L("이 피드백을 삭제할까요?", comment: "Feedback inbox delete confirm title"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button(L("삭제", comment: "Delete"), role: .destructive) {
                if let record = pendingDelete { deleteRecord(record) }
                pendingDelete = nil
            }
            Button(L("취소", comment: "Cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L("서버에서 완전히 삭제되며 되돌릴 수 없어요.", comment: "Feedback inbox delete confirm message"))
        }
    }

    private func recordRow(_ record: LeeoFeedbackService.FeedbackRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let type = LeeoFeedbackType(rawValue: record.type)
                Image(systemName: record.isDone ? "checkmark.circle.fill" : (type?.icon ?? "ellipsis.bubble"))
                    .font(.caption)
                    .foregroundColor(record.isDone ? .green : theme.accent)
                    .accessibilityHidden(true)
                Text(type?.localizedName ?? record.type)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(record.isDone ? theme.textMuted : theme.accent)
                if record.isDone {
                    Text(L("완료", comment: "Feedback inbox: done badge"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
                Spacer()
                if let createdAt = record.createdAt {
                    Text(dateFormatter.string(from: createdAt))
                        .font(.caption2)
                        .foregroundColor(theme.textFaint)
                }
            }

            Text(record.message)
                .font(.body)
                .foregroundColor(record.isDone ? theme.textMuted : theme.text)
                .textSelection(.enabled)

            Text(record.deviceInfo.isEmpty
                 ? "\(record.appVersion) · \(record.platform) · \(record.locale)"
                 : "\(record.deviceInfo) · \(record.locale)")
                .font(.caption2)
                .foregroundColor(theme.textFaint)
        }
        .padding(.vertical, 4)
    }

    private func copyToPasteboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if userRecordName == nil {
            userRecordName = await service.currentUserRecordName()
        }
        if !notifyLoaded {
            notifyEnabled = await service.isNewFeedbackNotificationEnabled()
            notifyLoaded = true
        }
        do {
            records = try await service.fetchAll()
        } catch {
            print("❌ [LeeoFeedbackInboxView.load] \(error)")
            errorMessage = String(format: L("피드백을 불러오지 못했어요: %@", comment: "Feedback inbox load error"), error.localizedDescription)
        }
    }

    /// 새 피드백 푸시 알림 켜기/끄기 — CKQuerySubscription 등록/해제.
    private func setNotify(_ enabled: Bool) {
        Task {
            do {
                if enabled {
                    try await service.enableNewFeedbackNotifications()
                } else {
                    try await service.disableNewFeedbackNotifications()
                }
                notifyEnabled = enabled
            } catch {
                print("❌ [LeeoFeedbackInboxView.setNotify] \(error)")
                errorMessage = String(format: L("처리하지 못했어요: %@", comment: "Feedback inbox action error"), error.localizedDescription)
            }
        }
    }

    /// 완료/미완료 토글 — 서버 반영 후 로컬 목록 갱신. 실패 시 에러 표시(권한 안내 포함).
    private func toggleDone(_ record: LeeoFeedbackService.FeedbackRecord) {
        Task {
            do {
                try await service.setDone(recordName: record.id, done: !record.isDone)
                if let index = records.firstIndex(where: { $0.id == record.id }) {
                    records[index].status = record.isDone ? nil : "done"
                }
            } catch {
                print("❌ [LeeoFeedbackInboxView.toggleDone] \(error)")
                errorMessage = String(format: L("처리하지 못했어요: %@", comment: "Feedback inbox action error"), error.localizedDescription)
            }
        }
    }

    /// 서버에서 레코드 삭제 후 로컬 목록에서 제거.
    private func deleteRecord(_ record: LeeoFeedbackService.FeedbackRecord) {
        Task {
            do {
                try await service.delete(recordName: record.id)
                records.removeAll { $0.id == record.id }
            } catch {
                print("❌ [LeeoFeedbackInboxView.deleteRecord] \(error)")
                errorMessage = String(format: L("처리하지 못했어요: %@", comment: "Feedback inbox action error"), error.localizedDescription)
            }
        }
    }
}
