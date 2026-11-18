import BTHIDKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lowEnergy: HIDPeripheral
    @EnvironmentObject private var names: DeviceNameStore
    @Environment(\.hid) private var hid
    @State private var showReset = false
    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity
    @AppStorage(HIDSettings.developerModeKey) private var developerMode = false
    @AppStorage(HIDSettings.forceServiceChangedKey) private var forceServiceChanged = true
    @AppStorage(AppSettings.hasSeenWelcomeKey) private var hasSeenWelcome = false
    @AppStorage(AppSettings.autoAdvertiseKey) private var autoAdvertise = false

    var body: some View {
        #if os(macOS)
            NavigationStack {
                form
                    .formStyle(.grouped)
                    .navigationTitle(L10n.Tab.settings)
            }
        #else
            NavigationView {
                form.navigationTitle(L10n.Tab.settings)
            }
            .navigationViewStyle(.stack)
        #endif
    }

    private var form: some View {
        Form {
            Section(header: Text(L10n.Settings.trackpad)) {
                #if os(macOS)
                    // trackpad deltas already carry the system acceleration, so one step is neutral here
                    sensitivityRow(
                        L10n.Settings.trackingSpeed,
                        value: gainBinding($touchpadSensitivity, divisor: AppSettings.macPointerNeutral),
                        range: 0.1 ... 2.0
                    )
                #else
                    sensitivityRow(L10n.Settings.trackingSpeed, value: $touchpadSensitivity, range: AppSettings.pointerSensitivityRange)
                #endif
                sensitivityRow(L10n.Settings.scrollSpeed, value: $scrollSensitivity, range: AppSettings.scrollSensitivityRange)
            }
            Section(header: Text(L10n.Settings.connection), footer: Text(L10n.Settings.autoAdvertiseHint)) {
                Toggle(L10n.Settings.autoAdvertise, isOn: $autoAdvertise)
                AdvertisingDurationRow()
            }
            #if os(macOS)
                Section { CaptureShortcutRow() } header: { Text(L10n.DirectInput.section) }
            #endif
            Section(footer: Text(L10n.Settings.forceServiceChangedHint)) {
                Toggle(L10n.Settings.forceServiceChanged, isOn: $forceServiceChanged)
                    .onChange(of: forceServiceChanged) { if $0 { lowEnergy.scheduleServiceChanged() } }
            }
            Section(header: Text(L10n.Settings.advanced)) {
                Toggle(L10n.Settings.developerMode, isOn: $developerMode)
                Link(destination: AppSettings.repoURL) {
                    Label(L10n.Settings.sourceCode, systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            if developerMode, hid.isActive { batterySection }
            resetSection
        }
        .confirmationDialog(L10n.Settings.resetConfirm, isPresented: $showReset, titleVisibility: .visible) {
            Button(L10n.Settings.reset, role: .destructive) { _resetAll() }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) { showReset = true } label: {
                Label(L10n.Settings.reset, systemImage: "trash")
            }
        }
    }

    private func _resetAll() {
        names.clear()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        #if os(macOS)
            CaptureHotKey.shared.reset()
        #endif
        hasSeenWelcome = false
    }

    private var batterySection: some View {
        Section(header: Text(L10n.Section.battery)) {
            Slider(
                value: Binding(
                    get: { Double(hid.batteryLevel) },
                    set: { hid.updateBattery(UInt8($0)) }
                ),
                in: 0 ... 100,
                step: 1
            )
            HStack {
                Text(L10n.Battery.level)
                Spacer()
                Text(Double(hid.batteryLevel) / 100, format: .percent.precision(.fractionLength(0)))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func gainBinding(_ source: Binding<Double>, divisor: Double) -> Binding<Double> {
        Binding(
            get: { source.wrappedValue / divisor },
            set: { source.wrappedValue = $0 * divisor }
        )
    }

    private func sensitivityRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .foregroundColor(.secondary)
                    + Text(verbatim: "×").foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: 0.1)
        }
    }
}

struct AdvertisingDurationRow: View {
    @AppStorage(HIDSettings.advertisingDurationKey) private var seconds = HIDSettings.defaultAdvertisingDuration

    @State private var draft = ""
    @FocusState private var editing: Bool

    private var validSeconds: Int? {
        guard let value = Int(draft), HIDSettings.advertisingDurationRange.contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Advertising duration")
                Spacer()
                TextField("Seconds", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .accessibilityLabel(Text("Advertising duration in seconds"))
                    .focused($editing)
                    .onSubmit { editing = false }
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("s").foregroundColor(.secondary)
            }
            if editing, validSeconds == nil, !draft.isEmpty {
                Text("Enter a whole number from 1 to 3600.").font(.caption).foregroundColor(.red)
            }
        }
        .onAppear { draft = String(seconds) }
        .onChange(of: draft) { _ in
            if editing, let validSeconds { seconds = validSeconds }
        }
        .onChange(of: seconds) { if !editing { draft = String($0) } }
        .onChange(of: editing) { if !$0 { draft = String(seconds) } }
    }
}

#if DEBUG
    #Preview {
        #if os(iOS)
            SettingsView()
                .environmentObject(HIDPeripheral(profile: Combo()))
                .environmentObject(HIDCentral())
                .environmentObject(DeviceNameStore())
        #else
            SettingsView()
                .environmentObject(HIDPeripheral(profile: Combo()))
                .environmentObject(HIDCentral())
                .environmentObject(DeviceNameStore())
                .environmentObject(HIDClassicDevice(profile: Combo()))
        #endif
    }
#endif
