import SwiftUI

/// On/off switch with a rounded-rectangle track and a square knob (the system switch is a
/// capsule, which the design rules exclude).
struct RoundedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: Spacing.m) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: 9)
                    .fill(configuration.isOn ? Theme.brand : Color.secondary.opacity(0.3))
                    .frame(width: 50, height: 30)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.white)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .padding(3)
                    }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == RoundedToggleStyle {
    static var rounded: RoundedToggleStyle { RoundedToggleStyle() }
}
