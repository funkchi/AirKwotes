import SwiftUI

struct RingShape: Shape {
    var progress: Double
    var startAngle: Angle = .degrees(-90)
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        p.addArc(center: center,
                 radius: radius,
                 startAngle: startAngle,
                 endAngle: startAngle + .degrees(360 * min(max(progress, 0), 1)),
                 clockwise: false)
        return p
    }
}
