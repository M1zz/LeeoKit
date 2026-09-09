//
//  LeeoFamilyCatalog.swift
//  LeeoKit
//
//  같은 사람이 만든 앱들의 단일 출처. **앱마다 따로 적지 않는다** - 한 곳에 두면
//  앱을 하나 더 냈을 때 LeeoKit 만 올려도 나머지 앱들이 전부 그 앱을 소개하게 된다.
//
//  자기 자신은 목록에서 빠진다. 판정 순서는 `LeeoAppSpec.familyID` → `appStoreID` 대조.
//  둘 다 없으면 아무것도 못 빼므로, 계약에 `appStoreID` 를 적어 두는 편이 좋다.
//
//  ⚠️ `name` 은 **그 언어의 스토어에 실제로 올라간 이름**이다. 우리가 지어 부르면
//     카드에서 본 이름과 스토어에서 만나는 이름이 달라진다. 부제(대시·콜론 뒤)까지
//     통째로 적는 이유가 그것이다. 짧게 다듬으면 그 순간 다시 어긋난다.
//
//     현지화가 없는 언어는 스토어가 한국어 이름을 그대로 보여 준다. 그때는 한국어를
//     그대로 둔다(무지개 공방은 모든 스토어가, 욕망의 무지개·두번알림은 일본·러시아가
//     그렇다). 어느 언어에 무엇이 올라가 있는지는 **짐작하지 말고 확인한다**:
//
//         curl "https://itunes.apple.com/lookup?id=<앱ID>&country=<kr|us|jp|id|ru|cn|tw>"
//
//     스토어 이름이 언어마다 제각각인 앱도 있다(클립키보드 맥: ClipKeyCro · Tap剪贴键盘 ·
//     短语键盘). 보기 좋게 맞추고 싶으면 여기가 아니라 App Store Connect 에서 고친다.
//     여기는 스토어를 **비추는** 자리다.
//  ⚠️ `appStoreID` 는 스토어와의 계약이다. 새 앱을 넣을 때는 실제 ID 를 확인하고 적는다
//     (`curl "https://itunes.apple.com/lookup?bundleId=<번들ID>"` 로 확인된다).
//

import Foundation

public enum LeeoFamilyCatalog {

    // MARK: - 앱

    /// 계산 프로퍼티인 이유: 문구가 `L()` 이라 앱 실행 중 언어가 바뀌면 다시 읽어야 한다.
    public static var apps: [LeeoFamilyApp] {
        [
            LeeoFamilyApp(
                id: "clipkeyboard",
                name: L("클립키보드", comment: "Family app name: ClipKeyboard"),
                appStoreID: "1543660502",
                platforms: [.iPhone, .iPad],
                symbol: "keyboard",
                tintHex: "4FACFE",
                tagline: L("자주 쓰는 문장을 키보드에서 바로 꺼낸다",
                           comment: "Family tagline: ClipKeyboard"),
                purpose: L("계좌번호, 주소, 인사말처럼 매번 다시 치는 문장을 모아 두고 어느 앱에서든 키보드에서 바로 붙여넣습니다. 복사한 것은 스스로 갈래를 나눠 쌓입니다.",
                           comment: "Family purpose: ClipKeyboard"),
                forWhom: [
                    L("같은 답장을 하루에도 몇 번씩 보내는 사람",
                      comment: "Family audience: ClipKeyboard 1"),
                    L("계좌번호나 주소를 매번 찾아 헤매는 사람",
                      comment: "Family audience: ClipKeyboard 2"),
                ],
                moments: [
                    L("문의 답변, 지원서, 예약 확인처럼 문장이 반복되는 일",
                      comment: "Family moment: ClipKeyboard 1"),
                    L("복사해 둔 것을 조금 뒤에 다시 찾아야 할 때",
                      comment: "Family moment: ClipKeyboard 2"),
                ]
            ),
            LeeoFamilyApp(
                id: "clipkeyboard-mac",
                name: L("클립키보드: 빠른 붙여넣기", comment: "Family app name: ClipKeyboard for Mac (store name)"),
                appStoreID: "6756433372",
                platforms: [.mac],
                symbol: "menubar.rectangle",
                tintHex: "5B8DEF",
                tagline: L("메뉴바에서 한 번, 맥에서도 같은 문장",
                           comment: "Family tagline: ClipKeyboard for Mac"),
                purpose: L("아이폰에서 모은 문장이 iCloud 로 맥에 따라옵니다. 메뉴바 아이콘이나 전역 단축키로 어느 앱에서든 꺼내 붙여넣습니다.",
                           comment: "Family purpose: ClipKeyboard for Mac"),
                forWhom: [
                    L("폰과 맥을 오가며 같은 문장을 쓰는 사람",
                      comment: "Family audience: ClipKeyboard for Mac 1"),
                    L("메일과 문서 작업이 맥에서 끝나는 사람",
                      comment: "Family audience: ClipKeyboard for Mac 2"),
                ],
                moments: [
                    L("맥에서 메일을 쓰다 폰에 저장해 둔 문구가 필요할 때",
                      comment: "Family moment: ClipKeyboard for Mac 1"),
                    L("손을 키보드에서 떼지 않고 붙여넣고 싶을 때",
                      comment: "Family moment: ClipKeyboard for Mac 2"),
                ]
            ),
            LeeoFamilyApp(
                id: "rainbow-ios",
                name: L("욕망의 무지개", comment: "Family app name: Rainbow of Desire (store name)"),
                appStoreID: "6755280882",
                platforms: [.iPhone],
                symbol: "rainbow",
                tintHex: "FF7A59",
                tagline: L("겹칠수록 진해지는 한 주, 지금 집을 수 있는 일",
                           comment: "Family tagline: Rainbow of Desire"),
                purpose: L("일정의 밀도를 색으로 보여 주고, 할 일을 5분에 끝낼 조각과 시간을 떼어 둬야 할 덩어리로 갈라 줍니다. 위젯은 지금 당장 집을 수 있는 것 하나만 내밉니다.",
                           comment: "Family purpose: Rainbow of Desire"),
                forWhom: [
                    L("할 일 목록이 길어질수록 손이 안 가는 사람",
                      comment: "Family audience: Rainbow of Desire 1"),
                    L("언제 바빠지는지 미리 알고 싶은 사람",
                      comment: "Family audience: Rainbow of Desire 2"),
                ],
                moments: [
                    L("5분이 비었는데 무엇부터 할지 모를 때",
                      comment: "Family moment: Rainbow of Desire 1"),
                    L("다음 주에 약속을 하나 더 넣어도 되는지 가늠할 때",
                      comment: "Family moment: Rainbow of Desire 2"),
                ]
            ),
            LeeoFamilyApp(
                id: "rainbow-mac",
                name: L("무지개 공방", comment: "Family app name: Rainbow Workshop (Korean-only listing, all storefronts)"),
                appStoreID: "6777737322",
                platforms: [.mac],
                symbol: "square.grid.3x3",
                tintHex: "F5A623",
                tagline: L("한 주를 요일과 시간대로 짜는 작업대",
                           comment: "Family tagline: Rainbow Workshop"),
                purpose: L("할 일을 요일 격자에 끌어다 놓아 계획 블록으로 만듭니다. 수면과 식사 같은 고정 루틴을 먼저 깔고, 남은 자리에 일을 앉힙니다.",
                           comment: "Family purpose: Rainbow Workshop"),
                forWhom: [
                    L("주 단위로 계획을 세워 두고 움직이는 사람",
                      comment: "Family audience: Rainbow Workshop 1"),
                    L("폰에서 쪼갠 할 일을 큰 화면에서 배치하고 싶은 사람",
                      comment: "Family audience: Rainbow Workshop 2"),
                ],
                moments: [
                    L("일요일 저녁, 다음 한 주를 미리 앉혀 둘 때",
                      comment: "Family moment: Rainbow Workshop 1"),
                    L("회의와 마감 사이에 남은 시간을 찾을 때",
                      comment: "Family moment: Rainbow Workshop 2"),
                ]
            ),
            LeeoFamilyApp(
                id: "rereminder",
                name: L("두번알림", comment: "Family app name: Rereminder"),
                appStoreID: "6752551268",
                platforms: [.iPhone, .watch],
                symbol: "bell.badge",
                tintHex: "5E5CE6",
                tagline: L("끝나기 전에 한 번 더 울리는 타이머",
                           comment: "Family tagline: Rereminder"),
                purpose: L("종료 10분 전, 5분 전처럼 원하는 시점마다 미리 알립니다. 잠금 화면과 애플워치에서 남은 시간이 계속 보입니다.",
                           comment: "Family purpose: Rereminder"),
                forWhom: [
                    L("시간을 재며 일하는 사람",
                      comment: "Family audience: Rereminder 1"),
                    L("마감 직전에야 알아차려 곤란했던 사람",
                      comment: "Family audience: Rereminder 2"),
                ],
                moments: [
                    L("발표나 시험처럼 남은 시간을 배분해야 할 때",
                      comment: "Family moment: Rereminder 1"),
                    L("운동과 공부처럼 구간을 나눠 쓰는 시간",
                      comment: "Family moment: Rereminder 2"),
                ]
            ),
        ]
    }

    // MARK: - 함께 쓰는 이야기

    public static var synergies: [LeeoFamilySynergy] {
        [
            LeeoFamilySynergy(
                id: "apply-day",
                appIDs: ["rainbow-ios", "clipkeyboard", "rereminder"],
                title: L("지원서를 넣는 날", comment: "Synergy title: application day"),
                scene: L("열 군데에 비슷한 서류를 넣어야 하는 하루.",
                         comment: "Synergy scene: application day"),
                beats: [
                    L("욕망의 무지개가 '지원서 넣기'를 단계로 쪼갭니다. 자기소개를 붙여넣는 일은 5분 조각으로 남습니다.",
                      comment: "Synergy beat: application day 1"),
                    L("회사 이름만 바뀌는 자기소개는 클립키보드 템플릿으로 한 번만 만들어 두고 키보드에서 꺼냅니다.",
                      comment: "Synergy beat: application day 2"),
                    L("마감이 있는 곳은 두번알림에 걸어 둡니다. 30분 전과 5분 전에 한 번 더 울립니다.",
                      comment: "Synergy beat: application day 3"),
                ],
                payoff: L("같은 문장을 다시 쓰지 않고, 마감을 놓치지 않습니다.",
                          comment: "Synergy payoff: application day")
            ),
            LeeoFamilySynergy(
                id: "paperwork",
                appIDs: ["clipkeyboard", "rereminder"],
                title: L("서류가 오가는 오후", comment: "Synergy title: paperwork"),
                scene: L("계약이나 이사처럼 번호와 주소를 여러 번 적어 내는 날.",
                         comment: "Synergy scene: paperwork"),
                beats: [
                    L("복사한 계좌번호와 주소는 클립키보드가 갈래를 나눠 쌓아 둡니다. 다시 찾아 헤맬 일이 없습니다.",
                      comment: "Synergy beat: paperwork 1"),
                    L("상대가 확인해 주기로 한 시각은 두번알림에 겁니다.",
                      comment: "Synergy beat: paperwork 2"),
                    L("약속한 시간보다 먼저 울리니, 기다리는 쪽이 아니라 먼저 연락하는 쪽이 됩니다.",
                      comment: "Synergy beat: paperwork 3"),
                ],
                payoff: L("적어 둔 것을 잃지 않고, 약속한 시각을 넘기지 않습니다.",
                          comment: "Synergy payoff: paperwork")
            ),
            LeeoFamilySynergy(
                id: "focus-hour",
                appIDs: ["rainbow-ios", "rereminder", "clipkeyboard"],
                title: L("한 시간을 지켜 두는 법", comment: "Synergy title: focus hour"),
                scene: L("덩어리로 해야 하는 일에 시간을 떼어 둔 날.",
                         comment: "Synergy scene: focus hour"),
                beats: [
                    L("욕망의 무지개가 이 일은 조각이 아니라 덩어리라고 먼저 말해 줍니다.",
                      comment: "Synergy beat: focus hour 1"),
                    L("두번알림으로 한 시간을 재고, 끝나기 10분 전에 마무리 신호를 받습니다.",
                      comment: "Synergy beat: focus hour 2"),
                    L("중간에 들어온 문의는 클립키보드에 정해 둔 답장으로 짧게 끊습니다.",
                      comment: "Synergy beat: focus hour 3"),
                ],
                payoff: L("떼어 둔 시간이 조각으로 부서지지 않습니다.",
                          comment: "Synergy payoff: focus hour")
            ),
            LeeoFamilySynergy(
                id: "mac-desk",
                appIDs: ["rainbow-mac", "clipkeyboard-mac"],
                title: L("맥 앞에 앉은 아침", comment: "Synergy title: mac morning"),
                scene: L("맥을 켜고 오늘 할 일을 앉히는 삼십 분.",
                         comment: "Synergy scene: mac morning"),
                beats: [
                    L("무지개 공방에서 오늘 요일 칸에 할 일을 끌어다 놓습니다.",
                      comment: "Synergy beat: mac morning 1"),
                    L("메일과 문서에 들어갈 문장은 메뉴바의 클립키보드에서 단축키로 꺼냅니다.",
                      comment: "Synergy beat: mac morning 2"),
                    L("폰에서 저장한 것이 그대로 있으니 다시 옮겨 적을 일이 없습니다.",
                      comment: "Synergy beat: mac morning 3"),
                ],
                payoff: L("폰에서 모은 것을 맥에서 쓰고, 폰에서 쪼갠 것을 맥에서 짭니다.",
                          comment: "Synergy payoff: mac morning")
            ),
            LeeoFamilySynergy(
                id: "rainbow-pair",
                appIDs: ["rainbow-ios", "rainbow-mac"],
                title: L("폰에서 쪼개고 맥에서 짠다", comment: "Synergy title: rainbow pair"),
                scene: L("같은 iCloud 를 쓰는 두 앱은 같은 할 일을 봅니다.",
                         comment: "Synergy scene: rainbow pair"),
                beats: [
                    L("밖에서는 폰으로 할 일을 단계로 쪼갭니다.",
                      comment: "Synergy beat: rainbow pair 1"),
                    L("책상에 앉으면 맥에서 그 단계들을 요일과 시간대에 앉힙니다.",
                      comment: "Synergy beat: rainbow pair 2"),
                    L("한쪽에서 고친 자리는 다른 쪽에도 곧 나타납니다.",
                      comment: "Synergy beat: rainbow pair 3"),
                ],
                payoff: L("쪼개는 곳과 앉히는 곳이 달라도 목록은 하나입니다.",
                          comment: "Synergy payoff: rainbow pair")
            ),
        ]
    }

    // MARK: - 조회

    public static func app(id: String) -> LeeoFamilyApp? {
        apps.first { $0.id == id }
    }

    /// 이 앱이 카탈로그에서 누구인지. `familyID` 가 우선, 없으면 스토어 ID 로 찾는다.
    public static func currentAppID<Spec: LeeoAppSpec>(_ spec: Spec.Type) -> String? {
        if let declared = Spec.familyID { return declared }
        guard let storeID = Spec.appStoreID else { return nil }
        return apps.first { $0.appStoreID == storeID }?.id
    }

    /// 자기 자신을 뺀 나머지. 지금 기기에서 받을 수 있는 앱이 앞에 선다.
    public static func others<Spec: LeeoAppSpec>(for spec: Spec.Type) -> [LeeoFamilyApp] {
        let me = currentAppID(spec)
        let rest = apps.filter { $0.id != me }
        return rest.filter(\.runsOnThisDevice) + rest.filter { !$0.runsOnThisDevice }
    }

    /// 이 앱이 등장하는 이야기. 화면 맨 위에 서는 것들이다.
    public static func synergies<Spec: LeeoAppSpec>(involving spec: Spec.Type) -> [LeeoFamilySynergy] {
        let me = currentAppID(spec)
        return synergies.filter { $0.involves(me) }
    }

    /// 이 앱이 안 나오는 나머지 이야기.
    public static func synergies<Spec: LeeoAppSpec>(excluding spec: Spec.Type) -> [LeeoFamilySynergy] {
        let me = currentAppID(spec)
        return synergies.filter { !$0.involves(me) }
    }

    /// 특정 앱이 등장하는 이야기 (상세 화면용).
    public static func synergies(for appID: String) -> [LeeoFamilySynergy] {
        synergies.filter { $0.involves(appID) }
    }
}
