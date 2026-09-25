// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LeeoKit",
    // 기기 언어가 이 패키지가 가진 어느 언어도 아닐 때(독일어 등) 떨어지는 언어.
    // 원문은 한국어(카탈로그 sourceLanguage = ko)지만 여기는 en 이어야 한다 — ko로 두면
    // 외국 사용자에게 한국어가 뜬다. 대신 카탈로그에 ko 값을 명시해 둬야 ko.lproj가
    // 만들어진다 (→ scripts/fill-source-ko.py). 안 그러면 한국어 사용자가 영어를 본다.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17)
    ],
    products: [
        .library(name: "LeeoKit", targets: ["LeeoKit"])
    ],
    targets: [
        .target(
            name: "LeeoKit",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "LeeoKitTests", dependencies: ["LeeoKit"])
    ]
)
