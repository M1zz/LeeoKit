//
//  LeeoDataPromise.swift
//  LeeoKit
//
//  **내 데이터는 어디에.** 리이오의 앱이 하는 약속을 한 화면에, 모든 앱이 같은 모양으로 보인다.
//
//    이 기기에만        그 앱에서 만든 것 (앱이 Spec 의 `dataPromise` 로 적는다)
//    내 iCloud에만      백업 · 동기화 — 그 사람의 Apple 계정 안이라 개발자도 못 본다
//    개발자의 부탁       앱을 더 좋게 만들 데이터 [스위치] · 의견은 보낼 때만
//    없는 것            광고 · 추적 · 회원 가입 · 외부 회사 도구
//    직접 확인하기       iOS 의 앱 개인정보 보호 리포트 · 인터넷 없이도 되는지
//
//  ⚠️ 말과 코드가 같아야 한다. 스위치(`LeeoImprovementData`)를 끄면 사용 기록(`LeeoUsageReporter`) ·
//     오류 기록(`LeeoDiagnostics`)이 정말로 나가지 않는다. 새로 무언가를 개발자에게 보내는 코드를 넣으면
//     이 스위치를 지나게 하고, 이 화면의 '개발자의 부탁' 설명에 그것을 적는다.
//  ⚠️ 사용자에게 보이는 말에 '통계' 를 쓰지 않는다. 개발자가 앱을 고치려고 **부탁하는** 데이터다.
//
//  설정에서 한 줄:
//      LeeoDataPromiseLink<MyAppSpec>()
//

import SwiftUI

// MARK: - 개발자의 부탁 (스위치)

/// 앱을 더 좋게 만들 데이터를 개발자에게 보낼지. 처음엔 보낸다(켜짐) — 이 화면에서 언제든 끈다.
/// 끄면 사용 기록 · 오류 기록이 기기를 떠나지 않는다. 사용자가 직접 보내는 의견은 이 스위치와 따로다.
public enum LeeoImprovementData {
    public static let key = "leeo.sendsImprovementData"

    public static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - 앱이 적는 것

/// 그 앱에서 무엇이 어디에 있는지. Spec 의 `dataPromise` 로 준다.
public struct LeeoDataPromise: Sendable {
    /// 이 기기에만 있는 것 — 그 앱에서 사람이 만든 것. 예: "장표 · 녹음 · 받아쓴 글"
    public let onDevice: [String]
    /// 내 iCloud 에 가는 것(백업 말고). 예: "발표 동기화 (켰을 때)". 백업은 금고를 쓰면 저절로 들어간다.
    public let inICloud: [String]
    /// 인터넷 없이도 앱의 일을 다 하는가. 참이면 '직접 확인하기' 에 비행기 모드 한 줄이 선다.
    public let worksOffline: Bool

    public init(onDevice: [String] = [], inICloud: [String] = [], worksOffline: Bool = false) {
        self.onDevice = onDevice
        self.inICloud = inICloud
        self.worksOffline = worksOffline
    }
}

// MARK: - 문구

public enum LeeoDataPromiseText {
    /// 설정 행 이름.
    public static var entry: String { L("내 데이터는 어디에", comment: "Data promise: settings entry and screen title") }
}

// MARK: - 설정 행

public struct LeeoDataPromiseLink<Spec: LeeoAppSpec>: View {
    private let systemImage: String

    public init(systemImage: String = "lock.shield") {
        self.systemImage = systemImage
    }

    public var body: some View {
        NavigationLink {
            LeeoDataPromiseView<Spec>()
        } label: {
            Label(LeeoDataPromiseText.entry, systemImage: systemImage)
        }
    }
}

// MARK: - 화면

public struct LeeoDataPromiseView<Spec: LeeoAppSpec>: View {
    @AppStorage(LeeoImprovementData.key) private var sendsImprovementData = true

    public init() {}

    private var promise: LeeoDataPromise { Spec.dataPromise }

    /// 이 기기에만. 앱이 적지 않았으면 두루 맞는 말 한 줄.
    private var onDevice: [String] {
        promise.onDevice.isEmpty ? [L("이 앱에서 만든 모든 기록", comment: "Data promise: default on-device item")] : promise.onDevice
    }

    /// 내 iCloud에만. 금고가 iCloud 를 쓰면 백업이 먼저 선다.
    private var inICloud: [String] {
        (Spec.vaultUsesICloud ? [L("백업 (만들었을 때)", comment: "Data promise: iCloud item, backups the person made")] : [])
            + promise.inICloud
    }

    public var body: some View {
        Form {
            Section {
                ForEach(onDevice, id: \.self) { Label($0, systemImage: "iphone") }
            } header: {
                Text(L("이 기기에만", comment: "Data promise: section, stays on this device"))
            } footer: {
                Text(L("기기 밖 어디에도 저장하지 않아요. 개발자도 볼 수 없어요.", comment: "Data promise: on-device footer"))
            }

            if !inICloud.isEmpty {
                Section {
                    ForEach(inICloud, id: \.self) { Label($0, systemImage: "icloud") }
                } header: {
                    Text(L("내 iCloud에만", comment: "Data promise: section, only in the person's own iCloud"))
                } footer: {
                    Text(L("내 Apple 계정 안에만 있어서 개발자도 볼 수 없어요.", comment: "Data promise: iCloud footer"))
                }
            }

            Section {
                Toggle(isOn: $sendsImprovementData) {
                    Label(L("앱을 더 좋게 만들 데이터 보내기", comment: "Data promise: switch to send improvement data to the developer"),
                          systemImage: "hand.raised")
                }
                Label(L("의견은 내가 보낼 때만 가요", comment: "Data promise: feedback is sent only when the person sends it"),
                      systemImage: "envelope")
            } header: {
                Text(L("개발자의 부탁", comment: "Data promise: section, what the developer asks for"))
            } footer: {
                Text(L("앱이 멈추거나 오류가 났을 때의 기록, 앱 버전 · 기기 종류 · 언어, 앱을 연 날과 기능을 쓴 횟수를 보내 주시면 고치고 다듬는 데 써요. 내가 만든 기록과 이름 · 이메일은 들어가지 않고, 누가 보냈는지도 알 수 없어요. 끄면 아무것도 보내지 않아요.",
                       comment: "Data promise: what improvement data contains and what it never contains"))
            }

            Section {
                Label(L("광고", comment: "Data promise: not present, ads"), systemImage: "nosign")
                Label(L("나를 따라다니는 추적", comment: "Data promise: not present, tracking"), systemImage: "nosign")
                Label(L("회원 가입", comment: "Data promise: not present, account sign-up"), systemImage: "nosign")
                Label(L("외부 회사의 분석 도구", comment: "Data promise: not present, third-party analytics SDKs"), systemImage: "nosign")
            } header: {
                Text(L("없는 것", comment: "Data promise: section, things this app does not have"))
            }

            Section {
                Text(L("설정 ▸ 개인정보 보호 및 보안 ▸ 앱 개인정보 보호 리포트를 켜 두면 이 앱이 어디에 연결했는지 iPhone이 직접 보여 줘요.",
                       comment: "Data promise: how to verify with iOS App Privacy Report. Use the exact iOS Settings names of this language"))
                if promise.worksOffline {
                    Text(L("비행기 모드에서도 앱의 일은 그대로 돼요. 인터넷은 구입, iCloud, 그리고 개발자에게 보낼 때만 써요.",
                           comment: "Data promise: the app works offline; internet is only for purchases, iCloud and sending things to the developer"))
                }
            } header: {
                Text(L("직접 확인하기", comment: "Data promise: section, verify it yourself"))
            }
        }
        .navigationTitle(LeeoDataPromiseText.entry)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
