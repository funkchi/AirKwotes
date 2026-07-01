import SwiftUI

enum Theme {
    static let sidebar = Color(red: 0.906, green: 0.894, blue: 0.894)
    static let panelBG = Color.white
    static let cardBG = Color.white
    static let fieldBG = Color(red: 0.945, green: 0.945, blue: 0.953)
    static let hairline = Color(red: 0.90, green: 0.90, blue: 0.92)
    static let accent = Color(red: 0.20, green: 0.48, blue: 0.97)
    static let primary = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let secondary = Color(red: 0.50, green: 0.51, blue: 0.55)
    static let tertiary = Color(red: 0.66, green: 0.67, blue: 0.71)
    static let warning = Color(red: 0.93, green: 0.62, blue: 0.21)

    static func ringColor(forPercent remaining: Double) -> Color {
        switch remaining {
        case ..<0.15: return Color(red: 0.92, green: 0.31, blue: 0.27)
        case ..<0.40: return Color(red: 0.93, green: 0.62, blue: 0.21)
        default:      return Color(red: 0.26, green: 0.74, blue: 0.45)
        }
    }
}
