import SwiftUI
import SnaPayCore

/// Settings → חשבון משותף: who's in the household, pending invites, and inviting by email.
/// Each member logs only their own entries and sees everyone's (the server enforces it).
struct SharedAccountSection: View {
    @Environment(AppState.self) private var app
    let store: TransactionStore

    @State private var email = ""
    @State private var emailIssue: CredentialsIssue?
    @State private var failure: HouseholdFailure?
    @State private var isSending = false
    @State private var lastInvited: String?
    @State private var removing: HouseholdMember?
    @State private var isConfirmingLeave = false
    @State private var isLeaving = false

    private var isShared: Bool { store.household?.isShared ?? store.isShared }

    var body: some View {
        SettingsSection("חשבון משותף", footer: "כל שותף מתעד רק את ההוצאות שלו, ורואה את של כולם.") {
            Toggle(isOn: Binding(
                get: { isShared },
                set: { value in Task { try? await store.setShared(value) } }
            )) {
                SettingsLabel(symbol: "person.2", color: 0xE056B0, title: "חשבון משותף", detail: nil)
            }
            .toggleStyle(.rounded)
            .frame(minHeight: 56)
            .disabled(!store.isOwner || store.members.count > 1)
            .accessibilityIdentifier("sharing.toggle")

            if isShared || store.members.count > 1 || !store.sentInvites.isEmpty {
                ForEach(store.members) { member in
                    SettingsDivider()
                    memberRow(member)
                }
                ForEach(store.sentInvites) { invite in
                    SettingsDivider()
                    inviteRow(invite)
                }
                SettingsDivider()
                inviteField
                    .padding(.vertical, Spacing.sm)
                if let lastInvited {
                    ShareLink(item: Self.inviteMessage(for: lastInvited)) {
                        Label("שליחת ההזמנה בהודעה", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.brandInk)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("sharing.shareInvite")
                }
                if store.members.count > 1 {
                    SettingsDivider()
                    Button(role: .destructive) {
                        isConfirmingLeave = true
                    } label: {
                        LoadingLabel(title: "יציאה מהחשבון המשותף", isLoading: isLeaving)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.expense)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLeaving)
                    .accessibilityIdentifier("sharing.leave")
                }
            }
        }
        .confirmationDialog(
            "להסיר את \(removing?.firstName ?? "") מהחשבון?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("הסרה", role: .destructive) {
                guard let member = removing else { return }
                Task {
                    do {
                        try await store.removeMember(member)
                    } catch {
                        failure = error as? HouseholdFailure ?? .unknown
                    }
                }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("ההוצאות שתיעדו יעברו איתם לחשבון אישי חדש.")
        }
        .confirmationDialog("לצאת מהחשבון המשותף?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("יציאה", role: .destructive) {
                isLeaving = true
                Task {
                    do {
                        try await app.leaveHousehold()
                    } catch {
                        failure = error as? HouseholdFailure ?? .unknown
                    }
                    isLeaving = false
                }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("ההוצאות שתיעדת יעברו איתך לחשבון אישי חדש, עם עותק של הקטגוריות. השותפים ימשיכו בלעדיך.")
        }
    }

    private func memberRow(_ member: HouseholdMember) -> some View {
        let isMe = member.id == store.userID
        return HStack(spacing: Spacing.sm) {
            MemberAvatar(id: member.id, name: member.firstName, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? "\(member.fullName) (אתה)" : member.fullName)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(isMe ? (app.currentEmail ?? "") : (member.isOwner ? "מנהל/ת החשבון" : "שותף/ה"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusChip(title: "פעיל", style: .active)
        }
        .frame(minHeight: 56)
        .contextMenu {
            if store.isOwner && !isMe {
                Button("הסרה מהחשבון", systemImage: "person.badge.minus", role: .destructive) { removing = member }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sharing.member.\(member.firstName)")
    }

    private func inviteRow(_ invite: HouseholdInviteRow) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(String(invite.email.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.warning)
                .frame(width: 36, height: 36)
                .background(Theme.warningTint, in: .circle)
            Text(invite.email)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            StatusChip(title: "הוזמן", style: .invited)
        }
        .frame(minHeight: 56)
        .contextMenu {
            Button("ביטול ההזמנה", systemImage: "xmark", role: .destructive) {
                Task { await store.revokeInvite(invite) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sharing.invite.\(invite.email)")
    }

    private var inviteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "envelope")
                        .foregroundStyle(Theme.textTertiary)
                    TextField("אימייל של השותף", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .accessibilityIdentifier("sharing.email")
                }
                .fieldSurface(state: emailIssue == nil ? .normal : .error)
                Button(action: send) {
                    LoadingLabel(title: "הזמנה", isLoading: isSending)
                        .font(.headline)
                        .foregroundStyle(Theme.onButtonPrimary)
                        .padding(.horizontal, Spacing.m)
                        .frame(height: Metrics.fieldHeight)
                        .background(Theme.buttonPrimary, in: .rect(cornerRadius: Radius.field))
                }
                .buttonStyle(.plain)
                .disabled(isSending || email.isEmpty)
                .accessibilityIdentifier("sharing.send")
            }
            if let emailIssue {
                FieldErrorText(message: emailIssue.message)
            }
            if let failure {
                FieldErrorText(message: failure.message)
                    .accessibilityIdentifier("sharing.error")
            }
        }
    }

    private func send() {
        emailIssue = CredentialsValidator.emailIssue(email)
        failure = nil
        guard emailIssue == nil else { return }
        let normalized = CredentialsValidator.normalizedEmail(email)
        if normalized == app.currentEmail?.lowercased() {
            failure = .alreadyMember
            return
        }
        isSending = true
        Task {
            do {
                try await store.invite(email: normalized)
                lastInvited = normalized
                email = ""
            } catch {
                failure = error as? HouseholdFailure ?? .unknown
            }
            isSending = false
        }
    }

    /// The message the inviter can send (WhatsApp, SMS…): the invite waits in the app for
    /// that email.
    static func inviteMessage(for email: String) -> String {
        "הזמנתי אותך לחשבון המשותף שלנו ב-SnaPay, כדי שנראה יחד לאן הולך הכסף. "
            + "מורידים את SnaPay מה-App Store ונרשמים (או מתחברים) עם \(email), וההזמנה מחכה שם."
    }
}

extension HouseholdFailure {
    var message: LocalizedStringKey {
        switch self {
        case .inviteAlreadyPending: "כבר שלחת הזמנה לכתובת הזו."
        case .inviteNotFound: "ההזמנה כבר לא בתוקף."
        case .alreadyMember: "זה המייל שלך. צריך להזין את המייל של השותף."
        case .notOwner: "רק מי שמנהל את החשבון יכול להסיר שותפים."
        case .emailNotVerified: "צריך קודם לאשר את כתובת המייל. שלחנו לך קישור לאישור, ואחריו אפשר לנסות שוב."
        case .network: "אין חיבור לאינטרנט. נסו שוב."
        case .unknown: "משהו השתבש. נסו שוב."
        }
    }
}

/// Shown on the main screen when someone invited my email to their household.
struct InviteReceivedSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let invite: PendingInvite

    @State private var isWorking = false
    @State private var failure: HouseholdFailure?

    var body: some View {
        VStack(spacing: Spacing.m) {
            HStack(spacing: -12) {
                MemberAvatar(id: invite.householdID, name: invite.inviterFirstName, size: 56)
                    .overlay(Circle().strokeBorder(Theme.glassStrong, lineWidth: 3))
                FeatureIcon(symbol: "plus", color: Theme.brand, size: 56)
                    .clipShape(.circle)
                    .overlay(Circle().strokeBorder(Theme.glassStrong, lineWidth: 3))
            }
            .padding(.top, Spacing.m)
            Text("הזמנה לחשבון משותף")
                .font(Typography.title2)
                .foregroundStyle(Theme.textPrimary)
            Text("\(invite.inviterFirstName.isEmpty ? "מישהו" : invite.inviterFirstName) רוצה לנהל איתך את ההוצאות יחד. כל אחד מתעד את שלו, וכולם רואים הכול.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Label("ההוצאות שתיעדת עד עכשיו יעברו איתך לחשבון המשותף.", systemImage: "arrow.left.arrow.right")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fill, in: .rect(cornerRadius: Radius.chip))
            if let failure {
                ErrorBanner(message: failure.message)
            }
            Button {
                respond(accept: true)
            } label: {
                LoadingLabel(title: "הצטרפות", isLoading: isWorking)
            }
            .buttonStyle(.primary)
            .disabled(isWorking)
            .accessibilityIdentifier("invite.accept")
            HStack {
                Button("לא עכשיו") { dismiss() }
                    .buttonStyle(.text)
                Spacer()
                Button("דחיית ההזמנה") { respond(accept: false) }
                    .font(.headline)
                    .foregroundStyle(Theme.expense)
                    .disabled(isWorking)
                    .accessibilityIdentifier("invite.decline")
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.m)
        .presentationDetents([.height(520)])
        .designSheet()
        .interactiveDismissDisabled(isWorking)
    }

    private func respond(accept: Bool) {
        isWorking = true
        failure = nil
        Task {
            do {
                if accept {
                    try await app.accept(invite)
                } else {
                    try await app.decline(invite)
                }
                dismiss()
            } catch {
                failure = error as? HouseholdFailure ?? .unknown
            }
            isWorking = false
        }
    }
}
