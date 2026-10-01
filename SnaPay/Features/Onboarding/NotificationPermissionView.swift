import SwiftUI

/// First-launch explanation before the system notification prompt.
struct NotificationPermissionView: View {
    @Environment(AppState.self) private var app
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()

            VStack(spacing: Spacing.l) {
                Image(systemName: "bell")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 112, height: 112)
                    .glassSurface(radius: 32)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(Theme.destructive)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 18, y: 16)
                    }
                VStack(spacing: Spacing.sm) {
                    SampleNotification(title: "מיכל הוסיפה הוצאה", detail: "רמי לוי · \(Money.string(Decimal(string: "212.40")!, currency: "ILS"))")
                        .frame(width: 300)
                    SampleNotification(title: "מתקרבים לתקציב", detail: "קפה: 85% מהתקציב החודשי")
                        .frame(width: 282)
                        .opacity(0.85)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: Spacing.s) {
                Text("נשארים מעודכנים")
                    .font(Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("נעדכן אותך כשבן משפחה מוסיף הוצאה, כשמתקרבים לתקציב, וכשהסיכום החודשי מוכן.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.m)

            Spacer()

            VStack(spacing: Spacing.s) {
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
                .buttonStyle(.text)
                .accessibilityIdentifier("notifications.later")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.s)
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

/// A lock-screen-style notification for the illustration.
private struct SampleNotification: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            BrandTile(size: 36)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("SnaPay")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("עכשיו")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(Spacing.sm)
        .glassSurface(radius: 22)
    }
}
