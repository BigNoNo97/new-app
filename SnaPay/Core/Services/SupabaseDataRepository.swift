import Foundation
import Supabase
import SnaPayCore

extension SupabaseServices: DataRepository {
    func fetchCategories(householdID: UUID) async throws -> [CategoryItem] {
        try await client
            .from("categories")
            .select()
            .eq("household_id", value: householdID.uuidString)
            .order("sort_order")
            .execute()
            .value
    }

    func fetchMembers(householdID: UUID) async throws -> [HouseholdMember] {
        nonisolated struct Membership: Decodable, Sendable { let user_id: UUID; let role: String }
        let memberships: [Membership] = try await client
            .from("household_members")
            .select("user_id, role")
            .eq("household_id", value: householdID.uuidString)
            .order("joined_at")
            .execute()
            .value
        guard !memberships.isEmpty else { return [] }
        let profiles: [HouseholdMember] = try await client
            .from("profiles")
            .select("id, full_name")
            .in("id", values: memberships.map { $0.user_id.uuidString })
            .execute()
            .value
        let owners = Set(memberships.filter { $0.role == "owner" }.map(\.user_id))
        let order = Dictionary(uniqueKeysWithValues: memberships.enumerated().map { ($1.user_id, $0) })
        return profiles
            .map { HouseholdMember(id: $0.id, fullName: $0.fullName, isOwner: owners.contains($0.id)) }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    func fetchTransactions(householdID: UUID, since: Date) async throws -> [TransactionRow] {
        try await client
            .from("transactions")
            .select()
            .eq("household_id", value: householdID.uuidString)
            .gte("occurred_at", value: ISO8601DateFormatter().string(from: since))
            .order("occurred_at", ascending: false)
            .limit(5000)
            .execute()
            .value
    }

    func fetchTransactions(householdID: UUID, before: Date, limit: Int) async throws -> [TransactionRow] {
        try await client
            .from("transactions")
            .select()
            .eq("household_id", value: householdID.uuidString)
            .lt("occurred_at", value: ISO8601DateFormatter().string(from: before))
            .order("occurred_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func saveTransactions(_ rows: [TransactionRow]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("transactions").upsert(rows).execute()
    }

    func insertIgnoringDuplicates(_ rows: [TransactionRow]) async throws {
        guard !rows.isEmpty else { return }
        try await client
            .from("transactions")
            .upsert(rows, onConflict: "household_id,source,external_id", ignoreDuplicates: true)
            .execute()
    }

    func deleteTransaction(id: UUID) async throws {
        try await client.from("transactions").delete().eq("id", value: id.uuidString).execute()
    }

    func saveCategory(_ category: CategoryItem) async throws {
        try await client.from("categories").upsert(category).execute()
    }

    func fetchRecurringRules(userID: UUID) async throws -> [RecurringRuleRow] {
        try await client
            .from("recurring_rules")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value
    }

    func saveRecurringRule(_ rule: RecurringRuleRow) async throws {
        try await client.from("recurring_rules").upsert(rule).execute()
    }

    func fetchExchangeRates() async throws -> ExchangeRates {
        let response: ExchangeRatesResponse = try await client.functions.invoke(
            "exchange-rates",
            options: FunctionInvokeOptions(method: .get)
        )
        return response.exchangeRates()
    }

    func fetchMerchantMap(householdID: UUID) async throws -> [MerchantCategoryRow] {
        try await client
            .from("merchant_category_map")
            .select("household_id, merchant_key, category_id, times_used")
            .eq("household_id", value: householdID.uuidString)
            .order("updated_at", ascending: false)
            .limit(3000)
            .execute()
            .value
    }

    func recordMerchantCategory(householdID: UUID, merchant: String, categoryID: UUID) async throws {
        let key = String(CategorySuggester.normalize(merchant).prefix(120))
        guard !key.isEmpty else { return }
        try await client
            .rpc("record_merchant_category", params: [
                "p_household_id": householdID.uuidString,
                "p_merchant_key": key,
                "p_category_id": categoryID.uuidString,
            ])
            .execute()
    }

    func updateProfile(userID: UUID, changes: ProfileChanges) async throws {
        guard !changes.isEmpty else { return }
        try await client
            .from("profiles")
            .update(changes)
            .eq("id", value: userID.uuidString)
            .execute()
    }

    // MARK: Shared households

    func fetchHousehold(id: UUID) async throws -> HouseholdRow {
        try await client
            .from("households")
            .select("id, name, is_shared")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func setHouseholdShared(id: UUID, isShared: Bool) async throws {
        try await client
            .from("households")
            .update(["is_shared": isShared])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func fetchSentInvites(householdID: UUID) async throws -> [HouseholdInviteRow] {
        try await client
            .from("household_invites")
            .select("id, household_id, email, status, created_at")
            .eq("household_id", value: householdID.uuidString)
            .eq("status", value: "pending")
            .order("created_at")
            .execute()
            .value
    }

    func sendInvite(householdID: UUID, email: String) async throws {
        nonisolated struct NewInvite: Encodable, Sendable { let household_id: UUID; let email: String }
        do {
            try await client
                .from("household_invites")
                .insert(NewInvite(household_id: householdID, email: CredentialsValidator.normalizedEmail(email)))
                .execute()
        } catch {
            throw Self.householdFailure(error)
        }
    }

    func revokeInvite(_ id: UUID) async throws {
        try await client
            .from("household_invites")
            .update(["status": "revoked"])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func removeMember(_ userID: UUID) async throws {
        do {
            try await client.rpc("remove_household_member", params: ["p_user": userID.uuidString]).execute()
        } catch {
            throw Self.householdFailure(error)
        }
    }

    func notifyPartners(transactionID: UUID) async throws {
        try await client.functions.invoke(
            "notify-partners",
            options: FunctionInvokeOptions(method: .post, body: ["transaction_id": transactionID.uuidString])
        )
    }

    // MARK: AccountRepository (shared households, push, deletion)

    func fetchPendingInvites() async throws -> [PendingInvite] {
        try await client.rpc("my_pending_invites").execute().value
    }

    func acceptInvite(_ id: UUID) async throws -> UUID {
        do {
            return try await client.rpc("accept_household_invite", params: ["p_invite": id.uuidString]).execute().value
        } catch {
            throw Self.householdFailure(error)
        }
    }

    func declineInvite(_ id: UUID) async throws {
        do {
            try await client.rpc("decline_household_invite", params: ["p_invite": id.uuidString]).execute()
        } catch {
            throw Self.householdFailure(error)
        }
    }

    func leaveHousehold() async throws -> UUID {
        do {
            return try await client.rpc("leave_household").execute().value
        } catch {
            throw Self.householdFailure(error)
        }
    }

    func registerDeviceToken(_ token: String, environment: String) async throws {
        try await client
            .from("device_tokens")
            .upsert(["token": token, "environment": environment], onConflict: "token")
            .execute()
    }

    func unregisterDeviceToken(_ token: String) async throws {
        try await client.from("device_tokens").delete().eq("token", value: token).execute()
    }

    func deleteAccount() async throws {
        try await client.functions.invoke("delete-account", options: FunctionInvokeOptions(method: .post))
    }

    /// Maps server errors (SQLSTATE codes and messages from the family migration) to cases the
    /// UI explains.
    static func householdFailure(_ error: Error) -> HouseholdFailure {
        if error is URLError { return .network }
        let text = String(describing: error).lowercased()
        if text.contains("23505") || text.contains("duplicate key") { return .inviteAlreadyPending }
        if text.contains("invite_not_found") { return .inviteNotFound }
        if text.contains("not_owner") { return .notOwner }
        if text.contains("not_a_member") || text.contains("not_shared") { return .unknown }
        return .unknown
    }
}

extension SupabaseServices {
    /// One client per process, shared by the app and its quick-log intents (which can run
    /// with no window open).
    static let shared: SupabaseServices? = {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        return SupabaseServices(url: url, anonKey: key)
    }()
}
