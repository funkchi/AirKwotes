import SwiftUI

struct Ring: View {
    let remaining: Double?
    let status: QuotaSnapshot.Status
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3
    var label: String? = nil

    var body: some View {
        ZStack {
            RingShape(progress: 1)
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
            if let pct = remaining {
                RingShape(progress: pct)
                    .stroke(Theme.ringColor(forPercent: pct),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else {
                nonPercentArc
            }
            center
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var nonPercentArc: some View {
        switch status {
        case .loading:
            RingShape(progress: 0.75)
                .stroke(Color.secondary.opacity(0.4), lineWidth: lineWidth)
                .rotationEffect(.degrees(0))
        case .invalid, .error:
            RingShape(progress: 1)
                .stroke(Color.red.opacity(0.7), lineWidth: lineWidth)
        case .ok:
            RingShape(progress: 1)
                .stroke(Color.green.opacity(0.6), lineWidth: lineWidth)
        default:
            RingShape(progress: 0.85)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: lineWidth)
        }
    }

    @ViewBuilder private var center: some View {
        if let label {
            Text(label).font(.system(size: size * 0.28, weight: .semibold))
        } else if let pct = remaining {
            Text("\(Int(min(max(pct,0),1)*100))")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}
