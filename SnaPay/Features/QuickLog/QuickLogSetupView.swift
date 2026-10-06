import SwiftUI
import SnaPayCore

/// Walks the user through the one-time Shortcuts automation that powers quick-log (design:
/// `setup`), then waits for the first payment to arrive (`setupwait`).
struct QuickLogSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let store: TransactionStore

    private enum Phase { case guide, waiting }
    @State private var phase: Phase
    /// Set once the ready-made shortcut's link was opened; the main button then opens Shortcuts.
    @AppStorage("quickLog.shortcutOffered") private var shortcutOffered = false
    private let shortcutURL = AppConfig.quickLogShortcutURL
    @State private var isShowingDiagnostics = false

    init(store: TransactionStore) {
        self.store = store
        _phase = State(initialValue: store.quickLogFirstCaptureAt == nil ? .guide : .waiting)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.l)

            Group {
                switch phase {
                case .guide: guide
                case .waiting: waiting
                }
            }
            .transition(.opacity)
        }
        .background { AppBackground() }
        .animation(.easeInOut(duration: 0.25), value: phase)
        .task { store.reloadQuickLogInbox() }
        .sheet(isPresented: $isShowingDiagnostics) { QuickLogDiagnosticsView() }
    }

    /// Close button, progress line (no step numbers) and "skip for now".
    private var topBar: some View {
        HStack(spacing: Spacing.m) {
            IconButton(symbol: "xmark", label: "סגירה") { dismiss() }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.track)
                    RoundedRectangle(cornerRadius: 3).fill(Theme.brand)
                        .frame(width: proxy.size.width * (phase == .guide ? 0.5 : 1))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Button("דלג בינתיים") { dismiss() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.brandInk)
        }
    }

    // MARK: Guide

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("הגדרת תיעוד בקליק")
                        .font(Typography.largeTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("אוטומציה אחת בקיצורים, ומעכשיו כל תשלום ב-Apple Pay מגיע ישר ל-SnaPay.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                if !store.profile.quickLogEnabled {
                    Label("התיעוד בקליק כבוי כרגע. אפשר להפעיל אותו בפרופיל.", systemImage: "pause.circle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.warning)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warningTint, in: .rect(cornerRadius: Radius.chip))
                }

                VStack(spacing: Spacing.cardGap) {
                    if shortcutURL != nil {
                        SetupStep(isLast: false, text: "לחצו על **הוספת הקיצור** למטה, ואשרו ב**הוספת קיצור**.") {
                            actionRow(title: "תיעוד ב-SnaPay", subtitle: "קיצור מוכן")
                        }
                    }
                    SetupStep(isLast: false, text: "באפליקציית **קיצורים**, עברו ל**אוטומציה**, לחצו על פלוס ובחרו **Wallet**.") {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color(uiColor: UIColor(hex: 0x3B82F6)), in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Wallet").font(.subheadline.weight(.bold))
                                Text("כשמקישים על כרטיס ב-Wallet").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.backward").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    SetupStep(isLast: false, text: shortcutURL == nil
                              ? "השאירו **כל כרטיס** (Any Card) ואת **Automation** דלוק, כדי שזה ירוץ לבד בלי לשאול."
                              : "השאירו **כל כרטיס** (Any Card) ואת **Automation** דלוק, ולחצו **הבא**.") {
                        HStack {
                            Text("Automation").font(.subheadline)
                            Spacer()
                            RoundedRectangle(cornerRadius: 11)
                                .fill(Theme.buttonPrimary)
                                .frame(width: 52, height: 32)
                                .overlay(alignment: .trailing) {
                                    RoundedRectangle(cornerRadius: 9).fill(.white).frame(width: 26, height: 26).padding(3)
                                }
                        }
                    }
                    if shortcutURL != nil {
                        SetupStep(isLast: true, text: "ברשימת הקיצורים, בחרו **תיעוד ב-SnaPay**. הסכום, בית העסק והכרטיס יעברו אליו לבד.") {
                            actionRow(title: "תיעוד ב-SnaPay", subtitle: "סכום · בית עסק")
                        }
                    } else {
                        SetupStep(isLast: true, text: "הוסיפו את הפעולה **תיעוד תשלום** של SnaPay, ובכל שדה בחרו **Transaction**: סכום ← **Amount**, בית עסק ← **Merchant**, כרטיס ← **Card or Pass**.") {
                            actionRow(title: "תיעוד תשלום", subtitle: "סכום · בית עסק")
                        }
                    }
                }

                Text("החלונית מופיעה רק כשמשלמים בכרטיסים שבחרתם. תשלום שלא סווג מחכה במסך הבית.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.l)
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: Spacing.s) {
                if let shortcutURL, !shortcutOffered {
                    Button {
                        shortcutOffered = true
                        openURL(shortcutURL)
                    } label: {
                        Label("הוספת הקיצור", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("quicklog.addShortcut")
                } else {
                    Button {
                        openURL(URL(string: "shortcuts://")!)
                    } label: {
                        Label("פתח את קיצורים", systemImage: "square.2.layers.3d")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("quicklog.openShortcuts")
                }
                Button("כבר הגדרתי") { phase = .waiting }
                    .buttonStyle(.text)
                    .accessibilityIdentifier("quicklog.alreadySet")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.s)
        }
    }

    /// The SnaPay action (or the ready-made shortcut) as it looks in Shortcuts.
    private func actionRow(title: String, subtitle: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "doc.text")
            Text(title).font(.subheadline.weight(.bold))
            Spacer()
            Text(subtitle).font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .frame(height: 40)
        .background(
            LinearGradient(colors: [Theme.buttonPrimary, Theme.brand], startPoint: .leading, endPoint: .trailing),
            in: .rect(cornerRadius: 12)
        )
    }

    // MARK: Waiting

    private var waiting: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            illustration
            VStack(spacing: Spacing.s) {
                Text(store.quickLogFirstCaptureAt == nil ? "ההגדרה הסתיימה" : "מעולה, זה עובד!")
                    .font(Typography.title1)
                    .foregroundStyle(Theme.textPrimary)
                Text(store.quickLogFirstCaptureAt == nil
                     ? "מחכה לקליטה הראשונה מהפעולה האוטומטית. אחרי התשלום הבא נדע שהכול מחובר."
                     : "התשלום הראשון נקלט. מעכשיו כל תשלום ב-Apple Pay מגיע ל-SnaPay.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            statusChip
            Spacer()
            VStack(spacing: Spacing.s) {
                Button("סיימתי") { dismiss() }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("quicklog.done")
                if store.quickLogFirstCaptureAt == nil {
                    Button("חזרה להוראות") { phase = .guide }
                        .buttonStyle(.text)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.s)
    }

    /// Card → phone → SnaPay, joined by dotted lines.
    private var illustration: some View {
        HStack(spacing: Spacing.sm) {
            BrandTile(size: 64)
            dots
            Image(systemName: "wave.3.right")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 74, height: 140)
                .glassSurface(radius: 26)
            dots
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(uiColor: UIColor(hex: 0x5B8DEF)), Color(uiColor: UIColor(hex: 0x14B8A6))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 60)
                .overlay(alignment: .bottomTrailing) {
                    Text("•••• 4821")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                }
                .rotationEffect(.degrees(-6))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(Theme.brand.opacity(1 - Double(index) * 0.3)).frame(width: 6, height: 6)
            }
        }
    }

    /// A long press on the status opens the diagnostics log (hidden: for troubleshooting).
    @ViewBuilder
    private var statusChip: some View {
        Group {
            if let first = store.quickLogFirstCaptureAt {
                chip(color: Theme.brand, text: "התשלום הראשון נקלט ב\(first.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.wide).hour().minute()))")
                    .accessibilityIdentifier("quicklog.status")
            } else {
                chip(color: Theme.warning, text: "מחכה לתשלום הראשון")
                    .accessibilityIdentifier("quicklog.status.waiting")
            }
        }
        .onLongPressGesture { isShowingDiagnostics = true }
    }

    private func chip(color: Color, text: String) -> some View {
        HStack(spacing: Spacing.s) {
            Circle()
                .strokeBorder(color, lineWidth: 3)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(color.opacity(0.18), in: .circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 40)
        .glassSurface(radius: Radius.chip)
        .accessibilityElement(children: .combine)
    }
}

/// One step of the guide: a card with a small mock of the Shortcuts screen and the
/// instruction, on a timeline (dot and line) at the leading edge.
private struct SetupStep<Mock: View>: View {
    let isLast: Bool
    let text: LocalizedStringKey
    @ViewBuilder var mock: Mock

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 12, height: 12)
                    .padding(4)
                    .background(Theme.brandTint, in: .circle)
                    .padding(.top, Spacing.l)
                if !isLast {
                    Rectangle().fill(Theme.track).frame(width: 2)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    mock
                        .foregroundStyle(Theme.textPrimary)
                        .padding(Spacing.sm)
                        .background(Theme.field, in: .rect(cornerRadius: Radius.field))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Theme.stroke, lineWidth: 1))
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }
}
