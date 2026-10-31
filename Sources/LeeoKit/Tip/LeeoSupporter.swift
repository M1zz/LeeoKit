//
//  LeeoSupporter.swift
//  LeeoKit
//
//  **후원 보상**. 낸 팁을 점수로 쌓아 단계(응원자 · 단골 · 후견인)를 정한다. 기능은 열지 않는다 —
//  보상은 알아봐 주기(배지 · 고마운 사람들), 꾸밈 하나(후원자 아이콘), 먼저 듣기(미리 보고 한 표 · 베타)뿐이다.
//
//  - 점수: 작은 칸 1 · 중간 칸 3 · 큰 칸 10 (대략 달러 값). **리이오의 모든 앱 점수를 합친다.**
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
    /// 처음 한 번.
    case supporter = 1
    /// 누적 10점.
    case regular
    /// 누적 30점.
    case patron

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// 이 단계에 드는 점수.
    public var need: Int {
        switch self {
        case .supporter: return 1
        case .regular: return 10
        case .patron: return 30
        }
    }

    /// 점수가 든 가장 높은 단계. 0점이면 nil.
    public static func of(points: Int) -> LeeoSupporterLevel? {
        allCases.last { points >= $0.need }
    }

    public var next: LeeoSupporterLevel? { LeeoSupporterLevel(rawValue: rawValue + 1) }

    public var title: String {
        switch self {
        case .supporter: return L("응원자", comment: "Supporter level 1: first tip")
        case .regular: return L("단골", comment: "Supporter level 2: 10 points")
        case .patron: return L("후견인", comment: "Supporter level 3: 30 points")
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
    /// 칸 크기의 점수.
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
