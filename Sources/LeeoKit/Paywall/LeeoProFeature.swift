//
//  LeeoProFeature.swift
//  LeeoKit
//
//  페이월이 "방금 부딪힌 잠금 기능"을 앞세워 보여줄 수 있게 하는 최소 규약.
//  체험(trial)·슬롯 한도 같은 앱마다 다른 게이트 로직은 앱에 남기고, LeeoKit 은
//  "어떤 기능을 강조해서 팔지"에 필요한 표시 정보(아이콘/제목/설명)만 요구한다.
//
//  사용 예:
//      enum Feature: String, LeeoProFeature {
//          case unlimitedDeadlines, presentationMode
//          var leeoTitle: String { ... }
//          var leeoDetail: String { ... }
//          var leeoIcon: String { ... }   // SF Symbol
//      }
//      LeeoPaywallView<MyAppSpec>(leadFeature: Feature.presentationMode)
//

import Foundation

public protocol LeeoProFeature {
    /// 잠금 기능 이름 (페이월 헤드라인/불릿).
    var leeoTitle: String { get }
    /// 한 줄 설명 — 이 기능이 왜 좋은지.
    var leeoDetail: String { get }
    /// SF Symbol 이름.
    var leeoIcon: String { get }
}
