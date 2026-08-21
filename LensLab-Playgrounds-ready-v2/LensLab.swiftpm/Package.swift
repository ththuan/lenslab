// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "LensLab",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "LensLab",
            targets: ["AppModule"],
            bundleIdentifier: "com.lenslab.studio",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "2",
            appIcon: .placeholder,
            accentColor: .presetColor(.teal),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .camera(purposeString: "LensLab cần dùng camera iPad hoặc capture card để chụp ảnh."),
                .photoLibrary(purposeString: "LensLab cần lưu ảnh đã chỉnh sửa vào thư viện ảnh của bạn.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: ["Package.swift"],
            sources: ["LensLab.swift"]
        )
    ]
)
