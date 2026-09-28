import SwiftUI
import SnaPayCore

/// Settings (design: `settings`): profile, shared account, month start, currency and fee,
/// trips, security, quick-log, notifications, sign-out and account deletion.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let store: TransactionStore

    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var isShowingPasswordSent = false
    @State private var isShowingTrips = false
    @State private var isShowingQuickLogSetup = false
    @State private var isDeletingAccount = false
    @State private var faceIDEnabled = DevicePreferences.isFaceIDEnabled
    @State private var notificationsAllowed = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                HStack {
                    IconButton(symbol: "chevron.backward", label: "חזרה") { dismiss() }
                        .accessibilityIdentifier("settings.close")
                    Spacer()
                }
                Text("הגדרות")
                    .font(Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)

                profileSection
                SharedAccountSection(store: store)
                monthStartSection
                currencySection
                tripsSection
                securitySection
                quickLogSection
                notificationsSection

                VStack(spacing: Spacing.sm) {
                    Button {
                        Task { await app.signOut() }
                    } label: {
                        Label("התנתקות", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.glassSecondary)
                    .accessibilityIdentifier("profile.signOut")

                    Button {
                        isDeletingAccount = true
                    } label: {
                        Label("מחיקת החשבון שלי", systemImage: "trash")
                            .font(.headline)
                            .foregroundStyle(Theme.expense)
                            .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                            .glassSurface(radius: Radius.control)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.deleteAccount")
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .background { AppBackground() }
        .task {
            await store.loadSharing()
            notificationsAllowed = await PushNotifications.isAllowed() || AppConfig.isUITesting
        }
        .alert("שם תצוגה", isPresented: $isEditingName) {
            TextField("שם מלא", text: $nameDraft)
            Button("שמירה") {
                let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await store.updateProfile(ProfileChanges(fullName: name)) }
            }
            Button("ביטול", role: .cancel) {}
        }
        .alert("שלחנו לך מייל", isPresented: $isShowingPasswordSent) {
            Button("הבנתי", role: .cancel) {}
        } message: {
            Text("פתחו את הקישור במייל כדי לבחור סיסמה חדשה.")
        }
        .sheet(isPresented: $isShowingTrips) { TripsView(store: store) }
        .sheet(isPresented: $isShowingQuickLogSetup) { QuickLogSetupView(store: store) }
        .sheet(isPresented: $isDeletingAccount) { DeleteAccountSheet() }
    }

    // MARK: Sections

    private var profileSection: some View {
        SettingsSection("הפרופיל שלי") {
            SettingsRow(symbol: "person", color: 0x3B82F6, title: "שם תצוגה", value: store.profile.fullName) {
                nameDraft = store.profile.fullName
                isEditingName = true
            }
            .accessibilityIdentifier("settings.name")
            SettingsDivider()
            SettingsRow(symbol: "envelope", color: 0x06B6D4, title: "אימייל", value: app.currentEmail ?? "", action: nil)
            SettingsDivider()
            SettingsRow(symbol: "lock", color: 0x8B5CF6, title: "שינוי סיסמה", value: nil) {
                guard let email = app.currentEmail else { return }
                Task {
                    try? await app.sendPasswordReset(email: email)
                    isShowingPasswordSent = true
                }
            }
        }
    }

    private var monthStartSection: some View {
        SettingsSection("תחילת החודש", footer: "הסיכומים בבית ובדוחות מתחילים ביום הזה בכל חודש, למשל כשהמשכורת נכנסת ב-10.") {
            ForEach([1, 10], id: \.self) { day in
                monthRow(title: "ה-\(day) לחודש", isSelected: store.profile.monthStartDay == day) {
                    Task { await store.updateProfile(ProfileChanges(monthStartDay: day)) }
                }
                SettingsDivider()
            }
            Menu {
                Picker("יום", selection: Binding(
                    get: { store.profile.monthStartDay },
                    set: { day in Task { await store.updateProfile(ProfileChanges(monthStartDay: day)) } }
                )) {
                    ForEach(1...31, id: \.self) { Text("ה-\($0) לחודש").tag($0) }
                }
            } label: {
                HStack {
                    Text("תאריך אחר")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if ![1, 10].contains(store.profile.monthStartDay) {
                        Text("ה-\(store.profile.monthStartDay) לחודש")
                            .foregroundStyle(Theme.brandInk)
                            .fontWeight(.semibold)
                    }
                    Image(systemName: "chevron.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 50)
                .contentShape(.rect)
            }
            .accessibilityIdentifier("settings.monthDay")
        }
    }

    private func monthRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.brandInk)
                }
            }
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var currencySection: some View {
        SettingsSection("מטבע ועמלות", footer: "המטבע העיקרי נקבע בהרשמה, וכל הסכומים נשמרים בו.") {
            SettingsRow(symbol: "banknote", color: 0x2FB36D, title: "מטבע עיקרי", value: CurrencyNames.label(for: store.mainCurrency), action: nil)
            SettingsDivider()
            HStack(spacing: Spacing.sm) {
                SettingsIcon(symbol: "percent", color: 0xF5B301)
                Text("עמלת המרה של כרטיס האשראי")
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.s)
                FeeStepper(value: store.profile.cardFxFeePercent) { value in
                    Task { await store.updateProfile(ProfileChanges(cardFxFeePercent: value)) }
                }
            }
            .frame(minHeight: 56)
        }
    }

    private var tripsSection: some View {
        SettingsSection("טיולים") {
            ForEach(store.trips.prefix(3)) { trip in
                HStack(spacing: Spacing.sm) {
                    EmojiTile(emoji: trip.emoji, color: Color(hex: trip.color), size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(trip.name).foregroundStyle(Theme.textPrimary)
                        Text(CurrencyNames.symbol(for: trip.tripCurrency ?? store.mainCurrency))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if trip.isActiveTrip(on: .now) {
                        StatusChip(title: "פעיל", style: .active)
                    }
                }
                .frame(minHeight: 52)
                SettingsDivider()
            }
            Button {
                isShowingTrips = true
            } label: {
                Label(store.trips.isEmpty ? "טיול חדש" : "כל הטיולים", systemImage: store.trips.isEmpty ? "plus" : "airplane")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.brandInk)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.trips")
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        if BiometricService.isAvailable || AppConfig.isUITesting {
            SettingsSection("אבטחה") {
                Toggle(isOn: Binding(
                    get: { faceIDEnabled },
                    set: { enabled in
                        faceIDEnabled = enabled
                        app.setFaceIDEnabled(enabled)
                    }
                )) {
                    SettingsLabel(symbol: "faceid", color: 0x14B8A6, title: "Face ID", detail: "נעילת האפליקציה בכל פתיחה")
                }
                .toggleStyle(.rounded)
                .frame(minHeight: 56)
                .accessibilityIdentifier("settings.faceID")
            }
        }
    }

    private var quickLogSection: some View {
        SettingsSection("תיעוד בקליק") {
            Toggle(isOn: Binding(
                get: { store.profile.quickLogEnabled },
                set: { enabled in Task { await store.setQuickLogEnabled(enabled) } }
            )) {
                SettingsLabel(symbol: "wave.3.right", color: 0x2FB36D, title: "תיעוד בקליק מ-Apple Pay", detail: nil)
            }
            .toggleStyle(.rounded)
            .frame(minHeight: 56)
            .accessibilityIdentifier("profile.quickLog")
            SettingsDivider()
            Button("הגדר מחדש את האוטומציה") { isShowingQuickLogSetup = true }
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.brandInk)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .accessibilityIdentifier("profile.quickLogSetup")
        }
    }

    private var notificationsSection: some View {
        SettingsSection("התראות") {
            if !notificationsAllowed {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bell.slash")
                        .foregroundStyle(Theme.warning)
                    Text("ההתראות כבויות בהגדרות האייפון.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("פתיחה") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brandInk)
                }
                .padding(Spacing.sm)
                .background(Theme.warningTint, in: .rect(cornerRadius: Radius.chip))
                .padding(.vertical, Spacing.s)
            }
            notificationToggle("בן משפחה הוסיף הוצאה", \.notifyPartnerActivity, id: "partner") { ProfileChanges(notifyPartnerActivity: $0) }
            SettingsDivider()
            notificationToggle("מתקרבים לתקציב", \.notifyBudget, id: "budget") { ProfileChanges(notifyBudget: $0) }
            SettingsDivider()
            notificationToggle("הסיכום החודשי מוכן", \.notifyMonthlyRecap, id: "recap") { ProfileChanges(notifyMonthlyRecap: $0) }
            SettingsDivider()
            notificationToggle("תשלום מחכה לקטגוריה", \.notifyPendingCapture, id: "pending") { ProfileChanges(notifyPendingCapture: $0) }
            SettingsDivider()
            notificationToggle("טיפים ועדכונים", \.notifyTips, id: "tips") { ProfileChanges(notifyTips: $0) }
        }
    }

    private func notificationToggle(
        _ title: LocalizedStringKey,
        _ keyPath: KeyPath<Profile, Bool>,
        id: String,
        changes: @escaping (Bool) -> ProfileChanges
    ) -> some View {
        Toggle(isOn: Binding(
            get: { store.profile[keyPath: keyPath] },
            set: { value in Task { await store.updateProfile(changes(value)) } }
        )) {
            Text(title).foregroundStyle(Theme.textPrimary)
        }
        .toggleStyle(.rounded)
        .frame(minHeight: 52)
        .accessibilityIdentifier("settings.notify.\(id)")
    }
}

/// −  2.5%  + in a rounded box, half a percent per step, 0–20%.
private struct FeeStepper: View {
    let value: Decimal
    var onChange: (Decimal) -> Void

    var body: some View {
        HStack(spacing: 0) {
            step(symbol: "minus", delta: -0.5)
            Text("\(NSDecimalNumber(decimal: value).stringValue)%")
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 52)
                .accessibilityIdentifier("settings.fee")
            step(symbol: "plus", delta: 0.5)
        }
        .frame(height: 40)
        .background(Theme.fill, in: .rect(cornerRadius: Radius.chip))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func step(symbol: String, delta: Decimal) -> some View {
        let next = min(max(value + delta, 0), 20)
        return Button {
            onChange(next)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(next == value)
        .accessibilityLabel(delta > 0 ? "הגדלת העמלה" : "הקטנת העמלה")
    }
}

/// "Type מחק to confirm" (design: `deleteacct`).
struct DeleteAccountSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var failure: AuthFailure?

    private var isConfirmed: Bool { confirmation.trimmingCharacters(in: .whitespaces) == "מחק" }

    var body: some View {
        VStack(spacing: Spacing.m) {
            FeatureIcon(symbol: "exclamationmark.triangle", color: Theme.destructive, size: 64)
            Text("למחוק את החשבון?")
                .font(Typography.title2)
                .foregroundStyle(Theme.textPrimary)
            Text("הפעולה תמחק לצמיתות את החשבון וכל המידע שהזנת. אי אפשר לשחזר.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 6) {
                Text("כדי לאשר, הקלידו \"מחק\"")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                TextField("", text: $confirmation)
                    .autocorrectionDisabled()
                    .fieldSurface(state: isConfirmed ? .focused : .normal)
                    .accessibilityIdentifier("delete.confirmation")
            }
            if let failure {
                ErrorBanner(message: failure.message)
            }
            Button {
                isDeleting = true
                failure = nil
                Task {
                    do {
                        try await app.deleteAccount()
                    } catch {
                        failure = error as? AuthFailure ?? .unknown
                        isDeleting = false
                    }
                }
            } label: {
                LoadingLabel(title: "מחיקה לצמיתות", isLoading: isDeleting)
            }
            .buttonStyle(.destructive)
            .disabled(!isConfirmed || isDeleting)
            .accessibilityIdentifier("delete.confirm")
            Button("ביטול") { dismiss() }
                .buttonStyle(.glassSecondary)
        }
        .padding(Spacing.l)
        .presentationDetents([.height(560)])
        .designSheet()
        .interactiveDismissDisabled(isDeleting)
    }
}

// MARK: Building blocks

/// A titled group of rows on a glass card.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Spacing.xs)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .glassSurface()
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: UInt32

    var body: some View {
        FeatureIcon(symbol: symbol, color: Color(uiColor: UIColor(hex: color)), size: 32)
    }
}

struct SettingsLabel: View {
    let symbol: String
    let color: UInt32
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SettingsIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// Icon, title, value on the trailing side and a chevron when tappable.
struct SettingsRow: View {
    let symbol: String
    let color: UInt32
    let title: LocalizedStringKey
    let value: String?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Spacing.sm) {
            SettingsIcon(symbol: symbol, color: color)
            Text(title)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Spacing.s)
            if let value {
                Text(value)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if action != nil {
                Image(systemName: "chevron.backward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
    }
}

/// "פעיל" / "הוזמן" labels.
struct StatusChip: View {
    enum Style { case active, invited }

    let title: LocalizedStringKey
    let style: Style

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(style == .active ? Theme.brandInk : Theme.warning)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(style == .active ? Theme.brandTint : Theme.warningTint, in: .rect(cornerRadius: 8))
    }
}
