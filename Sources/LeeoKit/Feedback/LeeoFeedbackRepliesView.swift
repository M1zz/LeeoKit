//
//  LeeoFeedbackRepliesView.swift
//  LeeoKit
//
//  이 기기에서 보낸 의견과 거기 달린 답장. 사용자 쪽 화면이다.
//
//  ⚠️ 열면 **서버에서 답장을 다시 읽고**, 다 그린 뒤 읽음으로 적는다. 먼저 읽음으로 적으면
//     방금 도착한 답장이 "새 답장" 표시 없이 섞여 들어온다.
//

import SwiftUI

public struct LeeoFeedbackRepliesView<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var theme

    @State private var items: [LeeoSentFeedback] = []
    /// 이 화면을 열 때 안 읽음이던 것. 읽음으로 적은 뒤에도 이번에는 "새 답장" 으로 보여 준다.
    @State private var freshIDs: Set<String> = []
    @State private var isLoading = false

    private var service: LeeoFeedbackService { LeeoFeedbackService(spec: Spec.self) }

    public init() {}

    public var body: some View {
        Group {
            if items.isEmpty && !isLoading {
                emptyState
            } else {
                List {
                    ForEach(items) { item in
                        row(item)
                            .listRowBackground(theme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(L("보낸 의견", comment: "Sent feedback list title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        items = service.sentFeedback
        await service.refreshReplies()
        let latest = service.sentFeedback
        freshIDs.formUnion(latest.filter(\.hasUnreadReply).map(\.id))
        items = latest
        service.markRepliesSeen()
        isLoading = false
    }

    // MARK: - 한 건

    private func row(_ item: LeeoSentFeedback) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(typeName(item.type))
                    .fontWeight(.semibold)
                    .foregroundColor(theme.accent)
                Spacer(minLength: 8)
                Text(item.sentAt, format: .dateTime.year().month().day())
                    .foregroundColor(theme.textMuted)
            }
            .font(.body)

            Text(item.excerpt)
                .font(.body)
                .foregroundColor(theme.text)
                .lineLimit(3)

            if let reply = item.reply {
                replyBubble(reply, isFresh: freshIDs.contains(item.id))
            } else {
                Text(L("아직 답장이 없어요. 모든 의견은 개발자가 직접 읽어요.", comment: "Sent feedback: no reply yet"))
                    .font(.body)
                    .foregroundColor(theme.textMuted)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func replyBubble(_ reply: String, isFresh: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .accessibilityHidden(true)
                Text(L("개발자 답장", comment: "Sent feedback: developer reply label"))
                    .fontWeight(.semibold)
                if isFresh {
                    Text(L("새 답장", comment: "Sent feedback: new reply badge"))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.accent))
                }
            }
            .font(.body)
            .foregroundColor(theme.accent)

            Text(reply)
                .font(.body)
                .foregroundColor(theme.text)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radiusSm, style: .continuous)
                .fill(theme.accent.opacity(0.1))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundColor(theme.textMuted)
                .accessibilityHidden(true)
            Text(L("이 기기에서 보낸 의견이 없어요", comment: "Sent feedback: empty title"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(theme.text)
            Text(L("의견을 보내면 여기에 남고, 답장도 여기로 와요.", comment: "Sent feedback: empty hint"))
                .font(.body)
                .foregroundColor(theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func typeName(_ raw: String) -> String {
        LeeoFeedbackType(rawValue: raw)?.localizedName ?? raw
    }
}

// MARK: - 설정 행

/// 설정에 두는 "보낸 의견" 행. 안 읽은 답장이 있으면 숫자 배지가 붙는다.
///
/// ⚠️ 보낸 적이 없으면 **행 자체가 없다.** 빈 목록으로 들어가는 문은 설정을 길게 만들 뿐이다.
/// ⚠️ 나타날 때 답장을 한 번 읽는다(`refreshReplies`). 실패해도 장부 값으로 그린다.
public struct LeeoSentFeedbackRow<Spec: LeeoAppSpec>: View {
    private let hasSent: Bool
    @State private var unread: Int

    private var service: LeeoFeedbackService { LeeoFeedbackService(spec: Spec.self) }

    /// ⚠️ 보냈는지는 **처음 그릴 때** 장부에서 바로 읽는다. 빈 `Group` 에 붙인 `.task` 는
    ///    돌지 않아서, 나타난 뒤에 정하려 하면 행이 영영 안 생긴다.
    public init() {
        let service = LeeoFeedbackService(spec: Spec.self)
        self.hasSent = !service.sentFeedback.isEmpty
        self._unread = State(initialValue: service.unreadReplyCount)
    }

    public var body: some View {
        if hasSent {
            NavigationLink(destination: LeeoFeedbackRepliesView<Spec>()) {
                HStack {
                    Label(L("보낸 의견", comment: "Sent feedback list title"),
                          systemImage: "tray.and.arrow.up")
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .accessibilityLabel(String(format: L("새 답장 %d개", comment: "Sent feedback row: unread replies a11y"), unread))
                    }
                }
            }
            // 답장 화면에서 돌아오면 읽음이 반영돼 있어야 한다.
            .onAppear { unread = service.unreadReplyCount }
            .task { unread = await service.refreshReplies() }
        }
    }
}
