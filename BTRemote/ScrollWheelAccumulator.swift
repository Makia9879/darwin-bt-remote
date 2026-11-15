import Foundation

/// turns sub-notch pointer deltas into whole HID wheel steps
struct ScrollWheelAccumulator {
    /// pixels that make up one wheel step
    var pixelsPerStep: CGFloat = 12

    private var x: CGFloat = 0
    private var y: CGFloat = 0

    mutating func reset() {
        x = 0
        y = 0
    }

    /// `isPixel` deltas come from continuous devices (trackpad, magic mouse), otherwise deltas are already in lines
    mutating func steps(dx: CGFloat, dy: CGFloat, isPixel: Bool) -> (pan: Int8, wheel: Int8) {
        let scale = isPixel ? 1 / max(pixelsPerStep, 1) : 1
        x += dx * scale
        y += dy * scale

        let pan = x.rounded(.towardZero)
        let wheel = y.rounded(.towardZero)
        x -= pan
        y -= wheel

        return (Int8(max(-127, min(127, pan))), Int8(max(-127, min(127, wheel))))
    }
}
