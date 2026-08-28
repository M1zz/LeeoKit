//
//  LeeoCloudPage.swift
//  LeeoKit
//
//  CloudKit 조회를 "한 번에 다"가 아니라 페이지로 나눠 받는다.
//
//  서버는 한 요청에 담을 수 있는 레코드를 400개로 못 박아 두었다. resultsLimit에
//  그보다 큰 값을 주면 조회가 통째로 실패한다:
//
//      "Your request contains 900 items which is more than the maximum
//       number of items in a single request (400)"  (CKError 4)
//
//  즉 설치가 400을 넘는 순간, 지금까지 잘 되던 통계 화면이 이 에러 하나로 전부
//  0이 된다. 그래서 조회는 항상 작은 페이지로 요구하고 커서로 이어 받는다.
//
//  나눠 받는 순간 화면에는 **새로운 의무**가 생긴다. 숫자가 낮게 떠 있을 때 그게
//  "아직 받는 중"인지 "다 받았는데 원래 그만큼"인지 "중간에 끊긴 것"인지 사람이
//  알 수 없기 때문이다. 셋은 해야 할 일이 완전히 다르다 — 기다리기 / 그대로 믿기 /
//  다시 받기. 그래서 이 파일은 데이터와 함께 **어디까지 왔고 왜 멈췄는지**를 같이
//  넘긴다(`LeeoCloudProgress`). 화면이 그걸 말하지 않으면 아무도 모른다.
//

import Foundation
import CloudKit

/// 조회가 멈춘 이유. `nil`이면 아직 받는 중이라는 뜻이다.
public enum LeeoCloudStop: Sendable, Equatable {
    /// 서버가 더 줄 게 없다고 했다 — **이게 전부다.**
    case exhausted
    /// 상한(`limit`)에 걸려 우리가 멈췄다 — 서버엔 더 있다.
    case reachedLimit
    /// 화면이 사라지는 등으로 취소됐다.
    case cancelled
    /// 중간 페이지가 실패했다 — 받은 데까지가 결과다.
    case failed(String)

    /// 받아 온 것이 완전한가. 화면이 "전부"라고 말해도 되는지의 기준.
    public var isComplete: Bool { self == .exhausted }
}

/// 한 페이지가 도착할 때마다(그리고 마지막에 한 번 더) 화면에 넘기는 중간 보고.
public struct LeeoCloudProgress<T: Sendable>: Sendable {
    /// 지금까지 모인 전부. 화면은 이걸 그대로 그리면 된다.
    public let items: [T]
    /// 지금까지 받은 페이지 수 — 진행이 실제로 일어나고 있다는 유일한 증거.
    public let pages: Int
    /// 멈춘 이유. 아직 받는 중이면 `nil`.
    public let stop: LeeoCloudStop?

    /// 더 받을 게 없는가 (이유가 무엇이든 조회는 끝났다).
    public var isFinished: Bool { stop != nil }
    /// 끝났고, 그것이 완전한 결과인가.
    public var isComplete: Bool { stop?.isComplete == true }

    public init(items: [T], pages: Int, stop: LeeoCloudStop?) {
        self.items = items
        self.pages = pages
        self.stop = stop
    }

    /// 항목을 손질해서(필터·정렬) 같은 진행 상태로 다시 감싼다.
    public func mapItems<U: Sendable>(_ transform: ([T]) -> [U]) -> LeeoCloudProgress<U> {
        LeeoCloudProgress<U>(items: transform(items), pages: pages, stop: stop)
    }
}

public enum LeeoCloudPage {

    /// 한 요청에 요구할 레코드 수. 서버 상한보다 넉넉히 낮게 잡는다.
    public static let size = 200

    /// 서버가 거부하기 시작하는 경계. 이 값을 넘는 `resultsLimit`은 만들지 않는다.
    public static let serverMaximum = 400

    /// 커서로 페이지를 이어 받으며 레코드를 모은다.
    ///
    /// - Parameters:
    ///   - query: 실행할 쿼리. 정렬을 붙이려면 그 필드가 Sortable로 배포돼 있어야 한다.
    ///   - limit: 전체 상한(안전장치). 서버로 나가는 요청 크기와는 무관하다.
    ///   - pageSize: 한 요청에 요구할 개수. `serverMaximum`으로 잘린다.
    ///   - transform: 레코드 1건을 화면이 쓰는 값으로 바꾼다. `nil`이면 버린다.
    ///     `CKRecord`가 이 함수 밖으로 새어나가지 않도록 변환을 여기서 끝낸다.
    ///   - onProgress: 페이지마다 **지금까지 모인 전부**를, 마지막엔 **멈춘 이유까지**
    ///     붙여서 넘긴다. 화면을 그 자리에서 갱신하라고 있는 것이므로 메인 액터에서 부른다.
    /// - Returns: 모은 전부. 중간 페이지가 실패하면 거기까지가 결과다 —
    ///   **첫 페이지부터 실패했을 때만** 에러를 던진다(권한/스키마 문제는 말해야 하므로).
    @discardableResult
    public static func collect<T: Sendable>(
        _ query: CKQuery,
        in database: CKDatabase,
        limit: Int,
        pageSize: Int = size,
        transform: (CKRecord) -> T?,
        onProgress: (@MainActor (LeeoCloudProgress<T>) -> Void)? = nil
    ) async throws -> [T] {
        var collected: [T] = []
        var cursor: CKQueryOperation.Cursor?
        var pages = 0
        var stop: LeeoCloudStop = .exhausted
        let perRequest = max(1, min(pageSize, serverMaximum))

        while true {
            let want = min(perRequest, max(1, limit - collected.count))
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                       queryCursor: CKQueryOperation.Cursor?)
            do {
                if let cursor {
                    page = try await database.records(continuingMatchFrom: cursor, resultsLimit: want)
                } else {
                    page = try await database.records(matching: query, resultsLimit: want)
                }
            } catch {
                // 한 건도 못 받았으면 이유를 알려야 화면이 "권한 없음"인지 "스키마 없음"인지
                // 말할 수 있다. 이미 받아 둔 게 있으면 그게 오늘의 답이고, 대신 부분이라고 밝힌다.
                if collected.isEmpty { throw error }
                stop = .failed((error as NSError).localizedDescription)
                break
            }

            pages += 1
            for record in page.matchResults.compactMap({ try? $0.1.get() }) {
                if let value = transform(record) { collected.append(value) }
            }
            if let onProgress {
                let soFar = LeeoCloudProgress(items: collected, pages: pages, stop: nil)
                await onProgress(soFar)
            }

            if Task.isCancelled { stop = .cancelled; break }
            cursor = page.queryCursor
            if cursor == nil { stop = .exhausted; break }
            if collected.count >= limit { stop = .reachedLimit; break }
        }

        if let onProgress {
            let final = LeeoCloudProgress(items: collected, pages: pages, stop: stop)
            await onProgress(final)
        }
        return collected
    }
}
