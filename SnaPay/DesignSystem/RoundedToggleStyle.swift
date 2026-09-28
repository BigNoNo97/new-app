import SwiftUI

/// On/off switch with a rounded-rectangle track and a square-ish knob (the system switch is a
/// capsule, which the design rules exclude).
struct RoundedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: Spacing.m) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                // 52×32, radius 11, square-ish knob radius 9 (design: components / switch).
                RoundedRectangle(cornerRadius: 11)
                    .fill(configuration.isOn ? Theme.buttonPrimary : Theme.fillStrong)
                    .frame(width: 52, height: 32)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(.white)
                            .frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
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
