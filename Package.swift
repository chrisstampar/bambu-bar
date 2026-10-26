// swift-tools-version: 6.0
import PackageDescription

// Focused license tests; the macOS app and widget are built with XcodeGen.
let package = Package(
    name: "BambuBarLicensing",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BambuBarUpdates", path: "Sources/BambuBar/Updates"),
        .testTarget(name: "UpdatesTests", dependencies: ["BambuBarUpdates"], path: "Tests/UpdatesTests"),
        .target(name: "BambuBarLicensing", path: "Sources/BambuBar/Licensing", exclude: ["LicenseView.swift"]),
        .testTarget(name: "LicensingTests", dependencies: ["BambuBarLicensing"], path: "Tests/LicensingTests"),
    ],
    swiftLanguageModes: [.v5]
)
