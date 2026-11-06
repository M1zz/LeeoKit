//
//  LeeoSupporter.swift
//  LeeoKit
//
//  **후원 보상**. 낸 팁으로 단계(응원자 · 단골 · 후견인)를 정한다. 기능은 열지 않는다.
//  보상은 알아봐 주기(배지 · 고마운 사람들), 꾸밈 하나(후원자 아이콘), 먼저 듣기(미리 보고 한 표 · 베타)뿐이다.
//
//  - **단계 하나가 팁 칸 하나다.** 커피 한 잔이면 응원자, 간식 한 번이면 단골, 든든한 한 끼면 후견인.
//    작은 칸을 여러 번 내도 합쳐서 오른다(커피 세 잔은 간식 한 번과 같다). **리이오의 모든 앱 것을 합친다.**
//  - 안쪽에서는 칸 값을 1 · 3 · 10 으로 더해 센다. 화면에는 숫자를 보이지 않고 팁 이름으로 말한다.
//    ⚠️ 2026-11 전에는 단계 문턱이 10 · 30 이고 점수를 보였다. 간식 한 번(3)을 낸 사람이 "단골을 샀는데
//       응원자, 7점 남음" 으로 읽었다(골드위크 피드백). 문턱을 칸 값에 맞췄다. 낮아지기만 해서 내려가는 사람은 없다.
//  - 기록: 결제 하나가 한 줄("번들|결제 번호|점수"). 이 기기 · 다른 기기 · 다른 앱의 줄을 합집합으로 모은다.
//    같은 결제는 어느 기기에서 와도 번호가 같아 두 번 세지 않는다.
//  - iCloud: 피드백과 같은 컨테이너(`Spec.feedback.containerIdentifier`)의 **개인** DB, 기록 하나(`supporter`).
//    언제나 평생 패스와 같은 길이라 앱마다 새 권한이 필요 없다.
//  ⚠️ 새 기록 종류(`LeeoSupporter`)는 CloudKit 콘솔에서 운영 스키마로 내보내야 출시 빌드가 쓴다.
//     그 전에는 저장이 실패하고 이 기기의 점수만 보인다(앱은 멀쩡하다).
//

import Foundation
import CloudKit

// MARK: - 단계

public enum LeeoSupporterLevel: Int, CaseIterable, Comparable, Sendable {
    /// 커피 한 잔.
    case supporter = 1
    /// 간식 한 번(또는 커피 세 잔).
    case regular
    /// 든든한 한 끼.
    case patron

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// 이 단계에 이르는 팁 칸.
    var tip: LeeoTipTier.Size {
        switch self {
        case .supporter: return .small
        case .regular: return .medium
        case .patron: return .large
        }
    }

    /// 이 단계에 드는 값. 이 단계의 팁 칸 값과 같다.
    public var need: Int { LeeoSupporterLedger.points(for: tip) }

    /// 이 단계에 이르는 팁 이름("간식 한 번").
    public var tipTitle: String { LeeoTipTier(size: tip).title }

    /// 점수가 든 가장 높은 단계. 0점이면 nil.
    public static func of(points: Int) -> LeeoSupporterLevel? {
        allCases.last { points >= $0.need }
    }

    public var next: LeeoSupporterLevel? { LeeoSupporterLevel(rawValue: rawValue + 1) }

    public var title: String {
        switch self {
        case .supporter: return L("응원자", comment: "Supporter level 1: first tip")
        case .regular: return L("단골", comment: "Supporter level 2: a snack-sized tip")
        case .patron: return L("후견인", comment: "Supporter level 3: a meal-sized tip")
        }
    }

    /// 이 단계에서 받는 것 한 줄.
    public var perks: String {
        switch self {
        case .supporter:
            return L("후원자 배지 · 고마운 사람들에 이름", comment: "Supporter level 1 perks")
        case .regular:
            return L("후원자 전용 앱 아이콘 · 다음 기능 미리 보고 한 표", comment: "Supporter level 2 perks")
        case .patron:
            return L("새 버전 베타(TestFlight) 초대", comment: "Supporter level 3 perks")
        }
    }

    public var symbol: String {
        switch self {
        case .supporter: return "heart.fill"
        case .regular: return "star.fill"
        case .patron: return "crown.fill"
        }
    }
}

// MARK: - 점수 장부 (순수 함수)

enum LeeoSupporterLedger {
    /// 칸 크기의 값. 단계 문턱(`LeeoSupporterLevel.need`)이 이 값이다.
    static func points(for size: LeeoTipTier.Size) -> Int {
        switch size {
        case .small: return 1
        case .medium: return 3
        case .large: return 10
        }
    }

    static func entry(bundleID: String, transactionID: String, points: Int) -> String {
        "\(bundleID)|\(transactionID)|\(points)"
    }

    /// (번들, 결제 번호, 점수). 모양이 틀린 줄은 nil.
    static func parse(_ line: String) -> (bundleID: String, transactionID: String, points: Int)? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, let p = Int(parts[2]), p > 0 else { return nil }
        return (String(parts[0]), String(parts[1]), p)
    }

    /// 두 장부의 합집합. 같은 결제(번들 + 번호)는 한 줄만, 먼저 본 줄을 남긴다.
    static func merge(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in a + b {
            guard let e = parse(line), seen.insert("\(e.bundleID)|\(e.transactionID)").inserted else { continue }
            out.append(line)
        }
        return out
    }

    static func total(_ lines: [String]) -> Int {
        lines.compactMap(parse).reduce(0) { $0 + $1.points }
    }

    static func lines(_ lines: [String], of bundleID: String) -> [String] {
        lines.filter { parse($0)?.bundleID == bundleID }
    }
}

// MARK: - iCloud

enum LeeoSupporterCloud {
    static let recordType = "LeeoSupporter"
    static let recordName = "supporter"
    static let field = "tips"

    /// 장부를 iCloud 의 것과 합치고, 늘었으면 올린다. 합친 장부를 돌려준다. 실패하면 nil(이 기기 것만 쓴다).
    static func sync(_ local: [String], containerIdentifier: String) async -> [String]? {
        guard !runningTests else { return nil }
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        let id = CKRecord.ID(recordName: recordName)
        do {
            let record: CKRecord
            do {
                record = try await database.record(for: id)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: recordType, recordID: id)
            }
            let cloud = (record[field] as? [String]) ?? []
            let merged = LeeoSupporterLedger.merge(cloud, local)
            if merged.count != cloud.count {
                record[field] = merged as CKRecordValue
                _ = try await database.save(record)
            }
            return merged
        } catch {
            print("⚠️ [LeeoSupporter.sync] iCloud 와 후원 기록을 맞추지 못했다: \(error.localizedDescription)")
            return nil
        }
    }

    /// 단위 시험 안에서는 iCloud 에 닿지 않는다(컨테이너 권한이 없어 그 자리에서 죽는다).
    private static var runningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
}
