import BTHIDKit
import SwiftUI

enum Transport: String {
    case lowEnergy, classic
}

@main
struct BTRemoteApp: App {
    @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = false
    @State private var didLaunch = false
    @StateObject private var lowEnergy = HIDPeripheral(profile: Combo())
    @StateObject private var central = HIDCentral()
    #if os(macOS)
        @StateObject private var directInput = DirectInputController()
        @StateObject private var classic = HIDClassicDevice(profile: Combo())
        @AppStorage(AppSettings.transportKey) private var transport = Transport.lowEnergy
    #endif

    @StateObject private var deviceNames = DeviceNameStore()

    init() {
        UserDefaults.standard.register(defaults: [HIDSettings.forceServiceChangedKey: true])
    }

    private var hid: HIDInput {
        #if os(macOS)
            return HIDInput.make(lowEnergy: lowEnergy, central: central, classic: classic, transport: transport)
        #else
            return HIDInput.make(lowEnergy: lowEnergy, central: central)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
                ContentView()
                    .environmentObject(lowEnergy)
                    .environmentObject(central)
                    .environmentObject(deviceNames)
                    .environment(\.hid, hid)
                    .onAppear {
                        guard !didLaunch else { return }
                        didLaunch = true
                        central.start()
                        if autoAdvertise { lowEnergy.start() }
                    }
            #else
                ContentView()
                    .environmentObject(lowEnergy)
                    .environmentObject(central)
                    .environmentObject(classic)
                    .environmentObject(directInput)
                    .environmentObject(deviceNames)
                    .environment(\.hid, hid)
                    .onAppear {
                        guard !didLaunch else { return }
                        didLaunch = true
                        CaptureHotKey.shared.beginCapture = {
                            guard !directInput.isCapturing else { return }
                            if hid.isConnected { directInput.start(hid) }
                            else { directInput.showNoConnection() }
                        }
                        _start(advertise: autoAdvertise)
                    }
                    .onChange(of: transport) { _ in _switch() }
            #endif
        }
    }

    #if os(macOS)
        private func _start(advertise: Bool) {
            switch transport {
            case .classic:
                classic.start()
            case .lowEnergy:
                if advertise { lowEnergy.start() }
                central.start()
            }
        }

        private func _switch() {
            lowEnergy.stop()
            classic.stop()
            _start(advertise: false)
        }
    #endif
}
