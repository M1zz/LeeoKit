//
//  LeeoRoadmap.swift
//  LeeoKit
//
//  **앞으로 만들 것**을 사용자에게 보여 준다. 만들고 있는 것 · 다음에 만들 것 · 최근에 나온 것.
//
//  원본은 앱의 Spec 한 곳이다(`LeeoAppSpec.roadmap`). 개발하다 "이건 다음에" 가 생기면 거기에 한 줄을 더하고,
//  내보내면 `.shipped("버전")` 으로 옮긴다. 화면 · 번역은 따로 손대지 않는다(문구는 앱 카탈로그로 번역된다).
//
//  Spec 에서:
//      static var roadmap: [LeeoRoadmapItem] {[
//          .init(id: "sync.stable", status: .planned,
//                title: NSLocalizedString("기기 간 동기화 정식판", comment: "Roadmap item"),
//                detail: NSLocalizedString("지금은 베타예요. 더 안정되게 다듬어 정식으로 열어요.", comment: "Roadmap item detail")),
//      ]}
//
//  설정에서:
//      NavigationLink(LeeoRoadmapText.entry) { LeeoRoadmapView<MyAppSpec>(onSuggest: { showFeedback = true }) }
//

import SwiftUI

// MARK: - 항목

public struct LeeoRoadmapItem: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// 지금 만들고 있다(다음 업데이트에 들어갈 것 포함).
        case building
        /// 다음에 만들 것.
        case planned
        /// 나왔다. 몇 버전에서.
        case shipped(String)
    }

    /// 앱 안에서 고정된 이름("sync.stable"). 문구가 바뀌어도 같은 항목이다.
    public let id: String
    public let status: Status
    /// 화면에 보이는 이름. 앱이 `NSLocalizedString` 으로 넘긴다.
    public let title: String
    public let detail: String?

    public init(id: String, status: Status, title: String, detail: String? = nil) {
        self.id = id
        self.status = status
        self.title = title
        self.detail = detail
    }
}

public extension Array where Element == LeeoRoadmapItem {
    var building: [LeeoRoadmapItem] { filter { $0.status == .building } }
    var planned: [LeeoRoadmapItem] { filter { $0.status == .planned } }
    /// 나온 것. 최근 것 몇 개만 보여 준다(오래된 것은 릴리즈 노트의 몫).
    func shipped(limit: Int = 5) -> [LeeoRoadmapItem] {
        Array(filter { if case .shipped = $0.status { return true }; return false }.prefix(limit))
    }
}

// MARK: - 앱이 쓰는 문구

public enum LeeoRoadmapText {
    /// 설정 행 이름.
    public static var entry: String { L("앞으로 만들 기능", comment: "Roadmap: settings entry") }
}

// MARK: - 화면

public struct LeeoRoadmapView<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var theme
    private let items: [LeeoRoadmapItem]
    private let onSuggest: (() -> Void)?

    /// - Parameter onSuggest: "이런 기능이 있으면 좋겠어요" 를 누르면 부른다(보통 피드백 창). nil 이면 단추가 없다.
    public init(onSuggest: (() -> Void)? = nil) {
        self.items = Spec.roadmap
        self.onSuggest = onSuggest
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("지금 만들고 있는 것과 다음에 만들 것이에요. 순서와 시기는 바뀔 수 있어요.",
                       comment: "Roadmap: explanation at the top"))
                    .font(.subheadline)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if items.isEmpty {
                    Text(L("아직 적어 둔 계획이 없어요.", comment: "Roadmap: empty"))
                        .font(.body)
                        .foregroundStyle(theme.textMuted)
                }
                section(L("만들고 있어요", comment: "Roadmap section: in progress"),
                        symbol: "hammer.fill", items.building)
                section(L("다음에 만들어요", comment: "Roadmap section: planned"),
                        symbol: "calendar", items.planned)
                section(L("최근에 나왔어요", comment: "Roadmap section: recently shipped"),
                        symbol: "checkmark.seal.fill", items.shipped())

                if let onSuggest {
                    Button(action: onSuggest) {
                        Label(L("이런 기능이 있으면 좋겠어요", comment: "Roadmap: suggest a feature button"),
                              systemImage: "lightbulb")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous)
                                .fill(theme.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(LeeoRoadmapText.entry)
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, _ list: [LeeoRoadmapItem]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(theme.text)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 16) }
                        row(item)
                    }
                }
                .background(RoundedRectangle(cornerRadius: theme.radiusSm + 4, style: .continuous).fill(theme.surface))
            }
        }
    }

    private func row(_ item: LeeoRoadmapItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.text)
                Spacer(minLength: 8)
                if case .shipped(let version) = item.status {
                    Text(String(format: L("%@에 나옴", comment: "Roadmap: shipped in version %@"), version))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textMuted)
                }
            }
            if let detail = item.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
