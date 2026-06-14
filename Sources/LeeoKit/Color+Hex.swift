//
//  Color+Hex.swift
//  LeeoKit
//
//  Hex <-> Color 변환 및 색상 이름 매핑. 앱 결합 없는 순수 유틸.
//

import SwiftUI

public extension Color {
    /// "#4FACFE" 또는 "4FACFE" 형태의 hex 문자열에서 Color 생성
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    /// Color를 "RRGGBB" hex 문자열로 변환
    func toHex() -> String? {
        #if canImport(UIKit)
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        #elseif canImport(AppKit)
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        #else
        return nil
        #endif

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])

        return String(format: "%02lX%02lX%02lX",
                      lroundf(r * 255),
                      lroundf(g * 255),
                      lroundf(b * 255))
    }

    /// 색상 이름 문자열에서 Color 반환 (테마·카테고리 색상 공통 사용)
    static func fromName(_ name: String) -> Color {
        let colorMap: [String: Color] = [
            "blue": .blue, "green": .green, "purple": .purple,
            "orange": .orange, "red": .red, "indigo": .indigo,
            "brown": .brown, "cyan": .cyan, "teal": .teal,
            "pink": .pink, "mint": .mint, "yellow": .yellow
        ]
        return colorMap[name] ?? .gray
    }
}
