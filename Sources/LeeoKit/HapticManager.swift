//
//  HapticManager.swift
//  LeeoKit
//
//  햅틱 피드백 래퍼. UIKit 없는 환경(macOS native)에서는 no-op 폴백.
//

#if canImport(UIKit)
import UIKit

public struct HapticManager {
    public static let shared = HapticManager()
    private init() {}

    /// Light impact - for button taps, toggles
    public func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium impact - for significant actions
    public func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Heavy impact - for important completions
    public func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Success notification - for successful operations
    public func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification - for warnings
    public func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error notification - for errors
    public func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Selection changed - for picker changes
    public func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Rigid impact - for delete actions
    public func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// Soft impact - for subtle interactions
    public func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
#else
// macOS native fallback - no haptics
public struct HapticManager {
    public static let shared = HapticManager()
    private init() {}

    public func light() {}
    public func medium() {}
    public func heavy() {}
    public func success() {}
    public func warning() {}
    public func error() {}
    public func selection() {}
    public func rigid() {}
    public func soft() {}
}
#endif
