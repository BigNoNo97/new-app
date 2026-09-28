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
        nonisolated struct Membership: Decodable, Sendable { let user_id: UUID }
        let memberships: [Membership] = try await client
            .from("household_members")
            .select("user_id")
            .eq("household_id", value: householdID.uuidString)
            .execute()
            .value
        guard !memberships.isEmpty else { return [] }
        return try await client
            .from("profiles")
            .select("id, full_name")
            .in("id", values: memberships.map { $0.user_id.uuidString })
            .execute()
            .value
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
}
