import SwiftUI

struct LaunchView: View {
    var body: some View {
        VStack(spacing: Spacing.l) {
            BrandTile(size: 88)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when the app starts with Face ID enabled, or returns from the background.
struct FaceIDLockView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            VStack(spacing: Spacing.m) {
                BrandTile(size: 88)
                (Text("Sna").foregroundStyle(Theme.textPrimary) + Text("Pay").foregroundStyle(Theme.brand))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .environment(\.layoutDirection, .leftToRight)
                Text("הנתונים שלך נעולים עד שתזדהה")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Image(systemName: "faceid")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(Theme.brand)
                .frame(width: 132, height: 132)
                .glassSurface(radius: 36)
                .padding(.top, Spacing.l)
                .accessibilityHidden(true)
            Spacer()
            VStack(spacing: Spacing.s) {
                Button {
                    Task { await app.unlock() }
                } label: {
                    Label("פתח עם Face ID", systemImage: "faceid")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("lock.unlock")
                // Face ID falls back to the passcode by itself; this offers it up front.
                Button("הזנת קוד הגישה") {
                    Task { await app.unlock() }
                }
                .buttonStyle(.text)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.s)
        .task { await app.unlock() }
    }
}

struct ConnectionProblemView: View {
    @Environment(AppState.self) private var app
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary)
            Text("אין חיבור לשרת")
                .font(Typography.title2)
                .foregroundStyle(Theme.textPrimary)
            Text("בדקו את החיבור לאינטרנט ונסו שוב.")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                isRetrying = true
                Task {
                    await app.retryAfterConnectionProblem()
                    isRetrying = false
                }
            } label: {
                LoadingLabel(title: "נסו שוב", isLoading: isRetrying)
            }
            .buttonStyle(.primary)
            .disabled(isRetrying)
        }
        .padding(Spacing.m)
    }
}

/// Builds without Supabase settings (before the project exists) show this instead of crashing.
struct ServerNotConfiguredView: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary)
            Text("השרת עדיין לא מוגדר")
                .font(.title2.weight(.bold))
            Text("הגרסה הזו נבנתה בלי כתובת השרת. אחרי שיוגדר פרויקט Supabase, הגרסה הבאה תעבוד.")
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.l)
    }
}
