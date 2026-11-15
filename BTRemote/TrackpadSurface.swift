#if os(macOS)
    import AppKit
    import SwiftUI

    /// window-local trackpad: drag moves the remote pointer, two-finger scroll scrolls,
    /// click and right click send the matching buttons
    struct TrackpadSurface: NSViewRepresentable {
        var pointerGain: CGFloat
        var scrollGain: CGFloat
        var onPointer: (Int8, Int8) -> Void
        var onScroll: (Int8, Int8) -> Void
        var onLeftDown: () -> Void
        var onLeftUp: () -> Void
        var onRightClick: () -> Void
        var onMiddleClick: () -> Void

        func makeNSView(context: Context) -> SurfaceView {
            let view = SurfaceView()
            update(view)
            return view
        }

        func updateNSView(_ view: SurfaceView, context: Context) {
            update(view)
        }

        private func update(_ view: SurfaceView) {
            view.pointerGain = pointerGain
            view.scrollGain = scrollGain
            view.onPointer = onPointer
            view.onScroll = onScroll
            view.onLeftDown = onLeftDown
            view.onLeftUp = onLeftUp
            view.onRightClick = onRightClick
            view.onMiddleClick = onMiddleClick
        }

        final class SurfaceView: NSView {
            var pointerGain: CGFloat = 1
            var scrollGain: CGFloat = 1
            var onPointer: (Int8, Int8) -> Void = { _, _ in }
            var onScroll: (Int8, Int8) -> Void = { _, _ in }
            var onLeftDown: () -> Void = {}
            var onLeftUp: () -> Void = {}
            var onRightClick: () -> Void = {}
            var onMiddleClick: () -> Void = {}

            private var scrollWheel = ScrollWheelAccumulator()

            override var acceptsFirstResponder: Bool {
                true
            }

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
                true
            }

            override func mouseDown(with event: NSEvent) {
                onLeftDown()
            }

            override func mouseDragged(with event: NSEvent) {
                move(dx: event.deltaX, dy: event.deltaY)
            }

            override func mouseUp(with event: NSEvent) {
                onLeftUp()
            }

            override func rightMouseDown(with event: NSEvent) {
                onRightClick()
            }

            override func otherMouseDown(with event: NSEvent) {
                onMiddleClick()
            }

            override func scrollWheel(with event: NSEvent) {
                let isPixel = event.hasPreciseScrollingDeltas
                let steps = scrollWheel.steps(
                    dx: event.scrollingDeltaX * scrollGain,
                    dy: event.scrollingDeltaY * scrollGain,
                    isPixel: isPixel
                )
                guard steps.pan != 0 || steps.wheel != 0 else { return }
                onScroll(steps.pan, steps.wheel)
            }

            private func move(dx: CGFloat, dy: CGFloat) {
                let gain = max(pointerGain, 0.1)
                let mx = Int8(max(-127, min(127, (dx * gain).rounded())))
                let my = Int8(max(-127, min(127, (dy * gain).rounded())))
                guard mx != 0 || my != 0 else { return }
                onPointer(mx, my)
            }
        }
    }
#endif
