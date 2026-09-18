//
//  LeeoFeedbackPrompt.swift
//  LeeoKit
//
//  피드백을 받을 때 **무엇을 물을지**. 유형마다 다르다.
//
//  왜 필요한가: 받아 보니 "왜 오늘은 미리 준비된 답변을 만들 수 없나요?" 한 줄만 오는 일이
//  잦았다. 무슨 화면에서, 언제, 무엇을 하다가 그랬는지가 없으면 재현할 수가 없고,
//  물어보려면 회신 이메일이 있어야 하는데 그것도 없을 때가 많다. 빈 칸 하나를 주고
//  "자유롭게 적어주세요" 라고 하면 자유롭게 적히는 것은 결론뿐이다.
//
//  그래서 칸을 나눠 묻는다. 버그면 언제·무엇을 하다가·어떤 일이 일어났는지, 제안이면
//  어떤 상황에서 쓰고 싶은지(사용 예)까지. 답을 조립해 한 덩어리 글로 보내므로
//  받는 쪽(CloudKit 레코드의 `message`)은 그대로다. 스키마를 건드리지 않는다.
//

import Foundation

// MARK: - 질문 하나

public struct LeeoFeedbackPrompt: Identifiable, Sendable, Hashable {
    /// 조립한 글에 붙는 꼬리표이자 답을 담아 두는 열쇠. **번역해도 바뀌지 않는다.**
    public let id: String
    /// 사람에게 보이는 질문.
    public let label: String
    /// 빈 칸에 흐리게 적어 둘 보기. 무엇을 적어야 하는지는 예시가 가장 빨리 말한다.
    public let placeholder: String
    /// 이 칸이 비면 보내기가 잠긴다.
    public let isRequired: Bool
    /// 여러 줄인가(증상 설명) 한 줄인가(언제).
    public let isMultiline: Bool

    public init(id: String, label: String, placeholder: String,
                isRequired: Bool, isMultiline: Bool) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.isMultiline = isMultiline
    }
}

// MARK: - 유형마다 무엇을 묻는가

public extension LeeoFeedbackType {

    /// 이 유형에서 칸을 나눠 물을 것들. 비어 있으면 예전처럼 자유 입력 하나만 받는다.
    ///
    /// ⚠️ 칸은 **셋을 넘기지 않는다.** 묻는 것이 많아지면 그 자리에서 창을 닫는다.
    ///    꼭 필요한 둘만 필수로 두고 나머지는 선택으로 둔다.
    var prompts: [LeeoFeedbackPrompt] {
        switch self {
        case .bug:
            return [
                LeeoFeedbackPrompt(
                    id: "when",
                    label: L("언제, 무엇을 하다가 그랬나요?", comment: "Bug prompt: when and what"),
                    placeholder: L("예) 오늘 아침, 목록에서 항목을 저장하려던 중",
                                   comment: "Bug prompt placeholder: when and what"),
                    isRequired: true, isMultiline: false),
                LeeoFeedbackPrompt(
                    id: "symptom",
                    label: L("어떤 일이 일어났나요?", comment: "Bug prompt: symptom"),
                    placeholder: L("예) 앱이 그대로 닫혔어요. 다시 열면 적던 것이 사라져 있어요.",
                                   comment: "Bug prompt placeholder: symptom"),
                    isRequired: true, isMultiline: true),
                LeeoFeedbackPrompt(
                    id: "expected",
                    label: L("원래는 어떻게 되어야 했나요? (선택)", comment: "Bug prompt: expected"),
                    placeholder: L("예) 적던 것이 그대로 남아 있어야 해요.",
                                   comment: "Bug prompt placeholder: expected"),
                    isRequired: false, isMultiline: true)
            ]
        case .feature:
            return [
                LeeoFeedbackPrompt(
                    id: "wish",
                    label: L("어떤 기능이 있으면 좋겠나요?", comment: "Feature prompt: wish"),
                    placeholder: L("예) 항목을 폴더로 묶고 싶어요.",
                                   comment: "Feature prompt placeholder: wish"),
                    isRequired: true, isMultiline: true),
                LeeoFeedbackPrompt(
                    id: "usecase",
                    label: L("어떤 상황에서 쓰실 것 같나요?", comment: "Feature prompt: use case"),
                    placeholder: L("예) 일과 집에서 쓰는 것이 섞여서, 필요한 쪽만 보고 싶어요.",
                                   comment: "Feature prompt placeholder: use case"),
                    isRequired: true, isMultiline: true)
            ]
        case .improvement:
            return [
                LeeoFeedbackPrompt(
                    id: "pain",
                    label: L("어떤 점이 불편하셨나요?", comment: "Improvement prompt: pain"),
                    placeholder: L("예) 항목이 많아지면 찾는 데 시간이 걸려요.",
                                   comment: "Improvement prompt placeholder: pain"),
                    isRequired: true, isMultiline: true),
                LeeoFeedbackPrompt(
                    id: "usecase",
                    label: L("그때 무엇을 하고 계셨나요?", comment: "Improvement prompt: use case"),
                    placeholder: L("예) 밖에서 급하게 하나를 찾아야 했을 때요.",
                                   comment: "Improvement prompt placeholder: use case"),
                    isRequired: true, isMultiline: true)
            ]
        case .question, .other:
            // 궁금한 것과 그 밖의 말은 칸을 나누지 않는다. 물어볼 것이 정해져 있지 않다.
            return []
        }
    }

    /// 사진을 함께 받으면 좋은 유형인가. 증상은 글보다 화면 한 장이 빠르다.
    var invitesScreenshot: Bool {
        switch self {
        case .bug, .improvement: return true
        case .feature, .question, .other: return false
        }
    }
}

// MARK: - 답을 한 덩어리 글로

/// 나눠 받은 답을 보내는 글 하나로 조립한다.
///
/// ⚠️ 레코드의 `message` 필드 하나에 담는다. 칸마다 필드를 새로 만들면 앱마다
///    Production 스키마를 다시 배포해야 하고, 예전 앱이 보낸 글과 모양이 갈린다.
///    꼬리표를 붙여 한 글로 만들면 받는 화면도, 메일 폴백도 고칠 것이 없다.
public enum LeeoFeedbackComposer {

    /// 답이 비어 있는 필수 칸들. 보내기를 잠글지 여기서 정한다.
    public static func missingRequired(type: LeeoFeedbackType,
                                       answers: [String: String]) -> [LeeoFeedbackPrompt] {
        type.prompts.filter { prompt in
            guard prompt.isRequired else { return false }
            return trimmed(answers[prompt.id]).isEmpty
        }
    }

    /// 칸을 나눠 묻지 않는 유형(궁금한 것·기타)은 자유 입력만 있으면 된다.
    public static func canSend(type: LeeoFeedbackType,
                              answers: [String: String],
                              note: String) -> Bool {
        if type.prompts.isEmpty { return !trimmed(note).isEmpty }
        return missingRequired(type: type, answers: answers).isEmpty
    }

    /// 보낼 글. 꼬리표 + 답을 빈 줄로 띄워 잇고, 자유 입력은 맨 뒤에 붙인다.
    public static func compose(type: LeeoFeedbackType,
                               answers: [String: String],
                               note: String) -> String {
        var blocks: [String] = []
        for prompt in type.prompts {
            let answer = trimmed(answers[prompt.id])
            guard !answer.isEmpty else { continue }
            blocks.append("\(prompt.label)\n\(answer)")
        }
        let extra = trimmed(note)
        if !extra.isEmpty {
            if blocks.isEmpty {
                blocks.append(extra)
            } else {
                blocks.append("\(L("덧붙임", comment: "Composed feedback: extra note label"))\n\(extra)")
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 붙인 사진 한 장

#if canImport(UIKit)
import UIKit

/// 화면에 보여 줄 이미지와 보낼 JPEG 을 함께 들고 있는다.
/// 보낼 때 다시 만들지 않으려고 고르는 순간 한 번만 줄인다.
struct LeeoFeedbackShot: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpeg: Data
}
#endif
