import Foundation
import Testing
@testable import SnaPayCore

struct HouseholdTests {
    @Test func olderCachedProfilesGetNotificationDefaults() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-00000000000a","full_name":"דנה","main_currency":"ILS",
         "month_start_day":1,"card_fx_fee_percent":0,"quick_log_enabled":true,"onboarding_completed":true}
        """
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile.notifyPartnerActivity)
        #expect(profile.notifyPendingCapture)
        #expect(!profile.notifyTips)
    }

    @Test func profileRoundTripsWithPreferences() throws {
        var profile = Profile(id: UUID(), fullName: "Avi")
        profile.notifyTips = true
        profile.notifyBudget = false
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }

    @Test func appliesOnlyTheChangedFields() {
        var profile = Profile(id: UUID(), fullName: "Avi", monthStartDay: 1, cardFxFeePercent: 2)
        profile.apply(ProfileChanges(monthStartDay: 10, notifyPartnerActivity: false))
        #expect(profile.monthStartDay == 10)
        #expect(profile.cardFxFeePercent == 2)
        #expect(!profile.notifyPartnerActivity)
        #expect(profile.fullName == "Avi")
    }

    @Test func encodesOnlyTheSetFields() throws {
        let data = try JSONEncoder().encode(ProfileChanges(cardFxFeePercent: Decimal(string: "2.5")!, notifyTips: true))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(Set(object.keys) == ["card_fx_fee_percent", "notify_tips"])
        #expect(ProfileChanges().isEmpty)
    }

    @Test func validatesChanges() {
        #expect(ProfileChanges(monthStartDay: 31).isValid)
        #expect(!ProfileChanges(monthStartDay: 0).isValid)
        #expect(!ProfileChanges(cardFxFeePercent: 21).isValid)
        #expect(!ProfileChanges(fullName: "  ").isValid)
        #expect(!ProfileChanges(fullName: String(repeating: "א", count: 81)).isValid)
    }

    @Test func decodesInvitesAndHouseholds() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pending = try decoder.decode([PendingInvite].self, from: Data("""
        [{"id":"80000000-0000-0000-0000-000000000001","household_id":"90000000-0000-0000-0000-000000000001",
          "inviter_name":"מיכל כהן","created_at":"2026-10-01T10:00:00Z"}]
        """.utf8))
        #expect(pending.first?.inviterFirstName == "מיכל")

        let sent = try decoder.decode(HouseholdInviteRow.self, from: Data("""
        {"id":"80000000-0000-0000-0000-000000000002","household_id":"90000000-0000-0000-0000-000000000001",
         "email":"dana@example.com","status":"pending","invited_by":null,"created_at":"2026-10-01T10:00:00Z","responded_at":null}
        """.utf8))
        #expect(sent.status == .pending)

        let household = try decoder.decode(HouseholdRow.self, from: Data("""
        {"id":"90000000-0000-0000-0000-000000000001","name":"","is_shared":true,"created_by":null}
        """.utf8))
        #expect(household.isShared)
    }

    @Test func membersDecodeFromProfilesWithoutRole() throws {
        let member = try JSONDecoder().decode(HouseholdMember.self, from: Data("""
        {"id":"00000000-0000-0000-0000-00000000000a","full_name":"Avi Cohen"}
        """.utf8))
        #expect(member.firstName == "Avi")
        #expect(!member.isOwner)
    }
}
