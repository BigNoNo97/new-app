import SwiftUI
import UIKit

/// Color tokens. Placeholder values until the Claude Design output is in; keep every
/// color in the app coming from here so the swap is one file.
enum Theme {
    static let brand = Color("AccentColor")
    static let expense = Color(light: 0xE5625A, dark: 0xFF7A70)
    static let income = brand
    static let savings = Color(light: 0xB7C92E, dark: 0xD4E157)

    static let backgroundTop = Color(light: 0xF1F7F9, dark: 0x081220)
    static let backgroundBottom = Color(light: 0xE4F1EE, dark: 0x0A2E31)
    static let glow1 = Color(light: 0xBFE8D3, dark: 0x1F7A4F)
    static let glow2 = Color(light: 0xC9DDF2, dark: 0x145A6E)
}

/// Corner radii. Controls are rounded rectangles, never capsules (design rule).
enum Radius {
    static let control: CGFloat = 14
    static let card: CGFloat = 24
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

extension Color {
    /// A color that adapts to light and dark mode, from 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
