import Testing
@testable import WalletWeatherKit

/// The model name a new token is given (#155).
struct DeviceModelTests {
    @Test func knownModels() {
        #expect(DeviceModel.name(for: "iPhone17,2") == "iPhone 16 Pro Max")
        #expect(DeviceModel.name(for: "iPhone18,4") == "iPhone Air")
        #expect(DeviceModel.name(for: "iPhone19,4") == "iPhone Duo")
        #expect(DeviceModel.name(for: "iPhone12,1") == "iPhone 11")
    }

    @Test func unknownFallsBackToIPhone() {
        #expect(DeviceModel.name(for: "iPhone99,9") == "iPhone")
        #expect(DeviceModel.name(for: "arm64") == "iPhone")
        #expect(DeviceModel.name(for: "") == "iPhone")
    }

    @Test func everyNameIsAnIPhone() {
        #expect(DeviceModel.names.values.allSatisfy { $0.hasPrefix("iPhone") })
        #expect(DeviceModel.names.count == 34)
    }
}
