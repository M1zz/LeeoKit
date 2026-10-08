#!/usr/bin/env python3
"""String Catalog 번역 검사 — 빠진 값 · ko 외 언어의 한글 · 포맷 지정자 불일치를 센다.

원문이 한국어 문장 키라서, 어느 언어든 값이 빠지면 그 언어 사용자에게 한국어 키가 그대로 보인다
(iOS 는 다른 언어로 대신 채우지 않는다). 새 문자열·새 언어를 넣은 뒤 돌린다. 문제가 있으면 1로 끝난다.
  python3 scripts/check-l10n.py
"""
import glob, json, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HANGUL = re.compile("[가-힣ㄱ-ㆎ]")
SPEC = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|@)")

def specs(s):
    found = [(int(m.group(1)) if m.group(1) else None, "d" if m.group(2) != "@" else "@") for m in SPEC.finditer(s)]
    if any(p for p, _ in found):
        return sorted(found)
    return [(i + 1, t) for i, (_, t) in enumerate(found)]

def values(loc):
    if "stringUnit" in loc:
        yield loc["stringUnit"].get("value", "")
    for kind in loc.get("variations", {}).values():
        for form in kind.values():
            yield from values(form)

bad = 0
for path in sorted(glob.glob(os.path.join(root, "Sources", "**", "*.xcstrings"), recursive=True)):
    data = json.load(open(path, encoding="utf-8"))
    strings = data["strings"]
    langs = sorted({l for e in strings.values() for l in e.get("localizations", {})})
    missing = {l: [] for l in langs}
    hangul = {l: [] for l in langs}
    spec = {l: [] for l in langs}
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.get("localizations", {})
        want = specs(key)
        for l in langs:
            if l not in locs or not any(v.strip() for v in values(locs[l])):
                missing[l].append(key); continue
            for v in values(locs[l]):
                if l != "ko" and HANGUL.search(v):
                    hangul[l].append(key)
                if specs(v) != want:
                    spec[l].append(key)
    print(f"{os.path.relpath(path, root)} — 키 {len(strings)}개, 언어 {len(langs)}개")
    print(f"  {'언어':<8}{'빈칸':>5}{'한글':>5}{'지정자':>6}")
    for l in langs:
        m, h, s = len(missing[l]), len(set(hangul[l])), len(set(spec[l]))
        bad += m + h + s
        print(f"  {l:<8}{m:>5}{h:>5}{s:>6}")
        for k in missing[l][:5]: print(f"      빈칸: {k}")
        for k in sorted(set(hangul[l]))[:5]: print(f"      한글: {k}")
        for k in sorted(set(spec[l]))[:5]: print(f"      지정자: {k}")
print("문제 합계:", bad)
sys.exit(1 if bad else 0)
