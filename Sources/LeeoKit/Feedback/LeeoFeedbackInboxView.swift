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
    // 새 피드백 로컬 알림 (백그라운드 새로고침 — 이 기기 기준 상태)
    @State private var notifyEnabled = false
    @State private var notifyLoaded = false

    private var service: LeeoFeedbackService { LeeoFeedbackService(spec: Spec.self) }

    public init() {}

    // MARK: - 활성/완료 분리 (완료 상태는 로컬 저장, isDone으로 판별)

    /// 활성(미완료) 피드백 — 메인 목록에 노출.
    private var activeRecords: [LeeoFeedbackService.FeedbackRecord] {
        records.filter { !$0.isDone }
    }
    /// 완료된 피드백 — 메인 목록에서 감추고 "완료된 피드백" 월별 모아보기로 이동.
    private var doneRecords: [LeeoFeedbackService.FeedbackRecord] {
        records.filter { $0.isDone }
    }

    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let records: [LeeoFeedbackService.FeedbackRecord]
    }

    /// 완료된 피드백을 접수(생성)일 기준으로 월별 그룹핑 (최신 월 먼저).
    /// records가 이미 최신순이라 각 그룹 내부도 최신순이 유지된다.
    private var doneMonthGroups: [MonthGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: doneRecords) { rec -> String in
            guard let date = rec.createdAt else { return "0000-00" }
            let c = cal.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        let monthFormatter = DateFormatter()
        monthFormatter.locale = .current
        monthFormatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return grouped.keys.sorted(by: >).map { key in
            let recs = grouped[key] ?? []
            let title: String
            if key == "0000-00" {
                title = L("날짜 없음", comment: "Feedback completed: no date group")
            } else if let date = recs.first?.createdAt {
                title = monthFormatter.string(from: date)
            } else {
                title = key
            }
            return MonthGroup(id: key, title: title, records: recs)
        }
    }

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
                Text(L("새 피드백이 접수되면 이 기기로 로컬 알림이 와요. 실시간은 아니고, iOS 백그라운드 새로고침 주기와 앱을 열 때 확인해요. CloudKit admin 역할의 read 권한 설정 후에 동작해요.", comment: "Feedback inbox: push notification footer"))
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
                // 활성(미완료) 피드백만 노출 — 완료 표시하면 아래 "완료된 피드백" 월별 모아보기로 이동.
                Section {
                    if activeRecords.isEmpty {
                        Text(L("활성 피드백이 없어요. 모두 완료했어요 🎉", comment: "Feedback inbox: no active feedback"))
                            .font(.body)
                            .foregroundColor(theme.textMuted)
                    } else {
                        ForEach(activeRecords) { record in
                            recordRow(record)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        toggleDone(record)
                                    } label: {
                                        Label(L("완료 표시", comment: "Feedback inbox: mark done"),
                                              systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingDelete = record
                                    } label: {
                                        Label(L("삭제", comment: "Delete"), systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    Text(String(format: L("받은 피드백 %d건", comment: "Feedback inbox active count header"),
                                activeRecords.count))
                } footer: {
                    Text(L("오른쪽으로 밀면 완료 표시(이 기기에만 저장돼요), 왼쪽으로 밀면 삭제. 삭제는 CloudKit admin 역할에 쓰기 권한이 있어야 반영돼요.", comment: "Feedback inbox actions footer"))
                        .font(.body)
                }

                // 완료된 피드백 — 월별 섹션으로 모아보기 (완료 개수가 있을 때만)
                if !doneRecords.isEmpty {
                    Section {
                        NavigationLink {
                            completedListView
                        } label: {
                            Label(String(format: L("완료된 피드백 %d건 모아보기", comment: "Feedback inbox: completed archive entry"),
                                         doneRecords.count),
                                  systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
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

            // 회신 정보 (사용자가 남긴 경우에만)
            if !record.contactName.isEmpty || !record.contactEmail.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.caption)
                        .foregroundColor(theme.accent)
                        .accessibilityHidden(true)
                    if !record.contactName.isEmpty {
                        Text(record.contactName)
                            .font(.caption)
                            .foregroundColor(theme.textMuted)
                    }
                    if !record.contactEmail.isEmpty,
                       let url = URL(string: "mailto:\(record.contactEmail)") {
                        Link(record.contactEmail, destination: url)
                            .font(.caption)
                    }
                }
            }

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
            notifyEnabled = service.isLocalNotifyEnabled
            notifyLoaded = true
        }
        do {
            records = try await service.fetchAll()
            // 인박스를 열어 확인했으니 현재 목록을 '봄' 처리 — 이미 본 피드백으로 다시 알림 안 오게.
            service.markAllFeedbackSeen(records)
        } catch {
            print("❌ [LeeoFeedbackInboxView.load] \(error)")
            errorMessage = String(format: L("피드백을 불러오지 못했어요: %@", comment: "Feedback inbox load error"), error.localizedDescription)
        }
    }

    /// 새 피드백 로컬 알림 켜기/끄기 — 백그라운드 새로고침 예약/취소.
    private func setNotify(_ enabled: Bool) {
        Task {
            do {
                if enabled {
                    try await service.enableLocalNewFeedbackNotifications()
                } else {
                    service.disableLocalNewFeedbackNotifications()
                }
                notifyEnabled = enabled
            } catch {
                print("❌ [LeeoFeedbackInboxView.setNotify] \(error)")
                errorMessage = String(format: L("처리하지 못했어요: %@", comment: "Feedback inbox action error"), error.localizedDescription)
            }
        }
    }

    /// 완료/미완료 토글 — 이 기기 로컬에 저장(서버 쓰기 없음).
    /// 공개 DB에선 남이 만든 레코드를 수정할 수 없어(WRITE not permitted) 완료 상태는 로컬로 관리한다.
    private func toggleDone(_ record: LeeoFeedbackService.FeedbackRecord) {
        let newDone = !record.isDone
        service.setDoneLocal(recordName: record.id, done: newDone)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index].status = newDone ? "done" : nil
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

    // MARK: - 완료된 피드백 모아보기 (월별 섹션)

    /// 완료 처리된 피드백을 "yyyy년 M월" 섹션으로 묶어 보여준다.
    /// 왼쪽으로 밀어 완료 해제(활성 목록으로 복귀), 오른쪽으로 밀어 삭제.
    @ViewBuilder
    private var completedListView: some View {
        List {
            if doneMonthGroups.isEmpty {
                Section {
                    Text(L("완료된 피드백이 없어요", comment: "Feedback completed archive empty"))
                        .font(.body)
                        .foregroundColor(theme.textMuted)
                }
            } else {
                ForEach(doneMonthGroups) { group in
                    Section {
                        ForEach(group.records) { record in
                            recordRow(record)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        toggleDone(record)
                                    } label: {
                                        Label(L("완료 해제", comment: "Feedback inbox: unmark done"),
                                              systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.orange)
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
                        Text(group.title)
                    }
                }
            }
        }
        .navigationTitle(L("완료된 피드백", comment: "Feedback completed archive title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
}
