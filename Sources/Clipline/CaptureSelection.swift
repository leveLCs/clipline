import AppKit

enum CaptureMode {
    case vision, ddddocr, hang

    init(modifiers: NSEvent.ModifierFlags) {
        self = modifiers.contains(.control) ? .hang : modifiers.contains(.option) ? .ddddocr : .vision
    }
}

struct CaptureSelection {
    let rect: CGRect
    let pixelRect: CGRect
    let mode: CaptureMode

    init?(start: CGPoint, end: CGPoint, screenFrame: CGRect, pixelSize: CGSize,
          modifiers: NSEvent.ModifierFlags) {
        guard [start.x, start.y, end.x, end.y, screenFrame.minX, screenFrame.minY,
               screenFrame.width, screenFrame.height, pixelSize.width, pixelSize.height].allSatisfy({ $0.isFinite }),
              screenFrame.width > 0, screenFrame.height > 0, pixelSize.width > 0, pixelSize.height > 0,
              screenFrame.contains(start) else { return nil }
        let area = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(screenFrame)
        guard !area.isNull, area.width >= 3, area.height >= 3 else { return nil }
        rect = area
        let sx = pixelSize.width / screenFrame.width, sy = pixelSize.height / screenFrame.height
        // AppKit is bottom-up; image pixels are top-down. Use the actual capture's scale.
        pixelRect = CGRect(x: (area.minX - screenFrame.minX) * sx,
                           y: (screenFrame.maxY - area.maxY) * sy,
                           width: area.width * sx, height: area.height * sy)
            .integral.intersection(CGRect(origin: .zero, size: pixelSize))
        mode = CaptureMode(modifiers: modifiers)
    }
}
