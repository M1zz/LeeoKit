#!/usr/bin/env python3
"""String Catalog 에 원문(ko) 값을 명시적으로 채운다.

왜 필요한가:
  패키지의 defaultLocalization 은 en 이다 — 기기 언어가 이 패키지에 없는 언어일 때(독일어 등)
  영어로 떨어지게 하려고. 그런데 원문이 ko 인 카탈로그는 ko 값을 따로 적지 않으면
  ko.lproj 를 만들지 않고, 그러면 한국어 사용자까지 영어를 보게 된다.
  그래서 ko 값이 빠진 키마다 키 그대로를 ko 값으로 적어 둔다.

새 문자열을 넣은 뒤 한 번 돌리면 된다. 여러 번 돌려도 같은 결과다.
  python3 scripts/fill-source-ko.py
"""
import glob
import json
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
changed_total = 0
for path in sorted(glob.glob(os.path.join(root, "Sources", "**", "*.xcstrings"), recursive=True)):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    data = json.loads(raw)
    if data.get("sourceLanguage") != "ko":
        continue
    changed = 0
    for key, entry in data["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.setdefault("localizations", {})
        if "ko" in locs:
            continue
        locs["ko"] = {"stringUnit": {"state": "translated", "value": key}}
        changed += 1
    if changed:
        # 모양은 원래 것을 지킨다. 모양이 바뀌면 diff가 파일 전체가 된다.
        if '" : ' in raw:
            out = json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : "))
        else:
            out = json.dumps(data, indent=2, ensure_ascii=False)
        if raw.endswith("\n"):
            out += "\n"
        with open(path, "w", encoding="utf-8") as f:
            f.write(out)
    changed_total += changed
    print(f"{os.path.relpath(path, root)}: ko {changed}개 채움")
print(f"합계 {changed_total}개")
