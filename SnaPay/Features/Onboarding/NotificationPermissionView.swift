import SwiftUI

/// First-launch explanation before the system notification prompt.
struct NotificationPermissionView: View {
    @Environment(AppState.self) private var app
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()

            ZStack {
                Color.clear
                    .frame(width: 220, height: 120)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
                    .rotationEffect(.degrees(-4))
                    .offset(y: 18)
                GlassCard {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "bell.badge.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Theme.expense, Theme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("דנה הוסיפה הוצאה")
                                .font(.subheadline.weight(.semibold))
                            Text("₪48.90 · אוכל ומסעדות")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 280)
            }
            .accessibilityHidden(true)

            VStack(spacing: Spacing.s) {
                Text("נשארים מעודכנים")
                    .font(.largeTitle.weight(.bold))
                Text("נעדכן אותך כשבן משפחה מוסיף הוצאה, כשמתקרבים לתקציב, וכשהסיכום החודשי מוכן.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.m)

            Spacer()

            VStack(spacing: Spacing.m) {
                Button {
                    finish(allow: true)
                } label: {
                    LoadingLabel(title: "אפשר התראות", isLoading: isWorking)
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("notifications.allow")

                Button("אולי אחר כך") {
                    finish(allow: false)
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("notifications.later")
            }
        }
        .padding(Spacing.m)
        .disabled(isWorking)
    }

    private func finish(allow: Bool) {
        isWorking = true
        Task {
            await app.finishNotificationPrompt(allow: allow)
            isWorking = false
        }
    }
}
