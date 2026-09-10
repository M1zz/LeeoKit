//
//  LeeoFamilyView.swift
//  LeeoKit
//
//  "같은 사람이 만든 다른 앱" 화면. 앱 쪽 코드는 설정에 한 줄이면 된다:
//
//      LeeoFamilySettingsRow<MyAppSpec>()
//
//  화면이 지키는 것 세 가지 -
//    1. **자기 자신은 안 보인다.** 이미 쓰고 있는 앱을 권하면 광고가 된다.
//    2. **이야기가 먼저, 목록이 나중.** 지금 쓰는 앱이 등장하는 장면부터 보여 준다.
//    3. **못 받는 것은 못 받는다고 말한다.** 아이폰에서 맥 앱 카드는 그렇게 표시된다.
//    4. **목록과 상세를 나눈다.** 첫 화면은 한 눈에 훑는 줄만 세우고, 긴 글은 눌러서 본다.
//       예전에는 이야기가 통째로 펼쳐진 채 쌓여서 첫 화면이 하염없이 길었다. 무엇이
//       있는지 보려면 끝까지 내려야 했고, 그러느니 아무도 안 내렸다.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 본 화면

public struct LeeoFamilyView<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var style

    private let apps: [LeeoFamilyApp]
    private let mine: [LeeoFamilySynergy]
    private let rest: [LeeoFamilySynergy]

    /// - Parameters:
    ///   - apps: 목록을 직접 넘기고 싶을 때 (기본값은 카탈로그에서 자기 자신을 뺀 것).
    ///   - synergies: 이야기를 직접 넘기고 싶을 때.
    public init(apps: [LeeoFamilyApp]? = nil, synergies: [LeeoFamilySynergy]? = nil) {
        self.apps = apps ?? LeeoFamilyCatalog.others(for: Spec.self)
        if let synergies {
            let me = LeeoFamilyCatalog.currentAppID(Spec.self)
            self.mine = synergies.filter { $0.involves(me) }
            self.rest = synergies.filter { !$0.involves(me) }
        } else {
            self.mine = LeeoFamilyCatalog.synergies(involving: Spec.self)
            self.rest = LeeoFamilyCatalog.synergies(excluding: Spec.self)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero

                if !mine.isEmpty {
                    section(
                        title: L("이렇게 이어집니다", comment: "Family section: stories with this app"),
                        note: L("지금 쓰고 계신 앱이 나오는 장면들입니다.",
                                comment: "Family section note: stories with this app")
                    ) {
                        ForEach(mine) { synergy in
                            NavigationLink(destination: LeeoFamilySynergyDetailView(synergy: synergy)) {
                                LeeoFamilySynergyRow(synergy: synergy)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !apps.isEmpty {
                    section(
                        title: L("다른 앱", comment: "Family section: other apps"),
                        note: nil
                    ) {
                        ForEach(apps) { app in
                            NavigationLink(destination: LeeoFamilyAppDetailView(app: app)) {
                                LeeoFamilyAppCard(app: app)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !rest.isEmpty {
                    section(
                        title: L("다른 조합", comment: "Family section: other combinations"),
                        note: nil
                    ) {
                        ForEach(rest) { synergy in
                            NavigationLink(destination: LeeoFamilySynergyDetailView(synergy: synergy)) {
                                LeeoFamilySynergyRow(synergy: synergy)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(style.bg)
        .navigationTitle(L("함께 쓰는 앱", comment: "Family screen title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 조각

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(apps.prefix(4)) { app in
                    LeeoFamilyIcon(app: app, size: 36)
                }
            }
            .accessibilityHidden(true)

            Text(L("혼자 쓰기보다, 이어 쓸 때", comment: "Family hero title"))
                .font(.title2).fontWeight(.semibold)
                .foregroundStyle(style.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(L("같은 사람이 만든 앱들입니다. 겹치는 자리가 있어서, 붙여 두면 하루가 이어집니다.",
                   comment: "Family hero subtitle"))
                .font(.body)
                .foregroundStyle(style.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        note: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(style.text)
                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(style.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
    }

    private var footer: some View {
        Text(L("여기서 아무것도 수집하지 않습니다. 눌러야만 App Store 가 열립니다.",
               comment: "Family footer note"))
            .font(.footnote)
            .foregroundStyle(style.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

// MARK: - 앱 카드

public struct LeeoFamilyAppCard: View {
    @Environment(\.leeoStyle) private var style
    let app: LeeoFamilyApp

    public init(app: LeeoFamilyApp) { self.app = app }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LeeoFamilyIcon(app: app, size: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.body).fontWeight(.semibold)
                    .foregroundStyle(style.text)
                Text(app.tagline)
                    .font(.subheadline)
                    .foregroundStyle(style.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                LeeoFamilyPlatformLine(app: app)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(style.textFaint)
                .padding(.top, 4)
        }
        .padding(16)
        .background(style.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: style.radiusLg))
        .contentShape(Rectangle())
    }
}

// MARK: - 이야기 줄 (목록)

/// 목록에 세우는 이야기 한 줄. **제목과 장면까지만** 보여 주고 나머지는 눌러서 본다.
///
/// 앱 카드(`LeeoFamilyAppCard`)와 같은 모양을 쓴다. 한 화면에 두 가지가 섞여 있는데
/// 생김새가 다르면 "이건 눌리고 저건 안 눌리나" 를 매번 다시 판단하게 된다.
public struct LeeoFamilySynergyRow: View {
    @Environment(\.leeoStyle) private var style
    let synergy: LeeoFamilySynergy

    public init(synergy: LeeoFamilySynergy) { self.synergy = synergy }

    private var cast: [LeeoFamilyApp] {
        synergy.appIDs.compactMap { LeeoFamilyCatalog.app(id: $0) }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 이야기에는 주인공이 여럿이라 아이콘도 여럿이다. 앱 줄은 하나.
            // 그 차이가 두 가지를 가르는 유일한 표시다.
            HStack(spacing: -6) {
                ForEach(cast) { app in
                    // 겹쳐 세우므로 바탕색 테를 두른다. 없으면 겹친 자리에서 두 아이콘이 붙어 보인다.
                    LeeoFamilyIcon(app: app, size: 30, ring: style.surfaceAlt)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(synergy.title)
                    .font(.body).fontWeight(.semibold)
                    .foregroundStyle(style.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(synergy.scene)
                    .font(.subheadline)
                    .foregroundStyle(style.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(style.textFaint)
                .padding(.top, 4)
        }
        .padding(16)
        .background(style.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: style.radiusLg))
        .contentShape(Rectangle())
        // 아이콘을 숨겼으므로 나오는 앱 이름은 여기서 읽어 준다.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(synergy.title), \(synergy.scene)")
        .accessibilityHint(cast.map(\.name).joined(separator: ", "))
    }
}

// MARK: - 이야기 상세

/// 이야기 한 편을 통째로 보여 주는 화면. 줄에서 눌러 들어온다.
///
/// 끝에 **나오는 앱들로 건너가는 문**을 둔다. 이야기를 읽고 마음이 움직인 자리가
/// 바로 여기라, 다시 목록으로 돌아가 그 앱을 찾게 하지 않는다.
public struct LeeoFamilySynergyDetailView: View {
    @Environment(\.leeoStyle) private var style
    let synergy: LeeoFamilySynergy

    public init(synergy: LeeoFamilySynergy) { self.synergy = synergy }

    private var cast: [LeeoFamilyApp] {
        synergy.appIDs.compactMap { LeeoFamilyCatalog.app(id: $0) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LeeoFamilySynergyCard(synergy: synergy)

                if !cast.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("이 장면에 나오는 앱", comment: "Family synergy detail: cast"))
                            .font(.headline)
                            .foregroundStyle(style.text)
                        ForEach(cast) { app in
                            NavigationLink(destination: LeeoFamilyAppDetailView(app: app)) {
                                LeeoFamilyAppCard(app: app)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(style.bg)
        .navigationTitle(synergy.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - 이야기 카드

public struct LeeoFamilySynergyCard: View {
    @Environment(\.leeoStyle) private var style
    let synergy: LeeoFamilySynergy

    public init(synergy: LeeoFamilySynergy) { self.synergy = synergy }

    private var cast: [LeeoFamilyApp] {
        synergy.appIDs.compactMap { LeeoFamilyCatalog.app(id: $0) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(cast) { app in
                    LeeoFamilyIcon(app: app, size: 26)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(synergy.title)
                    .font(.body).fontWeight(.semibold)
                    .foregroundStyle(style.text)
                Text(synergy.scene)
                    .font(.subheadline)
                    .foregroundStyle(style.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(synergy.beats.enumerated()), id: \.offset) { index, beat in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(style.accent)
                            .frame(width: 18, height: 18)
                            .background(style.accent.opacity(0.14), in: Circle())
                            .accessibilityHidden(true)
                        Text(beat)
                            .font(.subheadline)
                            .foregroundStyle(style.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text(synergy.payoff)
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(style.accent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            HStack(spacing: 6) {
                ForEach(cast) { app in
                    Text(app.name)
                        .font(.caption)
                        .foregroundStyle(style.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(style.surface, in: Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: style.radiusLg))
    }
}

// MARK: - 앱 상세

public struct LeeoFamilyAppDetailView: View {
    @Environment(\.leeoStyle) private var style
    let app: LeeoFamilyApp

    public init(app: LeeoFamilyApp) { self.app = app }

    private var stories: [LeeoFamilySynergy] { LeeoFamilyCatalog.synergies(for: app.id) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                purposeBlock
                bullets(title: L("이런 분에게", comment: "Family detail: audience"),
                        symbol: "person.fill",
                        items: app.forWhom)
                bullets(title: L("이럴 때 좋아요", comment: "Family detail: moments"),
                        symbol: "sparkles",
                        items: app.moments)

                if !stories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("함께 쓰는 장면", comment: "Family detail: stories"))
                            .font(.headline)
                            .foregroundStyle(style.text)
                        ForEach(stories) { synergy in
                            NavigationLink(destination: LeeoFamilySynergyDetailView(synergy: synergy)) {
                                LeeoFamilySynergyRow(synergy: synergy)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                storeButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(style.bg)
        .navigationTitle(app.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            LeeoFamilyIcon(app: app, size: 64)
            Text(app.name)
                .font(.title2).fontWeight(.semibold)
                .foregroundStyle(style.text)
            Text(app.tagline)
                .font(.body)
                .foregroundStyle(style.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            LeeoFamilyPlatformLine(app: app)
        }
    }

    private var purposeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("무엇을 하는 앱인가", comment: "Family detail: purpose"))
                .font(.headline)
                .foregroundStyle(style.text)
            Text(app.purpose)
                .font(.body)
                .foregroundStyle(style.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: style.radiusLg))
    }

    private func bullets(title: String, symbol: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(style.text)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.footnote)
                        .foregroundStyle(app.tint)
                        .frame(width: 18)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.body)
                        .foregroundStyle(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var storeButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                open()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app.fill")
                    Text(L("App Store 에서 보기", comment: "Family: open App Store"))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(app.tint)
                .clipShape(RoundedRectangle(cornerRadius: style.radiusSm))
            }
            .buttonStyle(.plain)

            if !app.runsOnThisDevice {
                Text(L("이 기기에서는 설치할 수 없습니다. 스토어 페이지만 열립니다.",
                       comment: "Family: other platform note"))
                    .font(.footnote)
                    .foregroundStyle(style.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func open() {
        guard let url = app.storeURL else { return }
        HapticManager.shared.light()
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}

// MARK: - 설정에 넣는 한 줄

/// 앱 설정 List/Form 안에 그대로 넣는 진입점.
public struct LeeoFamilySettingsRow<Spec: LeeoAppSpec>: View {
    @Environment(\.leeoStyle) private var style

    public init() {}

    private var others: [LeeoFamilyApp] { LeeoFamilyCatalog.others(for: Spec.self) }

    public var body: some View {
        if !others.isEmpty {
            NavigationLink(destination: LeeoFamilyView<Spec>()) {
                HStack(spacing: 12) {
                    // 무엇이 들어 있는지 줄에서부터 보이게, 홈 화면 폴더처럼 실제 아이콘을 담는다.
                    LeeoFamilyIconGrid(apps: others, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("함께 쓰는 앱", comment: "Family screen title"))
                            .font(.body).fontWeight(.semibold)
                        Text(others.map(\.name).joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(style.textMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - 부품

struct LeeoFamilyGlyph: View {
    let symbol: String
    let tint: Color
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.65)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// 스토어에 올라간 실제 앱 아이콘. 파일이 없는 앱만 상징(`LeeoFamilyGlyph`)으로 물러난다.
///
/// ⚠️ 모서리는 스타일의 radius 가 아니라 **아이콘 크기에 비례**해 깎는다. 홈 화면 아이콘이
///    그렇게 생겼고, 앱 룩의 radius 로 깎으면 같은 아이콘이 크기마다 다른 모양이 된다.
/// ⚠️ 가는 테두리를 두른다. 클립키보드처럼 바탕이 흰 아이콘은 밝은 화면에서 윤곽이 사라진다.
struct LeeoFamilyIcon: View {
    let app: LeeoFamilyApp
    let size: CGFloat
    /// 아이콘끼리 겹쳐 세울 때 둘레에 두르는 바탕색.
    var ring: Color? = nil

    private var radius: CGFloat { size * 0.225 }
    private var ringWidth: CGFloat { ring == nil ? 0 : 1.5 }

    var body: some View {
        Group {
            if let image = LeeoFamilyIconStore.image(for: app) {
                image
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                LeeoFamilyGlyph(symbol: app.symbol, tint: app.tint, size: size, radius: radius)
            }
        }
        .padding(ringWidth)
        .background {
            if let ring {
                RoundedRectangle(cornerRadius: radius + ringWidth, style: .continuous).fill(ring)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 설정 줄에 세우는 작은 아이콘 묶음. 홈 화면 폴더처럼 네 개까지 두 줄로 담는다.
struct LeeoFamilyIconGrid: View {
    @Environment(\.leeoStyle) private var style
    let apps: [LeeoFamilyApp]
    let size: CGFloat

    private var gap: CGFloat { size * 0.1 }
    private var cell: CGFloat { (size - gap * 3) / 2 }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(style.surfaceAlt)
            .frame(width: size, height: size)
            .overlay(
                VStack(spacing: gap) {
                    HStack(spacing: gap) { slot(0); slot(1) }
                    HStack(spacing: gap) { slot(2); slot(3) }
                }
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if index < apps.count {
            LeeoFamilyIcon(app: apps[index], size: cell)
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

/// 아이콘 파일을 한 번만 읽는다. 목록을 굴릴 때마다 PNG 를 디스크에서 다시 풀지 않도록.
enum LeeoFamilyIconStore {
    private static let cache = NSCache<NSString, LeeoFamilyPlatformImage>()

    static func image(for app: LeeoFamilyApp) -> Image? {
        let key = app.id as NSString
        if let hit = cache.object(forKey: key) { return Image(familyIcon: hit) }
        guard let data = app.iconPNGData,
              let loaded = LeeoFamilyPlatformImage(data: data) else { return nil }
        cache.setObject(loaded, forKey: key)
        return Image(familyIcon: loaded)
    }
}

#if canImport(UIKit)
typealias LeeoFamilyPlatformImage = UIImage
private extension Image {
    init(familyIcon: UIImage) { self.init(uiImage: familyIcon) }
}
#elseif canImport(AppKit)
typealias LeeoFamilyPlatformImage = NSImage
private extension Image {
    init(familyIcon: NSImage) { self.init(nsImage: familyIcon) }
}
#endif

struct LeeoFamilyPlatformLine: View {
    @Environment(\.leeoStyle) private var style
    let app: LeeoFamilyApp

    var body: some View {
        HStack(spacing: 8) {
            ForEach(app.platforms) { platform in
                HStack(spacing: 4) {
                    Image(systemName: platform.symbol)
                        .font(.caption2)
                    Text(platform.label)
                        .font(.caption)
                }
                .foregroundStyle(style.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.platformSummary)
    }
}
