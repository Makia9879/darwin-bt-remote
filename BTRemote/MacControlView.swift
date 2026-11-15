#if os(macOS)
    import BTHIDKit
    import SwiftUI

    /// trackpad-first surface for controlling another Mac
    struct MacControlView: View {
        let goToSetup: () -> Void

        @Environment(\.hid) private var hid
        @EnvironmentObject private var directInput: DirectInputController
        @AppStorage(HIDSettings.developerModeKey) private var developerMode = false

        var body: some View {
            if hid.isActive || developerMode {
                controls
            } else {
                NotConnectedView(icon: "rectangle.and.hand.point.up.left", goToSetup: goToSetup)
            }
        }

        private var controls: some View {
            VStack(spacing: 12) {
                directInputBar
                TrackpadPanel(hid: hid)
                shortcutRow
                Text(L10n.Mouse.hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }

        private var directInputBar: some View {
            HStack(spacing: 12) {
                Image(systemName: "hand.point.up.left")
                    .foregroundColor(directInput.isCapturing ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(directInput.isCapturing ? L10n.DirectInput.capturing : L10n.DirectInput.toggle)
                        .font(.body.weight(.medium))
                    Text(directInputHint)
                        .font(.caption)
                        .foregroundColor(directInput.lastError == nil ? .secondary : .red)
                }
                Spacer(minLength: 8)
                Toggle(isOn: captureBinding) {
                    Text(L10n.DirectInput.toggle)
                }
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(directInput.isCapturing ? Color.accentColor.opacity(0.16) : groupFill)
            )
        }

        private var directInputHint: LocalizedStringKey {
            if let _ = directInput.lastError {
                return L10n.DirectInput.captureFailed
            }
            return directInput.isCapturing ? L10n.DirectInput.releaseHint : L10n.DirectInput.toggleHint
        }

        private var captureBinding: Binding<Bool> {
            Binding(
                get: { directInput.isCapturing },
                set: { shouldCapture in
                    if shouldCapture {
                        directInput.start(hid)
                    } else {
                        directInput.stop()
                    }
                }
            )
        }

        private var shortcutRow: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Mouse.shortcuts)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: cellGap) {
                    shortcut("rectangle.3.group", L10n.Mouse.missionControl, .upArrow)
                    shortcut("rectangle.on.rectangle", L10n.Mouse.appWindows, .downArrow)
                    shortcut("chevron.left", L10n.Mouse.desktopLeft, .leftArrow)
                    shortcut("chevron.right", L10n.Mouse.desktopRight, .rightArrow)
                }
                .frame(height: 46)
            }
        }

        private func shortcut(_ icon: String, _ label: LocalizedStringKey, _ key: Keycode) -> some View {
            HoldButton(
                onPress: { hid.tap(key, modifiers: [.leftCtrl]) },
                onRelease: {},
                background: { RoundedRectangle(cornerRadius: 10).fill(groupFill) },
                label: {
                    VStack(spacing: 2) {
                        Image(systemName: icon).font(.caption)
                        Text(label).font(.caption2)
                    }
                }
            )
            .accessibilityLabel(label)
        }
    }

    #if DEBUG
        #Preview {
            MacControlView(goToSetup: {})
                .environmentObject(DirectInputController())
        }
    #endif
#endif
