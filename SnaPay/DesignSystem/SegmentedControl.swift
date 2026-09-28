import SwiftUI

/// Segmented control with rounded-rectangle segments (the system one is a capsule on iOS 26,
/// which the design rules exclude).
struct GlassSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        var id: Value { value }
    }

    @Binding var selection: Value
    let segments: [Segment]
    var identifier: String

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments) { segment in
                let isSelected = segment.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = segment.value }
                } label: {
                    Text(segment.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.background.opacity(0.9))
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("\(identifier).\(String(describing: segment.value))")
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.control))
    }
}
