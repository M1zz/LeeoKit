#!/usr/bin/env python3
"""함께 쓰는 앱 카드의 **실제 앱 아이콘**을 LeeoKit 소스에 박아 넣는다.

각 앱 레포의 AppIcon 원본(1024px)을 192px PNG 로 줄여 base64 로
Sources/LeeoKit/Family/LeeoFamilyIconData.swift 에 쓴다. 리소스 번들을 거치지 않으므로
어느 앱에서 LeeoKit 을 끌어와도, 어떤 빌드 환경에서도 그대로 읽힌다.

쓰는 법 (앱 레포들이 ~/Documents/workspace/Auto 아래에 나란히 있을 때):

    python3 scripts/embed_family_icons.py

다른 곳에 있으면 LEEO_APPS_ROOT 로 알려 준다. 줄이는 일은 macOS 의 sips 가 한다(설치할 것 없음).

앱을 카탈로그(LeeoFamilyCatalog)에 더하면 아래 SOURCES 에도 한 줄 더한다.
빠지면 LeeoFamilyTests 가 알려 준다. 앱 아이콘을 바꿨으면 다시 돌린다.
"""
import base64
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS = os.environ.get("LEEO_APPS_ROOT", os.path.expanduser("~/Documents/workspace/Auto"))
OUT = os.path.join(ROOT, "Sources", "LeeoKit", "Family", "LeeoFamilyIconData.swift")

# 카드에서 가장 크게 그리는 것이 64pt(상세 머리). 3배 화면에서 192px 이면 흐려지지 않는다.
SIZE = 192

# 카탈로그 id → 그 앱 레포 안의 AppIcon 원본(라이트 모양).
SOURCES = {
    "clipkeyboard": "클립키보드/ClipKeyboard/Assets.xcassets/AppIcon.appiconset/1024.png",
    "clipkeyboard-mac": "탭클립키보드/ClipKeyboard.tap/Assets.xcassets/AppIcon.appiconset/1024.png",
    "rainbow-ios": "욕망의 무지개/ScheduleDensityApp/Assets.xcassets/AppIcon.appiconset/image1414.png",
    "rainbow-mac": "무지개 공방/WeekBlocks/Assets.xcassets/AppIcon.appiconset/1024.png",
    "rereminder": "두번알림/Rereminder/Assets.xcassets/AppIcon.appiconset/logo.png",
}

HEADER = '''//
//  LeeoFamilyIconData.swift
//  LeeoKit
//
//  같은 사람이 만든 앱들의 **실제 앱 아이콘**(PNG, base64).
//  각 앱 레포의 AppIcon 원본을 {size}px 로 줄여 상수로 박아 둔 것이다.
//
//  ⚠️ 손으로 고치지 않는다. `python3 scripts/embed_family_icons.py` 가 만든다.
//     앱을 카탈로그에 더했거나 아이콘을 바꿨으면 그 스크립트를 다시 돌린다.
//
//  리소스 번들(Bundle.module)에 PNG 로 두지 않는 이유: 상수는 컴파일된 코드 안에 들어가
//  어느 앱이 어떤 방식으로 LeeoKit 을 끌어와도 "파일을 못 찾는" 경우가 생기지 않는다.
//

import Foundation

enum LeeoFamilyIconData {{
    /// 카탈로그 id → {size}px PNG 의 base64.
    static let pngBase64: [String: String] = [
'''

FOOTER = '''    ]
}
'''


def shrink(path):
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "icon.png")
        subprocess.run(["sips", "-s", "format", "png", "-z", str(SIZE), str(SIZE), path, "--out", out],
                       check=True, stdout=subprocess.DEVNULL)
        with open(out, "rb") as f:
            return f.read()


def main():
    rows = []
    for app_id, rel in SOURCES.items():
        path = os.path.join(APPS, rel)
        if not os.path.exists(path):
            sys.exit(f"❌ {app_id}: 원본이 없다 ({path})")
        data = shrink(path)
        rows.append(f'        "{app_id}": "{base64.b64encode(data).decode()}",')
        print(f"✅ {app_id}: {len(data):,} bytes  ← {rel}")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(HEADER.format(size=SIZE) + "\n".join(rows) + "\n" + FOOTER)
    print(f"📝 {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
