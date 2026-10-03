import ActivityKit
import Foundation
import UserNotifications

/// Starts, updates and ends the quick-log Live Activity (drawn by the widget extension). Runs in
/// the app's process, usually in the background while a Shortcuts automation runs.
enum QuickLogLiveActivity {
    /// An unclassified payment's card goes stale after this; the payment still waits on Home.
    static let staleAfter: TimeInterval = 15 * 60
    /// How long the "נשמר ב…" line stays before the card goes away.
    static let savedLingers: TimeInterval = 4

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
            notify(title: title, body: detail)
        }
    }

    /// Shows the payment's card, replacing any earlier quick-log card. Returns false when Live
    /// Activities are off or the payment is no longer waiting.
    @discardableResult
    static func start(paymentID: UUID, alerting: Bool) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = state(for: paymentID) else { return false }
        for activity in Activity<QuickLogActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(staleAfter))
        guard let activity = try? Activity.request(attributes: QuickLogActivityAttributes(paymentID: paymentID),
                                                   content: content) else { return false }
        if alerting {
            // The alert is what expands the card out of the Dynamic Island and lights the Lock Screen.
            await activity.update(content, alertConfiguration: AlertConfiguration(
                title: "\(state.merchant)",
                body: "\(state.amount) · לאיזו קטגוריה?",
                sound: .default
            ))
        }
        return true
    }

    /// After a category was tapped: the "נשמר ב…" line with undo, then the card goes away.
    static func showSaved(paymentID: UUID) async {
        guard let activity = activity(for: paymentID) else { return }
        guard let state = state(for: paymentID), state.chosen != nil else {
            await activity.end(nil, dismissalPolicy: .immediate)
            return
        }
        await activity.end(ActivityContent(state: state, staleDate: nil),
                           dismissalPolicy: .after(.now.addingTimeInterval(savedLingers)))
    }

    /// When the app opens: ends cards whose payment got a category (on Home, say) or is gone.
    static func endResolved() async {
        let inbox = QuickLogStorage.loadInbox()
        for activity in Activity<QuickLogActivityAttributes>.activities where activity.activityState == .active {
            let payment = inbox.payment(activity.attributes.paymentID)
            if payment == nil || payment?.categoryID != nil {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func activity(for paymentID: UUID) -> Activity<QuickLogActivityAttributes>? {
        Activity<QuickLogActivityAttributes>.activities.first { $0.attributes.paymentID == paymentID }
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
            chosen: payment.chosen.map(choice)
        )
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
