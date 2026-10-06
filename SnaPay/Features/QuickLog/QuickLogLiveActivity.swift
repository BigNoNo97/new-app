import ActivityKit
import Foundation
import UserNotifications

/// Starts, updates and ends the quick-log Live Activity (drawn by the widget extension). Runs in
/// the app's process, usually in the background while a Shortcuts automation runs.
///
/// iOS shows the expanded card for a few seconds when the alert fires, then shrinks it to the
/// pill around the Dynamic Island (a long press opens it again); the Lock Screen keeps the full
/// card. Either stays until a category is chosen: nothing here ends a payment's card before that.
/// Every start and end goes to the diagnostics log (`QuickLogStorage.log`).
enum QuickLogLiveActivity {
    /// How long the "נשמר ב…" line (with undo and note) stays before the card goes away.
    static let savedLingers: TimeInterval = 10

    /// After the automation captured a payment (`key` is its id, or why nothing was captured):
    /// show the card, expanding out of the Dynamic Island. Without Live Activities, or when
    /// nothing was captured, a notification says what happened instead.
    static func present(key: String) async {
        if let id = UUID(uuidString: key) {
            if await start(paymentID: id, alerting: true) { return }
            if case let .payment(payment) = QuickLogService.card(for: key).state {
                notify(title: "תשלום מחכה לקטגוריה", body: "\(payment.merchant) · \(payment.amount). לחיצה פותחת את SnaPay.")
            }
        } else if case let .message(title, detail) = QuickLogService.card(for: key).state {
            QuickLogStorage.log("לא נקלט: \(key)")
            notify(title: title, body: detail)
        }
    }

    /// Shows the payment's card, replacing other payments' cards. Updates the payment's card if
    /// it already shows (after undo). Returns false when Live Activities are off or the payment
    /// is no longer waiting.
    @discardableResult
    static func start(paymentID: UUID, alerting: Bool) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            QuickLogStorage.log("Live Activities כבויות בהגדרות")
            return false
        }
        guard let state = state(for: paymentID) else {
            QuickLogStorage.log("אין תשלום ממתין \(short(paymentID))")
            return false
        }
        let content = ActivityContent(state: state, staleDate: nil)
        // Plain loops, as in showSaved: each activity goes straight to update/end.
        var hasCard = false
        for activity in Activity<QuickLogActivityAttributes>.activities {
            if activity.attributes.paymentID == paymentID, activity.activityState == .active {
                hasCard = true
                // One call per activity: Swift 6 treats each as handing the activity off.
                if alerting {
                    await activity.update(content, alertConfiguration: alert(for: state))
                } else {
                    await activity.update(content)
                }
            } else {
                QuickLogStorage.log("סגירה: כרטיס קודם \(short(activity.attributes.paymentID)) (\(activity.activityState))")
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        if !hasCard {
            do {
                let activity = try Activity.request(attributes: QuickLogActivityAttributes(paymentID: paymentID), content: content)
                QuickLogStorage.log("כרטיס נפתח \(short(paymentID))")
                if alerting {
                    // The alert is what expands the card out of the Dynamic Island and lights the Lock Screen.
                    await activity.update(content, alertConfiguration: alert(for: state))
                }
            } catch {
                QuickLogStorage.log("פתיחת כרטיס נכשלה: \(error.localizedDescription)")
                return false
            }
        }
        return true
    }

    /// Redraws the payment's card without an alert (the on-device model's guess arrived).
    static func refresh(paymentID: UUID) async {
        guard let state = state(for: paymentID), state.chosen == nil else { return }
        for activity in Activity<QuickLogActivityAttributes>.activities where activity.attributes.paymentID == paymentID {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// After a category was tapped: the "נשמר ב…" line with undo, then the card goes away.
    static func showSaved(paymentID: UUID) async {
        // A loop, not first(where:): handing the activity to a (main-actor) closure would tie it to
        // the main actor, and Swift 6 then refuses to pass it to end(_:dismissalPolicy:).
        for activity in Activity<QuickLogActivityAttributes>.activities where activity.attributes.paymentID == paymentID {
            guard let state = state(for: paymentID), state.chosen != nil else {
                QuickLogStorage.log("סגירה: נשמר \(short(paymentID))")
                await activity.end(nil, dismissalPolicy: .immediate)
                return
            }
            QuickLogStorage.log("נשמר ב\(state.chosen?.name ?? "") \(short(paymentID))")
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .after(.now.addingTimeInterval(savedLingers)))
            return
        }
    }

    /// When the app comes to the foreground: logs what each card's state is (to tell whether iOS
    /// or the user dismissed one), and ends cards whose payment got a category (on Home, say) or
    /// is gone.
    static func endResolved() async {
        let inbox = QuickLogStorage.loadInbox()
        for activity in Activity<QuickLogActivityAttributes>.activities {
            let id = activity.attributes.paymentID
            guard activity.activityState == .active else {
                QuickLogStorage.log("בפתיחה: כרטיס \(short(id)) במצב \(activity.activityState)")
                continue
            }
            let payment = inbox.payment(id)
            if payment == nil || payment?.categoryID != nil {
                QuickLogStorage.log("סגירה: \(short(id)) \(payment == nil ? "כבר נשמר" : "סווג באפליקציה")")
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func state(for paymentID: UUID) -> QuickLogActivityAttributes.ContentState? {
        guard case let .payment(payment) = QuickLogService.card(for: paymentID.uuidString).state else { return nil }
        func choice(_ choice: QuickLogCardModel.Choice) -> QuickLogActivityAttributes.Choice {
            .init(id: choice.id, emoji: choice.emoji, name: choice.name, color: choice.color)
        }
        return .init(
            merchant: payment.merchant,
            amount: payment.amount,
            mainAmount: payment.mainAmount,
            card: payment.card,
            conversion: payment.conversion,
            choices: payment.choices.map(choice),
            chosen: payment.chosen.map(choice),
            suggested: payment.suggested.map(choice),
            hasNote: payment.hasNote
        )
    }

    private static func alert(for state: QuickLogActivityAttributes.ContentState) -> AlertConfiguration {
        AlertConfiguration(
            title: "\(state.merchant)",
            body: state.suggested.map { "\(state.amount) · \($0.name)?" } ?? "\(state.amount) · לאיזו קטגוריה?",
            sound: .default
        )
    }

    private static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "pending-capture"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
