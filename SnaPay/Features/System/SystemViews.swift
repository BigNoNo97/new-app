import SwiftUI

struct LaunchView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when the app starts with Face ID enabled, or returns from the background.
struct FaceIDLockView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 104, height: 104)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
            Text("SnaPay נעול")
                .font(.title.weight(.bold))
            Spacer()
            Button {
                Task { await app.unlock() }
            } label: {
                Label("פתיחה עם Face ID", systemImage: "faceid")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("lock.unlock")
        }
        .padding(Spacing.m)
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
                .foregroundStyle(.secondary)
            Text("אין חיבור לשרת")
                .font(.title2.weight(.bold))
            Text("בדקו את החיבור לאינטרנט ונסו שוב.")
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Text("השרת עדיין לא מוגדר")
                .font(.title2.weight(.bold))
            Text("הגרסה הזו נבנתה בלי כתובת השרת. אחרי שיוגדר פרויקט Supabase, הגרסה הבאה תעבוד.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.l)
    }
}
