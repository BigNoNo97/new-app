// SnaPay design system - generated from the SnaPay design canvas.
// Colors live in SnaPayColors.xcassets (Any / Dark appearances).
import SwiftUI

extension Color {
    static let textPrimary = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let textTertiary = Color("textTertiary")
    static let glass = Color("glass")
    static let glassStrong = Color("glassStrong")
    static let stroke = Color("stroke")
    static let glassHighlight = Color("glassHighlight")
    static let fill = Color("fill")
    static let fillStrong = Color("fillStrong")
    static let separator = Color("separator")
    static let brand = Color("brand")
    static let brandInk = Color("brandInk")
    static let buttonPrimary = Color("buttonPrimary")
    static let onButtonPrimary = Color("onButtonPrimary")
    static let brandTint = Color("brandTint")
    static let savings = Color("savings")
    static let savingsInk = Color("savingsInk")
    static let expense = Color("expense")
    static let destructive = Color("destructive")
    static let expenseTint = Color("expenseTint")
    static let warning = Color("warning")
    static let warningTint = Color("warningTint")
    static let scrim = Color("scrim")
    static let sheet = Color("sheet")
    static let field = Color("field")
    static let track = Color("track")
    static let catFood = Color("catFood")  // 🍔 אוכל ומסעדות
    static let catGrocery = Color("catGrocery")  // 🛒 סופר
    static let catShop = Color("catShop")  // 🛍️ קניות
    static let catCar = Color("catCar")  // 🚗 רכב ודלק
    static let catBus = Color("catBus")  // 🚌 תחבורה ציבורית
    static let catHome = Color("catHome")  // 🏠 דיור
    static let catBills = Color("catBills")  // 💡 חשבונות
    static let catPhone = Color("catPhone")  // 📱 תקשורת
    static let catHealth = Color("catHealth")  // 💊 בריאות
    static let catFun = Color("catFun")  // 🎬 בילויים
    static let catTravel = Color("catTravel")  // ✈️ טיולים
    static let catGift = Color("catGift")  // 🎁 מתנות
    static let catKids = Color("catKids")  // 👶 ילדים
    static let catPets = Color("catPets")  // 🐾 חיות מחמד
    static let catStudy = Color("catStudy")  // 📚 לימודים
    static let catCoffee = Color("catCoffee")  // ☕ קפה
}

enum SNFont {
    static let heroAmount = Font.system(size: 50, weight: .semibold)  // line height 56
    static let largeTitle = Font.system(size: 34, weight: .bold)  // line height 41
    static let title1 = Font.system(size: 28, weight: .bold)  // line height 34
    static let title2 = Font.system(size: 22, weight: .bold)  // line height 28
    static let title3 = Font.system(size: 20, weight: .semibold)  // line height 25
    static let headline = Font.system(size: 17, weight: .semibold)  // line height 22
    static let body = Font.system(size: 17, weight: .regular)  // line height 22
    static let callout = Font.system(size: 16, weight: .regular)  // line height 21
    static let subheadline = Font.system(size: 15, weight: .regular)  // line height 20
    static let footnote = Font.system(size: 13, weight: .regular)  // line height 18
    static let caption = Font.system(size: 12, weight: .regular)  // line height 16
    static let tab = Font.system(size: 11, weight: .medium)  // line height 13
}

enum SNSpace {
    static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12, m: CGFloat = 16
    static let l: CGFloat = 20, xl: CGFloat = 24, xxl: CGFloat = 32, xxxl: CGFloat = 40
    static let gutter: CGFloat = 20, cardGap: CGFloat = 12, sectionGap: CGFloat = 22
}

enum SNRadius {
    static let key: CGFloat = 10, chip: CGFloat = 12, field: CGFloat = 14, tile: CGFloat = 14
    static let button: CGFloat = 16, tabBar: CGFloat = 22, card: CGFloat = 24, sheet: CGFloat = 32
}

// Glass card: iOS 26 Liquid Glass. Rounded rectangles only - never .capsule.
struct SNGlassCard: ViewModifier {
    var radius: CGFloat = SNRadius.card
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.glassHighlight, lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            }
    }
}
extension View {
    func snGlass(radius: CGFloat = SNRadius.card) -> some View { modifier(SNGlassCard(radius: radius)) }
}

// Amounts: semibold, tabular digits, currency before the number (₪1,653), isolated LTR inside RTL text.
struct SNAmount: View {
    let text: String
    var font: Font = SNFont.heroAmount
    var body: some View {
        Text(text).font(font).monospacedDigit()
            .environment(\.layoutDirection, .leftToRight)
            .contentTransition(.numericText())
    }
}

struct SNPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SNFont.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color.onButtonPrimary)
            .background(Color.buttonPrimary, in: .rect(cornerRadius: SNRadius.button))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
