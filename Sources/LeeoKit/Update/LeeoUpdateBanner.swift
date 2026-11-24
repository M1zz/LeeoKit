//
//  LeeoUpdateBanner.swift
//  LeeoKit
//
//  새 버전 안내 — 화면 아래의 작은 카드. 막지 않고, 손대지 않으면 잠시 뒤 걷힌다.
//  `.leeoCelebrations` 가 함께 붙인다.
//

import SwiftUI

#if !os(watchOS)
public extension View {
    /// 새 버전이 나왔으면 무엇이 좋아졌는지 아래쪽 카드로 한 번 알린다. `.leeoCelebrations` 를 쓰면 저절로 붙는다.
    func leeoUpdateBanner() -> some View { modifier(LeeoUpdateHost()) }
}

struct LeeoUpdateHost: ViewModifier {
    @State private var release: LeeoStoreRelease?
    @Environment(\.openURL) private var openURL

    /// 손대지 않으면 이만큼 뒤에 걷힌다.
    private static let visibleFor: Duration = .seconds(12)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let release {
                    LeeoUpdateCard(release: release,
                                   onUpdate: { openURL(release.url); self.release = nil },
                                   onClose: { self.release = nil })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4), value: release)
            .task { await check() }
    }

    @MainActor
    private func check() async {
        guard LeeoEngagement.shared.launchCount > 1 else { return }
        // 축하 · 할인 배너가 먼저 뜰 틈을 주고, 그것들이 걷힌 뒤에 조용히 올린다.
        try? await Task.sleep(for: .seconds(4))
        for _ in 0..<30 where LeeoCelebration.shared.current != nil {
            try? await Task.sleep(for: .seconds(1))
        }
        let latest = await LeeoUpdate.latest()
        guard let found = LeeoUpdate.pending(release: latest, installed: LeeoUpdate.installedVersion,
                                             osVersion: ProcessInfo.processInfo.operatingSystemVersion) else { return }
        LeeoUpdate.markShown(found.version)
        release = found
        try? await Task.sleep(for: Self.visibleFor)
        if release == found { release = nil }
    }
}

struct LeeoUpdateCard: View {
    let release: LeeoStoreRelease
    let onUpdate: () -> Void
    let onClose: () -> Void
    @Environment(\.leeoStyle) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LeeoSaleAppIcon(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("새 버전이 나왔어요", comment: "Update card: title when a newer app version is on the App Store"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                if !release.notes.isEmpty {
                    Text(String(format: L("버전 %@에서 좋아진 점", comment: "Update card: small heading above the release notes. %@ = version such as 1.0.6"), release.version))
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                    ForEach(Array(release.notes.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(theme.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(String(format: L("버전 %@", comment: "Update card: version line when there are no release notes. %@ = version"), release.version))
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                }
                Button(action: onUpdate) {
                    Text(L("업데이트", comment: "Update card: button that opens the App Store page to update"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("닫기", comment: "Sale banner: close button accessibility label"))
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}
#endif
