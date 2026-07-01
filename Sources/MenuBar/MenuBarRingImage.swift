import AppKit

enum MenuBarRingImage {
    static func make(percent: Double?, status: QuotaSnapshot.Status) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let lineWidth: CGFloat = 2.15
        let radius = min(size.width, size.height) / 2 - lineWidth

        drawArc(center: center,
                radius: radius,
                progress: 1,
                lineWidth: lineWidth,
                alpha: 0.26,
                lineCap: .butt)

        switch status {
        case .invalid, .error:
            drawWarningMark(in: NSRect(x: 4, y: 4, width: 10, height: 10))
        default:
            let progress = percent.map { min(max($0, 0), 1) } ?? fallbackProgress(for: status)
            drawArc(center: center,
                    radius: radius,
                    progress: progress,
                    lineWidth: lineWidth,
                    alpha: 0.95,
                    lineCap: .round)
        }

        return image
    }

    private static func fallbackProgress(for status: QuotaSnapshot.Status) -> Double {
        switch status {
        case .loading:
            return 0.72
        case .unsupported:
            return 0.5
        default:
            return 0.86
        }
    }

    private static func drawArc(center: NSPoint,
                                radius: CGFloat,
                                progress: Double,
                                lineWidth: CGFloat,
                                alpha: CGFloat,
                                lineCap: NSBezierPath.LineCapStyle) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = lineCap
        path.appendArc(withCenter: center,
                       radius: radius,
                       startAngle: 90,
                       endAngle: 90 - CGFloat(360 * progress),
                       clockwise: true)

        NSColor.labelColor.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private static func drawWarningMark(in rect: NSRect) {
        let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                             accessibilityDescription: "Quota warning")
        symbol?.isTemplate = true
        symbol?.draw(in: rect,
                     from: .zero,
                     operation: .sourceOver,
                     fraction: 0.95,
                     respectFlipped: true,
                     hints: nil)
    }
}
