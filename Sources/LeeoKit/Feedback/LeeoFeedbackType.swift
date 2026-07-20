//
//  LeeoFeedbackType.swift
//  LeeoKit
//
//  피드백 문의 유형. rawValue는 CloudKit 레코드의 type 필드에 그대로 저장된다 — 변경 금지.
//

import Foundation

public enum LeeoFeedbackType: String, CaseIterable, Sendable {
    case bug      = "bug"
    case feature  = "feature"
    case question = "question"
    case other    = "other"

    public var localizedName: String {
        switch self {
        case .bug:      return L("버그 신고", comment: "Feedback type: bug report")
        case .feature:  return L("기능 제안", comment: "Feedback type: feature request")
        case .question: return L("사용 방법 문의", comment: "Feedback type: usage question")
        case .other:    return L("기타", comment: "Feedback type: other")
        }
    }

    public var icon: String {
        switch self {
        case .bug:      return "ladybug"
        case .feature:  return "lightbulb"
        case .question: return "questionmark.circle"
        case .other:    return "ellipsis.bubble"
        }
    }

    /// 이메일 폴백 제목: "[버그 신고] MyApp 1.2.3"
    public func emailSubject(appName: String) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return "[\(localizedName)] \(appName) \(version)"
    }
}
