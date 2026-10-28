//
//  LeeoShareApp.swift
//  LeeoKit
//
//  친구에게 앱을 소개하는 설정 한 줄. 무료 앱에서 "선물하기" 자리에 선다 —
//  줄 수 있는 것이 앱 자체뿐이라, App Store 링크를 공유 시트로 보낸다.
//
//  App Store ID 가 없으면(아직 안 나온 앱) 줄을 그리지 않는다. 열리지 않는 링크를 보내게 하지 않는다.
//
//  설정에서 한 줄:
//      LeeoShareAppLink<MyAppSpec>()
//

import SwiftUI

// MARK: - 앱이 쓰는 문구

public enum LeeoShareText {
    /// 설정 행 이름.
    public static var entry: String { L("친구에게 소개하기", comment: "Share app: settings entry") }

    /// 링크와 함께 가는 한 줄. 보내는 사람이 시트에서 고칠 수 있다.
    public static func message(appName: String) -> String {
        String(format: L("%@ 한번 써 봐요.", comment: "Share app: message sent with the App Store link. %@ = app name"),
               appName)
    }

    /// 그 앱의 App Store 링크. 나라를 붙이지 않아 받는 사람의 스토어로 열린다.
    public static func appStoreURL(appStoreID: String?) -> URL? {
        guard let appStoreID, !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }
}

// MARK: - 설정 행

public struct LeeoShareAppLink<Spec: LeeoAppSpec>: View {
    private let systemImage: String

    public init(systemImage: String = "square.and.arrow.up") {
        self.systemImage = systemImage
    }

    public var body: some View {
        if let url = LeeoShareText.appStoreURL(appStoreID: Spec.appStoreID) {
            ShareLink(item: url,
                      subject: Text(Spec.displayName),
                      message: Text(LeeoShareText.message(appName: Spec.displayName))) {
                Label(LeeoShareText.entry, systemImage: systemImage)
            }
        }
    }
}
