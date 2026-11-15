// swift-tools-version: 6.2
// WalletWeatherKit: everything in the iOS app with no screen — the API
// client, the models, and money and date formatting. System frameworks only
// (Foundation, CryptoKit). Tested with `swift test` on the Mac, no simulator.
import PackageDescription

let package = Package(
    name: "WalletWeatherKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WalletWeatherKit", targets: ["WalletWeatherKit"]),
    ],
    targets: [
        .target(name: "WalletWeatherKit"),
        .testTarget(
            name: "WalletWeatherKitTests",
            dependencies: ["WalletWeatherKit"],
            resources: [.copy("Samples")]
        ),
    ]
)
