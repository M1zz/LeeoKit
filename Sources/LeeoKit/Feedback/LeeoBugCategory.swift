//
//  LeeoBugCategory.swift
//  LeeoKit
//
//  버그 신고를 **무슨 종류의 문제인지**로 한 번 더 나눈다.
//
//  왜 필요한가: "Pro 가 사라졌어요, 복원해도 없어요" 가 왔을 때 필요한 것은 언제 샀는지,
//  지금 Apple 이 이 기기에 무엇을 돌려주는지였다. 그런데 버그 칸은 하나라 "언제 · 무엇을 ·
//  어떻게" 만 물었고, 결제 기록은 받을 길이 없었다. 결국 산 사람인지조차 가리지 못했다.
//
//  문제의 종류마다 고치는 데 필요한 것이 다르다. 그래서 분류마다
//  - 묻는 칸(`prompts`, 셋을 넘기지 않는다)
//  - 부탁하는 사진과 **그 사진을 어디서 찍는지**(`attachments`)
//  - 묻지 않고 붙이는 진단(`probes`, 보내기 전에 사용자에게 그대로 보인다)
//  을 따로 둔다. 무엇을 받아서 어떻게 읽는지는 `docs/BUG_CATEGORIES.md`.
//
//  ⚠️ rawValue 는 자동 첨부 정보의 `category:` 줄에 그대로 실린다. 허브가 이 값으로 거르므로
//     바꾸지 않는다.
//

import Foundation

public enum LeeoBugCategory: String, CaseIterable, Sendable {
    /// 꺼짐, 흰 화면, 열리지 않음.
    case crash
    /// 느림, 버벅임, 배터리.
    case slow
    /// 결제했는데 안 열림, 복원 실패.
    case purchase
    /// 기기 사이 동기화, iCloud 백업.
    case sync
    /// 만들어 둔 것이 사라짐.
    case dataLoss = "data_loss"
    /// 알림이 안 오거나 늦음.
    case notification
    /// 위젯 · 키보드 · 제어 센터처럼 앱 밖에서 도는 것.
    case widget
    /// 레이아웃 깨짐, 글자 잘림, 어색한 번역.
    case display
    /// 위 어디에도 안 맞는 것. 예전 버그 칸 그대로 묻는다.
    case other

    // MARK: - 이름과 그림

    public var localizedName: String {
        switch self {
        case .crash:        return L("꺼지거나 열리지 않아요", comment: "Bug category: crash or won't open")
        case .slow:         return L("느리거나 버벅여요", comment: "Bug category: slow")
        case .purchase:     return L("결제 · 구매 복원", comment: "Bug category: purchase and restore")
        case .sync:         return L("동기화 · 백업", comment: "Bug category: sync and backup")
        case .dataLoss:     return L("데이터가 사라졌어요", comment: "Bug category: data loss")
        case .notification: return L("알림이 안 오거나 늦어요", comment: "Bug category: notifications")
        case .widget:       return L("위젯이나 키보드가 안 돼요", comment: "Bug category: widget or keyboard")
        case .display:      return L("화면이나 글자가 이상해요", comment: "Bug category: display or text")
        case .other:        return L("그 밖의 문제", comment: "Bug category: other")
        }
    }

    public var icon: String {
        switch self {
        case .crash:        return "xmark.octagon"
        case .slow:         return "tortoise"
        case .purchase:     return "creditcard"
        case .sync:         return "icloud.slash"
        case .dataLoss:     return "tray"
        case .notification: return "bell.slash"
        case .widget:       return "square.grid.2x2"
        case .display:      return "textformat"
        case .other:        return "ladybug"
        }
    }

    // MARK: - 묻는 칸

    /// 이 분류에서 나눠 물을 칸. **셋을 넘기지 않는다**(`LeeoFeedbackType.prompts` 와 같은 규칙).
    public var prompts: [LeeoFeedbackPrompt] {
        switch self {
        case .crash:
            return [
                LeeoBugPrompts.when,
                LeeoFeedbackPrompt(
                    id: "crash.what",
                    label: L("어떻게 되나요?", comment: "Crash prompt: what happens"),
                    placeholder: L("예) 열면 흰 화면에서 멈춰요. 저장을 누르면 앱이 꺼져요.",
                                   comment: "Crash prompt placeholder: what happens"),
                    isRequired: true, isMultiline: true),
                LeeoFeedbackPrompt(
                    id: "crash.repeat",
                    label: L("매번 그런가요? 껐다 켜도 그런가요? (선택)", comment: "Crash prompt: reproducible"),
                    placeholder: L("예) 매번요. 기기를 껐다 켜도 같아요.",
                                   comment: "Crash prompt placeholder: reproducible"),
                    isRequired: false, isMultiline: false)
            ]
        case .slow:
            return [
                LeeoFeedbackPrompt(
                    id: "slow.where",
                    label: L("어느 화면에서, 얼마나 걸리나요?", comment: "Slow prompt: where and how long"),
                    placeholder: L("예) 목록을 내릴 때마다 1초쯤 멈칫해요.",
                                   comment: "Slow prompt placeholder: where and how long"),
                    isRequired: true, isMultiline: true),
                LeeoBugPrompts.since
            ]
        case .purchase:
            return [
                LeeoFeedbackPrompt(
                    id: "purchase.what",
                    label: L("무엇을 샀고, 지금 어떻게 보이나요?", comment: "Purchase prompt: what was bought and what is shown"),
                    placeholder: L("예) 평생 이용권을 샀는데, 앱을 다시 깔고 나니 잠겨 있어요. 복원을 눌러도 없다고 나와요.",
                                   comment: "Purchase prompt placeholder: what was bought"),
                    isRequired: true, isMultiline: true),
                LeeoFeedbackPrompt(
                    id: "purchase.when",
                    label: L("언제, 어느 기기에서 샀나요? (선택)", comment: "Purchase prompt: when and on which device"),
                    placeholder: L("예) 올해 3월쯤, 예전 아이폰에서요.",
                                   comment: "Purchase prompt placeholder: when and device"),
                    isRequired: false, isMultiline: false)
            ]
        case .sync:
            return [
                LeeoFeedbackPrompt(
                    id: "sync.what",
                    label: L("어느 기기 사이에서, 무엇이 안 맞나요?", comment: "Sync prompt: which devices and what"),
                    placeholder: L("예) 아이폰에서 만든 것이 아이패드에 안 보여요.",
                                   comment: "Sync prompt placeholder: which devices"),
                    isRequired: true, isMultiline: true),
                LeeoBugPrompts.since
            ]
        case .dataLoss:
            return [
                LeeoFeedbackPrompt(
                    id: "loss.what",
                    label: L("무엇이, 얼마나 사라졌나요?", comment: "Data loss prompt: what and how much"),
                    placeholder: L("예) 만들어 둔 것 20개 중 절반쯤 없어졌어요.",
                                   comment: "Data loss prompt placeholder: what and how much"),
                    isRequired: true, isMultiline: true),
                // 사라지기 직전의 일이 원인을 거의 다 말한다(업데이트 · 기기 이전 · 재설치 · iCloud 끄기).
                LeeoFeedbackPrompt(
                    id: "loss.before",
                    label: L("사라지기 전에 무엇을 했나요?", comment: "Data loss prompt: what happened before"),
                    placeholder: L("예) 앱을 업데이트했어요. 새 아이폰으로 옮겼어요. 앱을 지웠다 다시 깔았어요.",
                                   comment: "Data loss prompt placeholder: what happened before"),
                    isRequired: true, isMultiline: true)
            ]
        case .notification:
            return [
                LeeoFeedbackPrompt(
                    id: "notify.which",
                    label: L("어떤 알림이, 언제 오기로 돼 있었나요?", comment: "Notification prompt: which and when"),
                    placeholder: L("예) 오전 9시 알림이 안 왔어요. 5분 늦게 왔어요.",
                                   comment: "Notification prompt placeholder: which and when"),
                    isRequired: true, isMultiline: true),
                LeeoFeedbackPrompt(
                    id: "notify.mode",
                    label: L("그때 집중 모드나 무음 모드였나요? (선택)", comment: "Notification prompt: focus or silent mode"),
                    placeholder: L("예) 수면 모드가 켜져 있었어요.",
                                   comment: "Notification prompt placeholder: focus mode"),
                    isRequired: false, isMultiline: false)
            ]
        case .widget:
            return [
                LeeoFeedbackPrompt(
                    id: "ext.which",
                    label: L("무엇이 어떻게 안 되나요?", comment: "Widget prompt: what is broken"),
                    placeholder: L("예) 홈 화면 위젯이 어제 값에서 멈춰 있어요. 키보드 목록에 이 앱이 안 보여요.",
                                   comment: "Widget prompt placeholder: what is broken"),
                    isRequired: true, isMultiline: true),
                LeeoBugPrompts.since
            ]
        case .display:
            return [
                LeeoFeedbackPrompt(
                    id: "display.where",
                    label: L("어느 화면의 무엇이 이상한가요?", comment: "Display prompt: where and what"),
                    placeholder: L("예) 설정 화면의 버튼 글자가 잘려요. 이 문장 번역이 어색해요.",
                                   comment: "Display prompt placeholder: where and what"),
                    isRequired: true, isMultiline: true)
            ]
        case .other:
            return LeeoFeedbackType.bug.prompts
        }
    }

    // MARK: - 부탁하는 사진

    /// 이 분류에서 부탁하는 사진. 무엇을 찍는지와 **어디서 찾는지**를 함께 말한다.
    /// 어디서 찾는지 모르면 사용자는 앱 화면을 찍어 보낸다(그 사진은 결제 기록을 말해 주지 않는다).
    public var attachments: [LeeoBugAttachment] {
        switch self {
        case .crash:
            return [LeeoBugAttachment(
                id: "crash.screen",
                title: L("멈추거나 꺼지기 직전 화면", comment: "Attachment title: screen before crash"),
                howTo: L("흰 화면이어도 괜찮아요. 옆 버튼과 볼륨 올리기 버튼을 함께 누르면 찍혀요.",
                         comment: "Attachment how-to: screen before crash"))]
        case .slow:
            return [LeeoBugAttachment(
                id: "slow.screen",
                title: L("느려지는 화면", comment: "Attachment title: slow screen"),
                howTo: L("멈칫하는 화면 한 장이면 충분해요. 무엇이 얼마나 많이 들어 있는지가 보이면 원인을 빨리 찾을 수 있어요.",
                         comment: "Attachment how-to: slow screen"))]
        case .purchase:
            return [
                LeeoBugAttachment(
                    id: "purchase.history",
                    title: L("구입 내역", comment: "Attachment title: purchase history"),
                    howTo: L("설정 앱 맨 위의 내 이름 > 미디어 및 구입 항목 > 계정 보기 > 구입 내역에서 이 앱의 결제를 찾아 찍어 주세요. 날짜와 금액만 보이면 돼요. 결제 수단은 가려도 괜찮아요.",
                             comment: "Attachment how-to: purchase history")),
                LeeoBugAttachment(
                    id: "purchase.restore",
                    title: L("구입 복원을 누른 뒤 나온 화면", comment: "Attachment title: restore result"),
                    howTo: L("구입 복원을 한 번 더 누르고, 나온 안내를 찍어 주세요.",
                             comment: "Attachment how-to: restore result"))
            ]
        case .sync:
            return [LeeoBugAttachment(
                id: "sync.icloud",
                title: L("iCloud 설정 화면", comment: "Attachment title: iCloud settings"),
                howTo: L("설정 앱 맨 위의 내 이름 > iCloud > 모두 보기에서 이 앱이 켜져 있는지 보이게 찍어 주세요. 두 기기에서 모두 찍어 주시면 더 좋아요.",
                         comment: "Attachment how-to: iCloud settings"))]
        case .dataLoss:
            return [LeeoBugAttachment(
                id: "loss.now",
                title: L("지금 남아 있는 화면", comment: "Attachment title: what remains"),
                howTo: L("지금 목록이 보이는 화면을 찍어 주세요. 사진 앱에 예전 화면을 찍어 둔 것이 있으면 함께 붙여 주세요. 무엇이 빠졌는지 견줘 볼 수 있어요.",
                         comment: "Attachment how-to: what remains"))]
        case .notification:
            return [LeeoBugAttachment(
                id: "notify.settings",
                title: L("이 앱의 알림 설정", comment: "Attachment title: notification settings"),
                howTo: L("설정 앱 > 알림 > 이 앱 화면을 찍어 주세요. 알림 허용, 잠금 화면, 배너, 사운드가 다 보이게요.",
                         comment: "Attachment how-to: notification settings"))]
        case .widget:
            return [LeeoBugAttachment(
                id: "ext.screen",
                title: L("안 되는 곳", comment: "Attachment title: where it fails"),
                howTo: L("위젯이 놓인 홈 화면이나 키보드가 떠 있는 화면을 찍어 주세요. 키보드라면 설정 앱 > 일반 > 키보드 > 키보드 화면도 함께 붙여 주세요.",
                         comment: "Attachment how-to: widget or keyboard"))]
        case .display:
            return [LeeoBugAttachment(
                id: "display.screen",
                title: L("이상한 화면", comment: "Attachment title: broken screen"),
                howTo: L("그 화면을 그대로 찍어 주세요. 번역이 어색하다면 어떻게 고치면 자연스러운지도 적어 주세요. 그대로 반영할게요.",
                         comment: "Attachment how-to: broken screen"))]
        case .other:
            return []
        }
    }

    // MARK: - 먼저 알려 둘 것

    /// 보내기 전에 꼭 알아야 하는 한 줄. 없으면 nil.
    ///
    /// ⚠️ 꺼지는 앱 · 사라진 데이터 · 동기화 문제에서 사람들이 가장 먼저 하는 일이 **앱 지우고
    ///    다시 깔기**다. 그 순간 기기 안에만 있던 데이터와 진단 기록이 같이 사라진다
    ///    (기기에만 있던 무료 혜택도 함께 사라져 "결제가 사라졌다" 는 문의로 돌아온다).
    public var caution: String? {
        switch self {
        case .crash, .dataLoss, .sync:
            return L("앱을 지우고 다시 깔기 전에 먼저 보내 주세요. 지우면 이 기기에만 있던 데이터가 함께 사라져 되살릴 수 없어요.",
                     comment: "Bug category caution: do not reinstall")
        case .purchase:
            return L("구입할 때 쓴 Apple 계정으로 로그인해 있는지 먼저 봐 주세요. 결제는 그 계정에 묶여 있어요.",
                     comment: "Bug category caution: same Apple account")
        case .slow, .notification, .widget, .display, .other:
            return nil
        }
    }

    // MARK: - 묻지 않고 붙이는 진단

    /// 이 분류에서 붙이는 진단. 무엇을 읽고 왜 읽는지는 `LeeoBugProbe` 와 `docs/BUG_CATEGORIES.md`.
    public var probes: [LeeoBugProbe] {
        switch self {
        case .crash:        return [.device]
        case .slow:         return [.device]
        case .purchase:     return [.purchases, .appReceipt, .storefront]
        case .sync:         return [.iCloud, .device]
        case .dataLoss:     return [.iCloud, .appReceipt, .device]
        case .notification: return [.notifications, .device]
        case .widget:       return [.widgets, .device]
        case .display:      return [.display]
        case .other:        return [.device]
        }
    }

    // MARK: - 어느 앱에 어느 분류를

    /// 앱의 Spec 을 보고 보여 줄 분류를 고른다.
    ///
    /// 해당 없다고 **선언한** 것만 뺀다. 선언하지 않은 것(`.unknown`)은 보여 준다 -
    /// 있는 문제를 고를 칸이 없는 것이 없는 문제의 칸이 보이는 것보다 나쁘다.
    /// 결제 분류만은 반대다. 파는 것이 없는 앱에서 결제를 고르게 하면 안 된다.
    public static func defaults(sellsSomething: Bool,
                                capabilities: LeeoCapabilities) -> [LeeoBugCategory] {
        allCases.filter { category in
            switch category {
            case .purchase:
                return sellsSomething
            case .sync:
                return !capabilities[.cloudSync].isNotApplicable
            case .notification:
                return !capabilities[.pushNotifications].isNotApplicable
            case .widget:
                return !capabilities[.widgets].isNotApplicable
            case .crash, .slow, .dataLoss, .display, .other:
                return true
            }
        }
    }

    /// Spec 으로 바로.
    public static func defaults<Spec: LeeoAppSpec>(for spec: Spec.Type) -> [LeeoBugCategory] {
        defaults(sellsSomething: Spec.paywall != nil, capabilities: Spec.capabilities)
    }
}

// MARK: - 부탁하는 사진 하나

public struct LeeoBugAttachment: Identifiable, Sendable, Hashable {
    /// 바뀌지 않는 열쇠. 문서와 시험이 이 값으로 가리킨다.
    public let id: String
    /// 무엇을 찍는가.
    public let title: String
    /// 어디서, 어떻게 찍는가.
    public let howTo: String

    public init(id: String, title: String, howTo: String) {
        self.id = id
        self.title = title
        self.howTo = howTo
    }
}

// MARK: - 여러 분류가 함께 쓰는 칸

enum LeeoBugPrompts {
    /// 버그 칸의 "언제" 와 같은 열쇠(`when`)를 쓴다. 분류를 바꿔도 적어 둔 답이 남는다.
    static var when: LeeoFeedbackPrompt { LeeoFeedbackType.bug.prompts[0] }

    static var since: LeeoFeedbackPrompt {
        LeeoFeedbackPrompt(
            id: "since",
            label: L("언제부터 그랬나요? (선택)", comment: "Bug prompt: since when"),
            placeholder: L("예) 지난주 업데이트 뒤부터요.", comment: "Bug prompt placeholder: since when"),
            isRequired: false, isMultiline: false)
    }
}

// MARK: - 선언 상태 도우미

extension LeeoCapabilityState {
    var isNotApplicable: Bool {
        if case .notApplicable = self { return true }
        return false
    }
}
