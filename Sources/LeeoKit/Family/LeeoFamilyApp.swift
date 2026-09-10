//
//  LeeoFamilyApp.swift
//  LeeoKit
//
//  같은 사람이 만든 앱 하나를 설명하는 값. "다운로드 해 달라"가 아니라
//  **무엇을 하는 앱이고, 누구에게, 언제 좋은가**를 담는다.
//
//  광고 문구를 넣지 않는 이유: 이 화면은 이미 내 앱을 쓰고 있는 사람이 본다.
//  그 사람에게 필요한 것은 설득이 아니라 "내 상황에 맞나"의 판단 근거다.
//
//  카탈로그는 `LeeoFamilyCatalog` 한 곳에 있고, 화면은 `LeeoFamilyView` 다.
//

import SwiftUI

// MARK: - 플랫폼

/// 앱이 사는 곳. 아이폰에서 맥 앱을 소개할 때 "여기서는 못 받는다"를 숨기지 않기 위해 붙인다.
public enum LeeoFamilyPlatform: String, Sendable, CaseIterable, Identifiable {
    case iPhone
    case iPad
    case mac
    case watch

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .iPhone: return L("아이폰", comment: "Platform: iPhone")
        case .iPad:   return L("아이패드", comment: "Platform: iPad")
        case .mac:    return L("맥", comment: "Platform: Mac")
        case .watch:  return L("애플워치", comment: "Platform: Apple Watch")
        }
    }

    public var symbol: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad:   return "ipad"
        case .mac:    return "macbook"
        case .watch:  return "applewatch"
        }
    }

    /// 이 기기에서 바로 설치할 수 있는 플랫폼인지. 아닌 것은 화면이 "맥에서 쓰는 앱"이라고 미리 말한다.
    public var isCurrentDevice: Bool {
        #if targetEnvironment(macCatalyst)
        return self == .mac
        #elseif os(macOS)
        return self == .mac
        #elseif os(watchOS)
        return self == .watch
        #else
        return self == .iPhone || self == .iPad
        #endif
    }
}

// MARK: - 앱

public struct LeeoFamilyApp: Identifiable, Sendable, Equatable {
    /// 카탈로그 안에서만 쓰는 안정된 열쇠. 스토어 ID 가 바뀌어도 시너지 이야기가 안 깨지도록 따로 둔다.
    public let id: String

    /// 그 언어의 App Store 에 실제로 올라간 이름. 현지화된 목록이 없는 앱은 어느 언어에서도
    /// 원래 이름 그대로 둔다 - 사용자가 스토어에서 찾을 이름이라서다.
    public let name: String

    public let appStoreID: String
    public let platforms: [LeeoFamilyPlatform]

    /// SF Symbol. 아이콘(`iconPNGData`)이 없을 때만 쓰는 자리표시다.
    public let symbol: String
    public let tintHex: String

    /// 한 줄 소개.
    public let tagline: String
    /// 무엇을 하는 앱인가 (두세 문장).
    public let purpose: String
    /// 이런 사람에게.
    public let forWhom: [String]
    /// 이럴 때 좋다.
    public let moments: [String]

    public init(
        id: String,
        name: String,
        appStoreID: String,
        platforms: [LeeoFamilyPlatform],
        symbol: String,
        tintHex: String,
        tagline: String,
        purpose: String,
        forWhom: [String],
        moments: [String]
    ) {
        self.id = id
        self.name = name
        self.appStoreID = appStoreID
        self.platforms = platforms
        self.symbol = symbol
        self.tintHex = tintHex
        self.tagline = tagline
        self.purpose = purpose
        self.forWhom = forWhom
        self.moments = moments
    }

    public var tint: Color { Color(hex: tintHex) ?? .accentColor }

    public var storeURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }

    /// 이 앱의 **실제 앱 아이콘**(PNG). 각 앱 레포의 AppIcon 원본을 줄여
    /// `LeeoFamilyIconData` 에 상수로 박아 둔 것을 꺼낸다.
    /// 상징만 그려 두면 카드를 보고 홈 화면이나 스토어에서 그 앱을 알아볼 수 없다.
    public var iconPNGData: Data? {
        LeeoFamilyIconData.pngBase64[id].flatMap { Data(base64Encoded: $0) }
    }

    /// "아이폰 · 애플워치" 처럼 한 줄로.
    public var platformSummary: String {
        platforms.map(\.label).joined(separator: " · ")
    }

    /// 지금 기기에서 바로 받을 수 있는가. 아니면 화면이 그 사실을 먼저 말한다.
    public var runsOnThisDevice: Bool {
        platforms.contains(where: \.isCurrentDevice)
    }
}
