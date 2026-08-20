// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "LensLab",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "LensLab",
            targets: ["AppModule"],
            bundleIdentifier: "com.lenslab.studio",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
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
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
