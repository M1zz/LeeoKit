//
//  LeeoCrashStack.swift
//  LeeoKit
//
//  MetricKit 콜스택(MXCallStackTree JSON)을 **프레임 한 줄짜리 텍스트**로 편다. 0번이 죽은 자리다.
//
//  ⚠️ `jsonRepresentation()` 을 그대로 잘라 보내지 말 것. 그 JSON 은 들여쓴 중첩 구조라
//     프레임 하나가 300자를 먹고, 4000자에서 자르면 13프레임만 남는다. 게다가 `binaryName` 은
//     `subFrames` **뒤에** 오는 필드라 한 번도 담기지 않는다. LeeoKit 3.16 까지의
//     `LeeoDiagnostics` 가 그렇게 보내서 허브의 크래시가 전부 "옛 형식(분석 불가)"이 됐다.
//     (클립키보드 docs/postmortem/CRASH_STACK_TRUNCATION.md · CRASH_STACK_UPSIDE_DOWN.md)
//
//  MetricKit 에 기대지 않는 순수 함수라 macOS `swift test` 에서도 시험한다.
//
//  나오는 모양:
//  ```
//   0 Goldweek +820588
//   1 SwiftUI +1042364
//   2 UIKitCore +558784
//  ... 뿌리 쪽 42프레임 생략
//  --
//  @ Goldweek 794FD256-8A8D-3C8D-91AA-AAC27EF3512C
//  ```
//  끝의 `@ 이름 UUID` 범례로 dSYM 을 찾아 `atos` 로 되돌린다.
//

import Foundation

public enum LeeoCrashStack {

    /// 한 줄이 30자 안팎이라 8000자면 200프레임쯤 들어간다.
    public static let defaultMaxLength = 8000

    /// - Parameter appBinary: 앱 자신의 실행 파일 이름. 잘라야 할 때도 이 바이너리의 프레임은 남긴다.
    public static func text(fromJSON data: Data, maxLength: Int = defaultMaxLength,
                            appBinary: String? = Bundle.main.executableURL?.lastPathComponent) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "-"

        let parsed = framesByParsing(data)
        var frames = parsed.frames
        var binaries = parsed.binaries
        // 못 읽었으면 글자로라도 건져 본다. 아래 함수 머리말 참고.
        if frames.isEmpty {
            frames = leafFirst(Array(framesBySalvaging(raw).reversed()))
            binaries = []
        }
        guard !frames.isEmpty else { return String(raw.prefix(maxLength)) }

        // 오프셋을 함수 이름으로 되돌리려면 **어느 dSYM 인지** 알아야 하고, 그걸 가리키는
        // 것이 바이너리 UUID 다. 프레임마다 붙이면 줄 길이가 두 배가 되므로
        // 바이너리마다 한 번, 맨 끝에 모아 적는다. 앱 자신은 깊이와 상관없이 맨 앞에.
        if let appBinary, let index = binaries.firstIndex(where: { $0.name == appBinary }) {
            binaries.insert(binaries.remove(at: index), at: 0)
        }
        let legend = binaries.prefix(12).map { "@ \($0.name) \($0.uuid)" }
        let legendText = legend.isEmpty ? "" : "\n--\n" + legend.joined(separator: "\n")
        // 생략 안내가 들어갈 자리도 남겨 둔다.
        let budget = maxLength - legendText.count - 40

        let isApp: (String) -> Bool = { frame in
            appBinary.map { binaryName(of: frame) == $0 } ?? false
        }
        return fit(frames, budget: budget, keep: isApp).joined(separator: "\n") + legendText
    }

    /// 상한 안에 들 줄을 고른다. 다 들어가면 전부, 아니면 **잎부터** 담되 앱 프레임은 깊어도 남긴다.
    ///
    /// ⚠️ 잎부터만 담으면 SwiftUI 멈춤에서 앱 코드가 사라진다. 그런 스택은 300프레임이 넘고
    ///    잎 쪽 200프레임이 전부 SwiftUI · AttributeGraph 라, 그 화면을 그리던 앱 코드는
    ///    잘려 나간 뿌리 쪽에만 있다. 허브에서는 범인이 늘 시스템 프레임이 되어 원인을 알 수 없었다
    ///    (StampCamera 1.0.5 · HigGym 1.0.7 멈춤).
    ///
    /// 그래서 앱 프레임 몫(상한의 1/3까지)을 먼저 떼어 두고, 남은 자리를 잎부터 채운다.
    /// 번호는 원래 번호 그대로 두고, 건너뛴 자리마다 몇 프레임을 뺐는지 한 줄을 남긴다.
    static func fit(_ frames: [String], budget: Int, keep: (String) -> Bool) -> [String] {
        func line(_ index: Int) -> String { String(format: "%2d ", index) + frames[index] }
        let lengths = frames.indices.map { line($0).count + 1 }
        let noteLength = 30   // "... 123프레임 생략" 한 줄의 넉넉한 몫

        var chosen = Set<Int>()
        var used = 0
        if lengths.reduce(0, +) > budget {
            for index in frames.indices where keep(frames[index]) {
                let cost = lengths[index] + noteLength
                guard used + cost <= budget / 3 else { break }
                chosen.insert(index)
                used += cost
            }
        }
        for index in frames.indices where !chosen.contains(index) {
            guard used + lengths[index] <= budget else { break }
            chosen.insert(index)
            used += lengths[index]
        }

        var lines: [String] = []
        var next = 0
        for index in chosen.sorted() {
            if index > next { lines.append("... \(index - next)프레임 생략") }
            lines.append(line(index))
            next = index + 1
        }
        if next < frames.count { lines.append("... 뿌리 쪽 \(frames.count - next)프레임 생략") }
        return lines
    }

    /// `"SwiftUI +1042364"` → `"SwiftUI"`.
    static func binaryName(of frame: String) -> String {
        String(frame.prefix(while: { $0 != " " }))
    }

    /// 제대로 읽는 길. **잎부터** 담긴 프레임 목록과, 거기 나온 바이너리들의 UUID 를 준다.
    private static func framesByParsing(_ data: Data) -> (frames: [String], binaries: [(name: String, uuid: String)]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]],
              !stacks.isEmpty
        else { return ([], []) }

        // 죽은 스레드부터 본다. `threadAttributed` 가 그 표식이고, 아무 스레드에도
        // 표식이 없으면 첫 스레드를 쓴다(멈춤 진단이 대개 그렇다).
        let attributed = stacks.filter { ($0["threadAttributed"] as? Bool) == true }
        let chosen = attributed.isEmpty ? Array(stacks.prefix(1)) : attributed

        var frames: [String] = []
        var uuids: [String: String] = [:]
        for stack in chosen {
            for frame in (stack["callStackRootFrames"] as? [[String: Any]]) ?? [] {
                flatten(frame, into: &frames, uuids: &uuids)
            }
        }
        // MetricKit 트리는 **잎이 바깥**이고 `subFrames` 가 뿌리(dyld `start`) 쪽으로 들어간다.
        // 그래서 편 순서가 곧 잎에서 뿌리 순이다. 크래시 리포트를 읽는 사람은 언제나 0번부터 본다.
        //
        // ⚠️ 여기서 뒤집으면 안 된다. 5.0.6 ~ 5.1.6 은 "뿌리가 바깥"이라 믿고 뒤집어 보내서,
        //    모든 스택의 0번이 dyld, 1번이 앱의 `main` 이 됐다. 허브는 그 `main` 을 범인으로 잡아
        //    서로 다른 멈춤 160여 건을 한 이슈로 묶었다.
        //    (docs/postmortem/CRASH_STACK_UPSIDE_DOWN.md)
        // 순서를 내용으로 한 번 더 확인한다. 트리 모양이 iOS 판마다 달라도 0번은 잎이다.
        let ordered = leafFirst(frames)
        // 잎에 가까운 바이너리부터. 범례가 잘려도 내 코드 쪽이 남게 한다.
        var seen = Set<String>()
        var binaries: [(name: String, uuid: String)] = []
        for frame in ordered {
            let name = binaryName(of: frame)
            guard let uuid = uuids[name], seen.insert(name).inserted else { continue }
            binaries.append((name: name, uuid: uuid))
        }
        return (ordered, binaries)
    }

    /// 0번이 **잎**(죽은 자리)이 되게 세운다.
    ///
    /// 뿌리는 어느 스레드든 알아볼 수 있다. 메인 스레드는 dyld 의 `start`, 나머지는
    /// libsystem_pthread 의 `thread_start` · `start_wqthread` 다. 그 뿌리가 앞에 있고 뒤에는
    /// 없으면 거꾸로 온 것이니 뒤집는다. 어느 쪽도 아니면 받은 순서를 믿는다.
    public static func leafFirst(_ frames: [String]) -> [String] {
        func isRoot(_ frame: String) -> Bool {
            frame.hasPrefix("dyld ") || frame.hasPrefix("libsystem_pthread.dylib ")
        }
        guard let first = frames.first, let last = frames.last,
              isRoot(first), !isRoot(last) else { return frames }
        return frames.reversed()
    }

    /// `JSONSerialization` 이 못 읽을 만큼 깊은 스택을 위한 대비책.
    ///
    /// ⚠️ 이게 없으면 **스택 넘침 크래시를 통째로 놓친다.** 프레임 하나가 사전+배열
    ///    두 겹이라 250프레임 언저리에서 파서의 중첩 한도에 걸리는데, 무한 재귀로 죽은
    ///    스택이 정확히 그 모양으로 온다. 거기서 원문을 덤프하면 예전 버그로 되돌아간다.
    ///
    /// 중괄호만 세어 프레임 경계를 잡는다. 안쪽 프레임이 먼저 닫히고, MetricKit 트리는
    /// 안쪽이 뿌리라 **닫히는 순서가 곧 뿌리에서 잎 순서**다. 부르는 쪽이 뒤집는다.
    ///
    /// 필드가 나오는 **순서에 기대지 않는다**. 한 프레임 안에서 `binaryName` 이
    /// `subFrames` 앞에 오든 뒤에 오든 같은 결과가 나온다. (JSON 객체의 키 순서는
    /// 약속된 것이 아니고, 실제로 iOS 판마다 다르게 나온 적이 있다)
    ///
    /// 원문이 중간에 잘려 닫히지 못한 프레임도 버리지 않는다. 그쪽이 오히려
    /// 죽은 자리에 가깝다.
    private static func framesBySalvaging(_ raw: String) -> [String] {
        var open: [(name: String?, offset: String?)] = []
        var closed: [(name: String?, offset: String?)] = []

        var inString = false
        var escaped = false
        var token = ""
        var candidateKey: String?
        var pendingKey: String?
        var number = ""

        func closeNumber() {
            defer { number = ""; pendingKey = nil }
            guard !number.isEmpty, pendingKey == "offsetIntoBinaryTextSegment", !open.isEmpty else { return }
            open[open.count - 1].offset = number
        }

        for character in raw {
            if inString {
                if escaped {
                    token.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                    if pendingKey == nil {
                        // ':' 앞의 문자열은 키다. 그건 다음 글자에서 확정된다.
                        candidateKey = token
                    } else {
                        if pendingKey == "binaryName", !open.isEmpty {
                            open[open.count - 1].name = token
                        }
                        pendingKey = nil
                    }
                    token = ""
                } else {
                    token.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case ":":
                pendingKey = candidateKey
                candidateKey = nil
            case "{":
                closeNumber()
                open.append((nil, nil))
                candidateKey = nil
            case "}":
                closeNumber()
                if let frame = open.popLast() { closed.append(frame) }
                candidateKey = nil
            case ",", "]", "[":
                closeNumber()
            default:
                if character.isNumber, pendingKey != nil {
                    number.append(character)
                } else if !character.isWhitespace {
                    // true / false / null 같은 값은 쓸 일이 없다.
                    number = ""
                    if !character.isNumber { pendingKey = pendingKey == "binaryName" ? pendingKey : nil }
                }
            }
        }

        // 잘려서 닫히지 못한 프레임은 안쪽부터 이어 붙인다.
        closed += open.reversed()

        return closed
            .filter { $0.offset != nil }
            .map { "\($0.name ?? "?") +\($0.offset ?? "0")" }
    }

    /// 프레임 트리를 바깥에서 안쪽 순으로(= 잎에서 뿌리 순으로) 편다.
    ///
    /// 표본 스택은 갈라질 수 있어(`subFrames` 가 여럿) 재귀로 훑는다. 크래시 트리는
    /// 대개 일직선이라 실제로는 한 갈래다. 한도를 두는 건 갈라진 트리에서 줄 수가
    /// 터지는 걸 막기 위함이다.
    private static func flatten(_ frame: [String: Any],
                        into out: inout [String],
                                uuids: inout [String: String],
                                limit: Int = 400) {
        guard out.count < limit else { return }

        let name = (frame["binaryName"] as? String) ?? "?"
        let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue ?? 0
        out.append("\(name) +\(offset)")
        if name != "?", let uuid = frame["binaryUUID"] as? String { uuids[name] = uuid }

        for sub in (frame["subFrames"] as? [[String: Any]]) ?? [] {
            flatten(sub, into: &out, uuids: &uuids, limit: limit)
        }
    }
}
