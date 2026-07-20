//
//  LeeoStyle.swift
//  LeeoKit
//
//  LeeoKit 화면 컴포넌트의 외형 값. 앱의 디자인 시스템과 무관하게 시스템 색 기본값으로
//  동작하고, 앱 테마가 있으면 `.leeoStyle(_:)`로 한 번 주입해서 앱과 같은 룩을 만든다.
//
//  사용 예 (앱 쪽):
//      LeeoFeedbackView<MyAppSpec>()
//          .leeoStyle(LeeoStyle(accent: theme.accent, bg: theme.bg, ...))
//

import SwiftUI

public struct LeeoStyle {
    public var accent: Color
    public var bg: Color
    public var surface: Color
    public var surfaceAlt: Color
    public var text: Color
    public var textMuted: Color
    public var textFaint: Color
    public var radiusSm: CGFloat
    public var radiusLg: CGFloat

    public init(
        accent: Color = .accentColor,
        bg: Color = .leeoSystemBackground,
        surface: Color = .leeoSecondaryBackground,
        surfaceAlt: Color = .leeoSecondaryBackground,
        text: Color = .primary,
        textMuted: Color = .secondary,
        textFaint: Color = .leeoTertiaryLabel,
        radiusSm: CGFloat = 10,
        radiusLg: CGFloat = 20
    ) {
        self.accent = accent
        self.bg = bg
        self.surface = surface
        self.surfaceAlt = surfaceAlt
        self.text = text
        self.textMuted = textMuted
        self.textFaint = textFaint
        self.radiusSm = radiusSm
        self.radiusLg = radiusLg
    }
}

private struct LeeoStyleKey: EnvironmentKey {
    static let defaultValue = LeeoStyle()
}

public extension EnvironmentValues {
    var leeoStyle: LeeoStyle {
        get { self[LeeoStyleKey.self] }
        set { self[LeeoStyleKey.self] = newValue }
    }
}

public extension View {
    /// LeeoKit 컴포넌트에 앱 테마 룩을 주입한다.
    func leeoStyle(_ style: LeeoStyle) -> some View {
        environment(\.leeoStyle, style)
    }
}

// MARK: - 크로스 플랫폼 시스템 색 (iOS/Catalyst ↔ macOS)

public extension Color {
    static var leeoSystemBackground: Color {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var leeoSecondaryBackground: Color {
        #if canImport(UIKit)
        Color(UIColor.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    static var leeoTertiaryLabel: Color {
        #if canImport(UIKit)
        Color(UIColor.tertiaryLabel)
        #else
        Color(NSColor.tertiaryLabelColor)
        #endif
    }
}
