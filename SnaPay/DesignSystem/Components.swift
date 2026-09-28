import SwiftUI

/// The atmospheric gradient with soft blurred light spots that sits behind every screen.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.backgroundTop, Theme.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle().fill(Theme.glow1).frame(width: 320).blur(radius: 120).offset(x: 80, y: -60)
        }
        .overlay(alignment: .bottomLeading) {
            Circle().fill(Theme.glow2).frame(width: 280).blur(radius: 120).offset(x: -60, y: 40)
        }
        .ignoresSafeArea()
    }
}

/// A Liquid Glass card.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }
}

/// Main call to action: solid brand color, rounded rectangle.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.brand, in: .rect(cornerRadius: Radius.control))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary action: glass, rounded rectangle.
struct SecondaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryGlassButtonStyle {
    static var glassSecondary: SecondaryGlassButtonStyle { SecondaryGlassButtonStyle() }
}

/// The floating bottom navigation: a rounded-rectangle glass bar (not a capsule) with a
/// raised circular "+" in the middle.
struct BottomBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                item(.home)
                item(.expenses)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Theme.brand, in: .circle)
                        .shadow(color: Theme.brand.opacity(0.35), radius: 12, y: 6)
                }
                .accessibilityLabel(Text("הוספה"))
                .accessibilityIdentifier("tab.add")
                .offset(y: -14)
                .frame(maxWidth: .infinity)
                item(.goals)
                item(.profile)
            }
            .padding(.horizontal, Spacing.s)
            .frame(height: 68)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
        }
    }

    private func item(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: selection == tab ? "\(tab.symbol).fill" : tab.symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(tab.title)
                    .font(.caption2.weight(selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? Theme.brand : .secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityIdentifier("tab.\(tab)")
    }
}
