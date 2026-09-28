import SwiftUI

/// The atmospheric background behind every screen: a cool gradient with soft color blooms, plus
/// small blurred light dots in dark mode (docs/design/claude-design/design-tokens: background).
/// Positions come from the design's 393pt-wide canvas and scale with the screen width.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    private struct Bloom {
        let x: CGFloat, y: CGFloat, size: CGFloat
        let light: UInt32, lightOpacity: Double
        let dark: UInt32, darkOpacity: Double
    }

    private static let blooms: [Bloom] = [
        Bloom(x: 120, y: -72, size: 201, light: 0x8FE3B8, lightOpacity: 0.5, dark: 0x1FA38A, darkOpacity: 0.55),
        Bloom(x: 81, y: 66, size: 297, light: 0xAFD2F5, lightOpacity: 0.55, dark: 0x2F6FE0, darkOpacity: 0.38),
        Bloom(x: -98, y: 253, size: 287, light: 0xD8F29A, lightOpacity: 0.4, dark: 0x3DDC84, darkOpacity: 0.22),
        Bloom(x: 154, y: 483, size: 214, light: 0xA7E8E0, lightOpacity: 0.45, dark: 0xF2B35B, darkOpacity: 0.14),
        Bloom(x: 267, y: 615, size: 291, light: 0xC9DCF7, lightOpacity: 0.45, dark: 0x15706A, darkOpacity: 0.45),
    ]

    private struct Dot {
        let x: CGFloat, y: CGFloat, size: CGFloat, color: UInt32, opacity: Double
    }

    /// Dark mode "bokeh".
    private static let dots: [Dot] = [
        Dot(x: 60, y: 41, size: 15, color: 0xFFFFFF, opacity: 0.43),
        Dot(x: 370, y: 444, size: 23, color: 0xF6C177, opacity: 0.31),
        Dot(x: 105, y: 676, size: 22, color: 0x7CF2B6, opacity: 0.31),
        Dot(x: 92, y: 728, size: 13, color: 0x9FE8FF, opacity: 0.22),
        Dot(x: 300, y: 210, size: 18, color: 0x8FB3FF, opacity: 0.3),
        Dot(x: 30, y: 520, size: 26, color: 0x7CF2B6, opacity: 0.18),
        Dot(x: 340, y: 790, size: 12, color: 0xFFFFFF, opacity: 0.3),
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 393
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    stops: scheme == .dark
                        ? [.init(color: Color(uiColor: UIColor(hex: 0x050A12)), location: 0),
                           .init(color: Color(uiColor: UIColor(hex: 0x0A1524)), location: 0.38),
                           .init(color: Color(uiColor: UIColor(hex: 0x08202B)), location: 0.72),
                           .init(color: Color(uiColor: UIColor(hex: 0x06282B)), location: 1)]
                        : [.init(color: Color(uiColor: UIColor(hex: 0xF8FBFD)), location: 0),
                           .init(color: Color(uiColor: UIColor(hex: 0xEDF5F9)), location: 0.45),
                           .init(color: Color(uiColor: UIColor(hex: 0xE4F5EC)), location: 1)],
                    startPoint: UnitPoint(x: 0.4, y: 0),
                    endPoint: UnitPoint(x: 0.6, y: 1)
                )
                ForEach(Self.blooms.indices, id: \.self) { index in
                    let bloom = Self.blooms[index]
                    let color = Color(uiColor: UIColor(hex: scheme == .dark ? bloom.dark : bloom.light))
                        .opacity(scheme == .dark ? bloom.darkOpacity : bloom.lightOpacity)
                    Circle()
                        .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: bloom.size * scale * 0.34))
                        .frame(width: bloom.size * scale, height: bloom.size * scale)
                        .blur(radius: 18)
                        .offset(x: bloom.x * scale, y: bloom.y * scale)
                }
                if scheme == .dark {
                    ForEach(Self.dots.indices, id: \.self) { index in
                        let dot = Self.dots[index]
                        Circle()
                            .fill(Color(uiColor: UIColor(hex: dot.color)).opacity(dot.opacity))
                            .frame(width: dot.size * 0.7, height: dot.size * 0.7)
                            .blur(radius: dot.size / 6)
                            .offset(x: dot.x * scale, y: dot.y * scale)
                    }
                }
            }
            // Laid out left to right like the design canvas, whatever the text direction.
            .environment(\.layoutDirection, .leftToRight)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A Liquid Glass card: radius 24, a 1pt stroke, a bright top edge and a soft shadow.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Spacing.m
    var radius: CGFloat = Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: radius)
    }
}

extension View {
    /// The card surface on its own, for views that manage their own padding.
    func glassSurface(radius: CGFloat = Radius.card, interactive: Bool = false) -> some View {
        modifier(GlassSurface(radius: radius, interactive: interactive))
    }
}

private struct GlassSurface: ViewModifier {
    let radius: CGFloat
    let interactive: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            }
            .overlay {
                // The 1pt highlight along the top edge.
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.glassHighlight, lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)))
            }
            .shadow(
                color: scheme == .dark ? .black.opacity(0.38) : Color(uiColor: UIColor(hex: 0x183C50)).opacity(0.10),
                radius: scheme == .dark ? 18 : 15, y: scheme == .dark ? 14 : 10
            )
    }
}

/// Main call to action: height 54, radius 16, solid dark green (bright green in dark mode).
struct PrimaryButtonStyle: ButtonStyle {
    var role: Role = .normal

    enum Role { case normal, destructive }

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let background = role == .destructive ? Theme.destructive : Theme.buttonPrimary
        configuration.label
            .font(.headline)
            .foregroundStyle(role == .destructive ? Color.white : Theme.onButtonPrimary)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .background(background, in: .rect(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)))
            }
            .shadow(color: background.opacity(isEnabled ? 0.3 : 0), radius: 12, y: 8)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary action: glass, height 54, radius 16.
struct SecondaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
            .glassSurface(radius: Radius.control, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Text-only action in brand green ("אולי אחר כך").
struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.brandInk)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var destructive: PrimaryButtonStyle { PrimaryButtonStyle(role: .destructive) }
}

extension ButtonStyle where Self == SecondaryGlassButtonStyle {
    static var glassSecondary: SecondaryGlassButtonStyle { SecondaryGlassButtonStyle() }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
}

/// A 44pt square glass icon button (bell, gear, close).
struct IconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .glassSurface(radius: Radius.field, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The floating bottom navigation: a glass bar (radius 22, not a capsule) with a raised 62pt
/// green "+" circle in the middle. Right to left: בית · הוצאות · + · יעדים · פרופיל.
struct BottomBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.expenses)
            Color.clear.frame(width: Metrics.plusButton + Spacing.m)
            item(.goals)
            item(.profile)
        }
        .padding(.horizontal, Spacing.s)
        .frame(height: Metrics.tabBarHeight)
        .glassSurface(radius: Radius.tabBar)
        .overlay(alignment: .top) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.onButtonPrimary)
                    .frame(width: Metrics.plusButton, height: Metrics.plusButton)
                    .background(
                        LinearGradient(colors: [Theme.brand, Theme.buttonPrimary], startPoint: .top, endPoint: .bottom),
                        in: .circle
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: Theme.brand.opacity(0.4), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("הוספה"))
            .accessibilityIdentifier("tab.add")
            .offset(y: -Metrics.plusRaise)
        }
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: isSelected ? "\(tab.symbol).fill" : tab.symbol)
                    .font(.system(size: 21, weight: .medium))
                Text(tab.title)
                    .font(Typography.tab.weight(isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Theme.brandInk : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tab.\(tab)")
    }
}

/// The logo: receipt-with-bars symbol and the "SnaPay" wordmark, "Pay" in brand green.
struct BrandMark: View {
    var size: CGFloat = 44
    var showsWordmark = true

    var body: some View {
        HStack(spacing: size * 0.22) {
            Image("BrandSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            if showsWordmark {
                (Text("Sna").foregroundStyle(Theme.textPrimary) + Text("Pay").foregroundStyle(Theme.brandInk))
                    .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SnaPay")
    }
}
