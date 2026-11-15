import SwiftUI

struct TrackpadPanel: View {
    let hid: HIDInput

    @AppStorage(AppSettings.touchpadSensitivityKey) private var touchpadSensitivity = AppSettings.defaultPointerSensitivity
    @AppStorage(AppSettings.scrollSensitivityKey) private var scrollSensitivity = AppSettings.defaultScrollSensitivity

    var body: some View {
        VStack(spacing: cellGap) {
            surface
            mouseButtonsRow.frame(height: 52)
        }
    }

    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(groupFill)
            #if os(iOS)
                TouchpadView(
                    moveSensitivity: touchpadSensitivity,
                    scrollSensitivity: scrollSensitivity,
                    onMove: { hid.move(dx: $0, dy: $1) },
                    onScroll: { hid.scroll($0) },
                    onLeftClick: { Haptics.tap(); hid.click(.left) },
                    onRightClick: { Haptics.tap(); hid.click(.right) }
                )
            #elseif os(macOS)
                TrackpadSurface(
                    pointerGain: touchpadSensitivity / AppSettings.macPointerNeutral,
                    scrollGain: scrollSensitivity,
                    onPointer: { hid.move(dx: $0, dy: $1) },
                    onScroll: { hid.scroll(dx: $0, dy: $1) },
                    onLeftDown: { hid.drag(.left) },
                    onLeftUp: { hid.releaseMouse() },
                    onRightClick: { hid.click(.right) },
                    onMiddleClick: { hid.click(.middle) }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mouseButtonsRow: some View {
        HStack(spacing: cellGap) {
            mouseButton(.left, L10n.Mouse.leftButton)
            mouseButton(.middle, L10n.Mouse.middleButton)
            mouseButton(.right, L10n.Mouse.rightButton)
        }
    }

    private func mouseButton(_ button: MouseButtons, _ label: LocalizedStringKey) -> some View {
        HoldButton(
            onPress: { hid.sendMouse(MouseReport(buttons: button)) },
            onRelease: { hid.sendMouse(.zero) },
            background: { RoundedRectangle(cornerRadius: 12).fill(groupFill) },
            label: { Text(label).font(.caption) }
        )
        .accessibilityLabel(label)
    }
}
