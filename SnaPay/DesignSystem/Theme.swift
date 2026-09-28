import SwiftUI
import UIKit

/// Color tokens from the Claude Design handoff (docs/design/claude-design/design-tokens).
/// Each one is a color set in Assets.xcassets with light and dark values; every color in the
/// app comes from here.
enum Theme {
    // Text
    static let textPrimary = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let textTertiary = Color("textTertiary")

    // Surfaces
    static let glass = Color("glass")
    static let glassStrong = Color("glassStrong")
    static let glassHighlight = Color("glassHighlight")
    static let stroke = Color("stroke")
    static let fill = Color("fill")
    static let fillStrong = Color("fillStrong")
    static let separator = Color("separator")
    static let sheet = Color("sheet")
    static let field = Color("field")
    static let track = Color("track")
    static let scrim = Color("scrim")

    // Brand and meaning
    /// Brand green for fills, rings, icons and the "+" button.
    static let brand = Color("brand")
    /// Brand green dark enough for text and small icons on glass.
    static let brandInk = Color("brandInk")
    static let brandTint = Color("brandTint")
    static let buttonPrimary = Color("buttonPrimary")
    static let onButtonPrimary = Color("onButtonPrimary")
    static let income = brandInk
    static let expense = Color("expense")
    static let expenseTint = Color("expenseTint")
    static let destructive = Color("destructive")
    static let savings = Color("savings")
    static let savingsInk = Color("savingsInk")
    static let warning = Color("warning")
    static let warningTint = Color("warningTint")

    /// Category tiles: the category color at 16% (light) / 22% (dark).
    static func categoryTint(_ color: Color, scheme: ColorScheme) -> Color {
        color.opacity(scheme == .dark ? 0.22 : 0.16)
    }
}

/// Corner radii. Controls are rounded rectangles, never capsules (design rule); full circles
/// only for avatars and the "+" button.
enum Radius {
    static let key: CGFloat = 10
    static let chip: CGFloat = 12
    static let field: CGFloat = 14
    static let tile: CGFloat = 14
    static let control: CGFloat = 16
    static let tabBar: CGFloat = 22
    static let card: CGFloat = 24
    static let sheet: CGFloat = 32
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let sm: CGFloat = 12
    static let m: CGFloat = 16
    static let gutter: CGFloat = 20
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 40
    static let cardGap: CGFloat = 12
    static let sectionGap: CGFloat = 22
}

/// Component sizes from the design tokens.
enum Metrics {
    static let buttonHeight: CGFloat = 54
    static let fieldHeight: CGFloat = 52
    static let chipHeight: CGFloat = 36
    static let tabBarHeight: CGFloat = 68
    static let plusButton: CGFloat = 62
    static let plusRaise: CGFloat = 30
}

/// Type scale (SF Pro / SF Hebrew). Built on system text styles so Dynamic Type still works;
/// the design's sizes are those styles at the default size.
enum Typography {
    static let heroAmount = Font.system(size: 50, weight: .semibold)
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title1 = Font.title.weight(.bold)
    static let title2 = Font.title2.weight(.bold)
    static let title3 = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let tab = Font.system(size: 11, weight: .medium)
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

extension Color {
    /// A color that adapts to light and dark mode, from 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
