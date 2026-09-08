//
//  LeeoFamilySynergy.swift
//  LeeoKit
//
//  앱 두세 개가 **한 상황 안에서** 어떻게 이어지는지를 적는 짧은 이야기.
//
//  왜 목록이 아니라 이야기인가: "이런 앱도 있어요"는 아무도 안 누른다. 사람이 움직이는 건
//  자기가 겪는 장면을 알아볼 때다. 그래서 각 조각은 장면(scene) 하나로 시작하고,
//  세 박자(beats) 동안 앱이 하나씩 들어오고, 마지막 한 줄(payoff)로 무엇이 달라졌는지 말한다.
//
//  규칙 하나: **한 이야기에 앱을 넷 이상 넣지 않는다.** 넷부터는 이야기가 아니라 카탈로그가 된다.
//

import Foundation

public struct LeeoFamilySynergy: Identifiable, Sendable, Equatable {
    public let id: String

    /// 이야기에 나오는 앱들 (`LeeoFamilyApp.id`). 나오는 순서가 곧 이야기의 순서다.
    public let appIDs: [String]

    /// 이야기의 제목. 기능이 아니라 **하루의 한 장면**을 가리킨다.
    public let title: String
    /// 언제의 이야기인가. 한 줄.
    public let scene: String
    /// 박자. 한 줄에 앱 하나씩 들어온다.
    public let beats: [String]
    /// 그래서 무엇이 달라졌나. 한 줄.
    public let payoff: String

    public init(
        id: String,
        appIDs: [String],
        title: String,
        scene: String,
        beats: [String],
        payoff: String
    ) {
        self.id = id
        self.appIDs = appIDs
        self.title = title
        self.scene = scene
        self.beats = beats
        self.payoff = payoff
    }

    public func involves(_ appID: String?) -> Bool {
        guard let appID else { return false }
        return appIDs.contains(appID)
    }
}
