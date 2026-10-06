//
//  LeeoFeedbackReplies.swift
//  LeeoKit
//
//  보낸 의견에 개발자가 **답장**을 다는 길.
//
//  왜 필요한가: 회신 이메일은 선택이라 대부분 비어 온다. 그러면 "어떤 화면에서요?" 한 마디를
//  물을 길이 없어서, 짧게 들어온 의견은 짐작으로 고치거나 묵히게 된다. 이메일 없이도 답이
//  닿아야 한다.
//
//  어떻게:
//   - 보낼 때 받은 recordName 을 이 기기에 적어 둔다(`SentFeedback` 장부).
//   - 개발자는 공용 DB 에 `reply-<recordName>` 이름으로 답장 레코드를 하나 만든다.
//   - 앱은 장부의 이름들로 **ID 를 바로 집어 읽는다.** 쿼리가 아니라서 Queryable 인덱스가
//     필요 없고, 남의 답장을 훑어볼 길도 없다(recordName 은 추측할 수 없는 UUID 다).
//
//  ⚠️ 피드백 레코드 자체에는 쓰지 않는다. 공용 DB 에서는 남이 만든 레코드를 고칠 수 없다
//     (완료 표시를 로컬로 옮긴 것과 같은 이유, `LeeoFeedbackService.fetchAll`).
//
//  ⚠️ 답장 타입이 아직 Production 에 없으면 읽기가 실패한다. 그때는 **조용히 빈 결과**다.
//     답장 기능 때문에 의견 보내기나 설정 화면이 깨지면 안 된다.
//

import Foundation
import CloudKit

// MARK: - 보낸 의견 한 건 (이 기기 장부)

public struct LeeoSentFeedback: Codable, Identifiable, Hashable, Sendable {
    /// 피드백 레코드의 recordName.
    public let id: String
    public let type: String
    /// 목록에서 알아보게 할 앞부분. 전체 글은 서버에 있다.
    public let excerpt: String
    public let sentAt: Date
    public var reply: String?
    public var repliedAt: Date?
    /// 답장을 열어 봤는가. 답장이 고쳐지면 다시 false 가 된다.
    public var replySeen: Bool

    public var hasUnreadReply: Bool { reply != nil && !replySeen }

    public init(id: String, type: String, excerpt: String, sentAt: Date,
                reply: String? = nil, repliedAt: Date? = nil, replySeen: Bool = false) {
        self.id = id
        self.type = type
        self.excerpt = excerpt
        self.sentAt = sentAt
        self.reply = reply
        self.repliedAt = repliedAt
        self.replySeen = replySeen
    }
}

// MARK: - 장부 다루기 (순수 규칙 - 시험이 여기를 본다)

public enum LeeoFeedbackLedger {

    /// 장부에 남기는 최대 건수. 오래된 것부터 버린다.
    public static let capacity = 30
    /// 이보다 오래된 의견에는 답장을 더 찾지 않는다(읽기 횟수를 줄인다). 장부에서는 지우지 않는다.
    public static let replyLookback: TimeInterval = 180 * 24 * 3600

    /// 답장 레코드의 이름. 피드백 하나에 답장 하나라 이름만으로 찾는다.
    public static func replyRecordName(forFeedback id: String) -> String { "reply-\(id)" }

    /// 앞부분 120자. 줄바꿈은 한 칸으로.
    public static func excerpt(of message: String) -> String {
        let flat = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flat.count > 120 ? String(flat.prefix(120)) + "…" : flat
    }

    /// 새로 보낸 것을 맨 앞에 넣고 용량을 넘긴 꼬리를 자른다.
    public static func inserting(_ item: LeeoSentFeedback, into list: [LeeoSentFeedback]) -> [LeeoSentFeedback] {
        Array(([item] + list.filter { $0.id != item.id }).prefix(capacity))
    }

    /// 서버에서 읽은 답장을 장부에 합친다.
    ///
    /// ⚠️ 답장이 **바뀌었을 때만** 안 읽음으로 돌린다. 같은 답장을 다시 읽어 올 때마다
    ///    배지가 되살아나면 사람은 배지를 무시하게 된다.
    public static func merging(replies: [String: (message: String, date: Date)],
                               into list: [LeeoSentFeedback]) -> [LeeoSentFeedback] {
        list.map { item in
            guard let reply = replies[item.id] else { return item }
            var next = item
            let changed = item.reply != reply.message
            next.reply = reply.message
            next.repliedAt = reply.date
            if changed { next.replySeen = false }
            return next
        }
    }

    /// 답장을 찾아볼 의견들.
    public static func lookupIDs(in list: [LeeoSentFeedback], now: Date = Date()) -> [String] {
        list.filter { now.timeIntervalSince($0.sentAt) < replyLookback }.map(\.id)
    }
}

// MARK: - 서비스

extension LeeoFeedbackService {

    private var ledgerKey: String {
        "leeo.feedback.sent.\(config.containerIdentifier).\(config.recordType).\(config.appIdentifier ?? "-")"
    }

    /// 이 기기에서 보낸 의견들. 최신이 앞.
    public var sentFeedback: [LeeoSentFeedback] {
        guard let data = UserDefaults.standard.data(forKey: ledgerKey),
              let list = try? JSONDecoder().decode([LeeoSentFeedback].self, from: data) else { return [] }
        return list
    }

    private func saveLedger(_ list: [LeeoSentFeedback]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: ledgerKey)
    }

    /// 안 읽은 답장 수. 설정 화면의 배지가 이 값을 쓴다(서버를 읽지 않는다).
    public var unreadReplyCount: Int {
        sentFeedback.filter(\.hasUnreadReply).count
    }

    /// 보낸 의견을 장부에 적는다. `submit` 이 성공하면 부른다.
    func recordSent(id: String, type: String, message: String) {
        let item = LeeoSentFeedback(id: id, type: type,
                                    excerpt: LeeoFeedbackLedger.excerpt(of: message),
                                    sentAt: Date())
        saveLedger(LeeoFeedbackLedger.inserting(item, into: sentFeedback))
    }

    /// 답장을 열어 봤다고 적는다.
    public func markRepliesSeen() {
        let list = sentFeedback.map { item -> LeeoSentFeedback in
            var next = item
            if next.reply != nil { next.replySeen = true }
            return next
        }
        saveLedger(list)
    }

    /// 서버에서 답장을 읽어 장부에 합친다. 반환값은 안 읽은 답장 수.
    ///
    /// ⚠️ 실패해도 던지지 않는다. 답장 타입이 아직 배포 전이거나 iCloud 가 꺼져 있어도
    ///    설정 화면은 그대로 떠야 한다. 그때는 장부에 있던 값으로 답한다.
    @discardableResult
    public func refreshReplies() async -> Int {
        let ids = LeeoFeedbackLedger.lookupIDs(in: sentFeedback)
        guard !ids.isEmpty else { return unreadReplyCount }

        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        let recordIDs = ids.map { CKRecord.ID(recordName: LeeoFeedbackLedger.replyRecordName(forFeedback: $0)) }
        var found: [String: (message: String, date: Date)] = [:]
        do {
            let results = try await db.records(for: recordIDs)
            for (recordID, result) in results {
                guard case .success(let record) = result,
                      let message = record["message"] as? String,
                      !message.isEmpty else { continue }
                let feedbackID = (record["feedbackID"] as? String)
                    ?? String(recordID.recordName.dropFirst("reply-".count))
                found[feedbackID] = (message, record.modificationDate ?? Date())
            }
        } catch {
            print("⚠️ [LeeoFeedbackService.refreshReplies] 답장 조회 실패(배포 전이면 정상): \(error)")
            return unreadReplyCount
        }

        if !found.isEmpty {
            saveLedger(LeeoFeedbackLedger.merging(replies: found, into: sentFeedback))
        }
        print("📬 [LeeoFeedbackService.refreshReplies] 답장 \(found.count)건 · 안 읽음 \(unreadReplyCount)건")
        return unreadReplyCount
    }

    // MARK: 개발자 쪽

    /// 피드백 한 건에 답장을 쓴다(이미 있으면 고친다). 개발자 계정에서만 쓴다.
    ///
    /// ⚠️ 답장 레코드는 **개발자가 만든 것**이라 개발자가 고칠 수 있다. 피드백 레코드와 다르다.
    public func sendReply(toFeedback feedbackID: String, message: String) async throws {
        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        let recordID = CKRecord.ID(recordName: LeeoFeedbackLedger.replyRecordName(forFeedback: feedbackID))
        let record: CKRecord
        if let existing = try? await db.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: config.replyRecordType, recordID: recordID)
        }
        record["feedbackID"] = feedbackID
        record["message"] = message
        if let appId = config.appIdentifier { record["appId"] = appId }
        _ = try await db.save(record)
        print("✅ [LeeoFeedbackService.sendReply] \(feedbackID) 에 답장")
    }

    /// 피드백 한 건에 달린 답장. 없으면 nil.
    public func fetchReply(forFeedback feedbackID: String) async -> String? {
        let db = CKContainer(identifier: config.containerIdentifier).publicCloudDatabase
        let recordID = CKRecord.ID(recordName: LeeoFeedbackLedger.replyRecordName(forFeedback: feedbackID))
        return (try? await db.record(for: recordID))?["message"] as? String
    }
}
