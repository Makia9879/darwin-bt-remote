import Foundation

public enum HIDSettings {
    public static let developerModeKey = "developerMode"
    public static let forceServiceChangedKey = "forceServiceChanged"
    public static let advertisedNameKey = "advertisedName"
    public static let advertisingDurationKey = "advertisingDurationSeconds"
    public static let defaultAdvertisingDuration = 120
    public static let advertisingDurationRange = 1 ... 3600

    static let classicDevicesKey = "classicDevices"
}
