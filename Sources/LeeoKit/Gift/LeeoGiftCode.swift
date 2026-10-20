//
//  LeeoGiftCode.swift
//  LeeoKit
//
//  선물 코드: Crockford Base32 8자리(약 1조 가지), 보일 때는 `ABCD-EFGH`.
//  헷갈리는 글자(I · L · O · U)는 쓰지 않고, 사람이 잘못 쳐도 알아듣는다(O → 0, I · L → 1).
//

import Foundation

public enum LeeoGiftCode {
    /// I · L · O · U 가 없는 32글자.
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let length = 8

    /// 새 코드. 시스템 난수(암호학적으로 안전)를 쓴다.
    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] })
    }

    /// `ABCDEFGH` → `ABCD-EFGH`.
    public static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        let mid = code.index(code.startIndex, offsetBy: length / 2)
        return "\(code[..<mid])-\(code[mid...])"
    }

    /// 사람이 넣은 글에서 코드를 찾는다. 받은 메시지를 통째로 붙여넣어도 된다.
    ///
    /// - 글 전체가 코드 하나면(대시 · 공백 · 소문자 상관없이) 그것
    /// - 아니면 글 속의 `XXXX-XXXX` 꼴을 찾는다
    /// - 못 찾으면 nil
    public static func extract(from text: String) -> String? {
        if let whole = normalize(text) { return whole }
        let pattern = "[0-9A-Za-z]{4}-[0-9A-Za-z]{4}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            if let code = normalize(String(text[r])) { return code }
        }
        return nil
    }

    /// 치는 중인 글을 칸에 넣을 모양으로 다듬는다. 8칸 입력칸이 쓴다.
    ///
    /// - 받은 메시지를 통째로 붙여넣었으면 그 안의 코드
    /// - 아니면 대문자로 바꾸고, 헷갈리는 글자를 고치고(O → 0, I · L → 1), 코드에 없는 글자(대시 · 공백 포함)를 버리고 8자까지
    public static func typed(_ text: String) -> String {
        if let found = extract(from: text) { return found }
        let mapped = text.uppercased().compactMap { ch -> Character? in
            switch ch {
            case "O": return "0"
            case "I", "L": return "1"
            default: return alphabet.contains(ch) ? ch : nil
            }
        }
        return String(mapped.prefix(length))
    }

    /// 코드 하나만 담긴 글을 정규화한다. 코드가 아니면 nil.
    static func normalize(_ text: String) -> String? {
        let mapped = text.uppercased().compactMap { ch -> Character? in
            switch ch {
            case "-", " ", "\n", "\t": return nil
            case "O": return "0"
            case "I", "L": return "1"
            default: return ch
            }
        }
        guard mapped.count == length, mapped.allSatisfy(alphabet.contains) else { return nil }
        return String(mapped)
    }
}
