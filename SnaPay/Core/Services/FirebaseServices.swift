import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import SnaPayCore

/// Auth, account and household data on Firebase's free plan: Auth for email and password, and
/// Firestore for the data, with `firebase/firestore.rules` enforcing who reads and writes what.
///
/// The free plan has no server functions, so what the database used to do (creating the
/// personal household on sign-up, moving entries between households, deleting an account) runs
/// here, in steps the rules allow one by one.
///
/// Documents are the models' JSON (`FirestoreJSON`). Every method runs off the main actor
/// (`@concurrent`), where the SDK's non-Sendable types stay; only Sendable models cross back.
nonisolated final class FirebaseServices: @unchecked Sendable {
    /// One instance per process, shared by the app and its quick-log intents. Nil when the build
    /// has no Firebase settings.
    static let shared: FirebaseServices? = {
        guard let settings = AppConfig.firebase else { return nil }
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(googleAppID: settings.appID, gcmSenderID: settings.senderID)
            options.apiKey = settings.apiKey
            options.projectID = settings.projectID
            options.bundleID = Bundle.main.bundleIdentifier ?? "com.bignono97.snapay"
            FirebaseApp.configure(options: options)
        }
        Auth.auth().languageCode = "he"
        return FirebaseServices()
    }()

    enum Path {
        static let userIDs = "user_ids"
        static let profiles = "profiles"
        static let deviceTokens = "device_tokens"
        static let households = "households"
        static let categories = "categories"
        static let transactions = "transactions"
        static let recurringRules = "recurring_rules"
        static let merchantMap = "merchant_map"
        static let invites = "invites"
    }

    /// Writes per batch. The rules read up to two documents per write; keeping batches small
    /// stays inside the per-request limit on those reads.
    static let batchSize = 9

    var db: Firestore { Firestore.firestore() }
    var auth: Auth { Auth.auth() }

    private init() {}

    // MARK: Session helpers

    func currentUID() throws -> String {
        guard let uid = auth.currentUser?.uid else { throw AuthFailure.unknown }
        return uid
    }

    func profileRef(_ uid: String) -> DocumentReference {
        db.collection(Path.profiles).document(uid)
    }

    func householdRef(_ id: UUID) -> DocumentReference {
        db.collection(Path.households).document(id.uuidString)
    }

    /// The app's user id for a Firebase uid, remembered on the device so a signed-in user opens
    /// the app offline.
    func cachedUserID(uid: String) -> UUID? {
        UserDefaults.standard.string(forKey: "firebase.userID.\(uid)").flatMap(UUID.init(uuidString:))
    }

    func rememberUserID(_ userID: UUID, uid: String) {
        UserDefaults.standard.set(userID.uuidString, forKey: "firebase.userID.\(uid)")
    }

    func readProfile(uid: String) async throws -> Profile? {
        guard let data = try await profileRef(uid).getDocument().data() else { return nil }
        return try FirestoreJSON.decode(Profile.self, from: data)
    }

    func readHousehold(_ id: UUID) async throws -> HouseholdDocument {
        guard let data = try await householdRef(id).getDocument().data() else { throw HouseholdFailure.unknown }
        return try FirestoreJSON.decode(HouseholdDocument.self, from: data)
    }

    /// Creates the user id, a personal household and the profile, in one batch (what the
    /// sign-up trigger used to do).
    func createAccount(uid: String, email: String, fullName: String, mainCurrency: String) async throws -> Profile {
        let userID = UUID()
        let currency = mainCurrency.uppercased()
        let name = String(fullName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let household = HouseholdDocument.personal(uid: uid, userID: userID, fullName: name)
        let profile = Profile(
            id: userID,
            fullName: name,
            mainCurrency: currency.count == 3 && currency.allSatisfy(\.isUppercase) ? currency : "ILS",
            activeHouseholdID: household.id,
            createdAt: .now
        )
        var profileFields = try FirestoreJSON.encode(profile)
        profileFields["email"] = email
        let batch = db.batch()
        batch.setData(["uid": uid], forDocument: db.collection(Path.userIDs).document(userID.uuidString))
        batch.setData(try FirestoreJSON.encode(household), forDocument: householdRef(household.id))
        batch.setData(profileFields, forDocument: profileRef(uid))
        try await batch.commit()
        rememberUserID(userID, uid: uid)
        return profile
    }

    /// The signed-in user's app id, creating the account documents if sign-up was cut short.
    func ensureAccount(for user: User) async throws -> UUID {
        if let profile = try await readProfile(uid: user.uid) {
            rememberUserID(profile.id, uid: user.uid)
            return profile.id
        }
        let profile = try await createAccount(
            uid: user.uid,
            email: user.email ?? "",
            fullName: user.displayName ?? "",
            mainCurrency: UserDefaults.standard.string(forKey: "firebase.pendingCurrency") ?? "ILS"
        )
        return profile.id
    }

    /// Commits writes in small batches.
    func commit(_ writes: [(WriteBatch) -> Void]) async throws {
        var start = 0
        while start < writes.count {
            let batch = db.batch()
            for write in writes[start..<min(start + Self.batchSize, writes.count)] {
                write(batch)
            }
            try await batch.commit()
            start += Self.batchSize
        }
    }

    func documents(_ query: Query) async throws -> [[String: Any]] {
        try await query.getDocuments().documents.map { $0.data() }
    }

    // MARK: Errors

    static let firestoreErrorDomain = "FIRFirestoreErrorDomain"
    static let authErrorDomain = "FIRAuthErrorDomain"

    static func isOffline(_ error: Error) -> Bool {
        if error is URLError { return true }
        let error = error as NSError
        if error.domain == firestoreErrorDomain {
            // gRPC status codes: 14 unavailable, 4 deadline exceeded.
            return error.code == 14 || error.code == 4
        }
        if error.domain == authErrorDomain {
            return error.code == AuthErrorCode.networkError.rawValue
        }
        return false
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == firestoreErrorDomain && error.code == 7
    }

    /// Firebase Auth errors as cases the UI explains.
    static func authFailure(_ error: Error) -> AuthFailure {
        if let failure = error as? AuthFailure { return failure }
        if isOffline(error) { return .network }
        let error = error as NSError
        guard error.domain == authErrorDomain, let code = AuthErrorCode(rawValue: error.code) else { return .unknown }
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound, .invalidEmail, .userMismatch:
            return .invalidCredentials
        case .emailAlreadyInUse:
            return .emailAlreadyRegistered
        case .weakPassword:
            return .weakPassword
        case .tooManyRequests:
            return .rateLimited
        case .networkError:
            return .network
        default:
            return .unknown
        }
    }

    static func householdFailure(_ error: Error) -> HouseholdFailure {
        if let failure = error as? HouseholdFailure { return failure }
        if isOffline(error) { return .network }
        return .unknown
    }
}

// MARK: - AuthServicing

extension FirebaseServices: AuthServicing {
    @concurrent func restoreSession() async -> UUID? {
        guard let user = auth.currentUser else { return nil }
        if let cached = cachedUserID(uid: user.uid) { return cached }
        return try? await ensureAccount(for: user)
    }

    @concurrent func signUp(fullName: String, email: String, password: String, mainCurrency: String) async throws -> SignUpOutcome {
        let email = CredentialsValidator.normalizedEmail(email)
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // Kept until the account documents exist, in case this is cut short.
            UserDefaults.standard.set(mainCurrency, forKey: "firebase.pendingCurrency")
            let result = try await auth.createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try? await change.commitChanges()
            _ = try await createAccount(uid: result.user.uid, email: email, fullName: name, mainCurrency: mainCurrency)
            UserDefaults.standard.removeObject(forKey: "firebase.pendingCurrency")
            // Joining a shared account needs a confirmed address; using the app doesn't.
            try? await result.user.sendEmailVerification()
            return .signedIn
        } catch {
            throw Self.authFailure(error)
        }
    }

    @concurrent func logIn(email: String, password: String) async throws -> UUID {
        do {
            let result = try await auth.signIn(withEmail: CredentialsValidator.normalizedEmail(email), password: password)
            return try await ensureAccount(for: result.user)
        } catch {
            throw Self.authFailure(error)
        }
    }

    @concurrent func sendPasswordReset(email: String) async throws {
        do {
            // Firebase's own page (in Hebrew) sets the new password; the user then logs in.
            try await auth.sendPasswordReset(withEmail: CredentialsValidator.normalizedEmail(email))
        } catch {
            let failure = Self.authFailure(error)
            // Don't reveal whether an address has an account.
            if failure == .invalidCredentials { return }
            throw failure
        }
    }

    /// Firebase's emails finish in the browser, so no link comes back to the app.
    @concurrent func handleRedirect(_ url: URL) async throws -> (AuthRedirect, UUID) {
        throw AuthFailure.unknown
    }

    @concurrent func updatePassword(_ password: String) async throws {
        guard let user = auth.currentUser else { throw AuthFailure.unknown }
        do {
            try await user.updatePassword(to: password)
        } catch {
            throw Self.authFailure(error)
        }
    }

    @concurrent func signOut() async {
        try? auth.signOut()
    }

    var currentEmail: String? { auth.currentUser?.email }
}

// MARK: - AccountRepository

extension FirebaseServices: AccountRepository {
    @concurrent func fetchProfile(userID: UUID) async throws -> Profile {
        do {
            let uid = try currentUID()
            guard var profile = try await readProfile(uid: uid) else { throw AuthFailure.unknown }
            // The owner removed me from a shared household: take my entries to a new one.
            if let householdID = profile.activeHouseholdID, try await wasRemoved(from: householdID, uid: uid) {
                profile.activeHouseholdID = try await moveToPersonalHousehold(profile: profile, uid: uid, from: householdID)
            }
            return profile
        } catch {
            if Self.isOffline(error) { throw AuthFailure.network }
            throw error
        }
    }

    @concurrent func completeOnboarding(userID: UUID, householdID: UUID, categories: [CategoryDraft]) async throws {
        let uid = try currentUID()
        let rows = CategoryRow.onboardingRows(chosen: categories, householdID: householdID)
        let items = rows.map {
            CategoryItem(id: $0.id, householdID: $0.householdID, name: $0.name, emoji: $0.emoji,
                         color: $0.color, kind: $0.kind, sortOrder: $0.sortOrder)
        }
        try await saveCategories(items)
        try await profileRef(uid).updateData(["onboarding_completed": true])
    }

    @concurrent func fetchPendingInvites() async throws -> [PendingInvite] {
        guard let email = auth.currentUser?.email else { return [] }
        let query = db.collection(Path.invites)
            .whereField("email", isEqualTo: email)
            .whereField("status", isEqualTo: HouseholdInviteRow.Status.pending.rawValue)
        return try await documents(query)
            .map { try FirestoreJSON.decode(PendingInvite.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @concurrent func acceptInvite(_ id: UUID) async throws -> UUID {
        do {
            guard let user = auth.currentUser, let email = user.email else { throw HouseholdFailure.unknown }
            let invite = try await myInvite(id, email: email)
            // The rules let only a confirmed address use an invite.
            try await user.reload()
            guard auth.currentUser?.isEmailVerified == true else {
                try? await auth.currentUser?.sendEmailVerification()
                throw HouseholdFailure.emailNotVerified
            }
            _ = try await user.getIDTokenResult(forcingRefresh: true)

            guard let profile = try await readProfile(uid: user.uid) else { throw HouseholdFailure.unknown }
            if profile.activeHouseholdID == invite.householdID { throw HouseholdFailure.alreadyMember }
            let entry = HouseholdDocument.Member(userID: profile.id, fullName: profile.fullName, joinedAt: .now)
            try await householdRef(invite.householdID).updateData([
                "members.\(user.uid)": try FirestoreJSON.encode(entry),
                "is_shared": true,
            ])
            try await db.collection(Path.invites).document(invite.documentID).updateData(["status": "accepted"])
            if let previous = profile.activeHouseholdID {
                try await moveEntries(userID: profile.id, from: previous, to: invite.householdID)
                try await profileRef(user.uid).updateData(["active_household_id": invite.householdID.uuidString])
                try await leave(previous, uid: user.uid)
            } else {
                try await profileRef(user.uid).updateData(["active_household_id": invite.householdID.uuidString])
            }
            return invite.householdID
        } catch {
            throw Self.householdFailure(error)
        }
    }

    @concurrent func declineInvite(_ id: UUID) async throws {
        do {
            guard let email = auth.currentUser?.email else { throw HouseholdFailure.unknown }
            let invite = try await myInvite(id, email: email)
            try await db.collection(Path.invites).document(invite.documentID).updateData(["status": "declined"])
        } catch {
            throw Self.householdFailure(error)
        }
    }

    @concurrent func leaveHousehold() async throws -> UUID {
        do {
            let uid = try currentUID()
            guard let profile = try await readProfile(uid: uid), let current = profile.activeHouseholdID else {
                throw HouseholdFailure.unknown
            }
            return try await moveToPersonalHousehold(profile: profile, uid: uid, from: current)
        } catch {
            throw Self.householdFailure(error)
        }
    }

    @concurrent func registerDeviceToken(_ token: String, environment: String) async throws {
        let uid = try currentUID()
        try await profileRef(uid).collection(Path.deviceTokens).document(token).setData([
            "token": token,
            "environment": environment,
            "updated_at": FirestoreJSON.string(from: .now),
        ])
    }

    @concurrent func unregisterDeviceToken(_ token: String) async throws {
        let uid = try currentUID()
        try await profileRef(uid).collection(Path.deviceTokens).document(token).delete()
    }

    /// Deletes everything the user entered and their account. Firebase asks for a recent
    /// sign-in, so the password is checked first.
    @concurrent func deleteAccount(password: String) async throws {
        guard let user = auth.currentUser, let email = user.email else { throw AuthFailure.unknown }
        do {
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        } catch {
            throw Self.authFailure(error)
        }
        do {
            guard let profile = try await readProfile(uid: user.uid) else { throw AuthFailure.unknown }
            let mine: (String) -> Query = { collection in
                self.db.collection(collection).whereField("user_id", isEqualTo: profile.id.uuidString)
            }
            var deletes: [(WriteBatch) -> Void] = []
            for collection in [Path.transactions, Path.recurringRules] {
                for document in try await mine(collection).getDocuments().documents {
                    deletes.append { batch in _ = batch.deleteDocument(document.reference) }
                }
            }
            for document in try await profileRef(user.uid).collection(Path.deviceTokens).getDocuments().documents {
                deletes.append { batch in _ = batch.deleteDocument(document.reference) }
            }
            try await commit(deletes)
            if let household = profile.activeHouseholdID {
                try await leave(household, uid: user.uid)
            }
            try await profileRef(user.uid).delete()
            try await db.collection(Path.userIDs).document(profile.id.uuidString).delete()
            try await user.delete()
            UserDefaults.standard.removeObject(forKey: "firebase.userID.\(user.uid)")
        } catch {
            throw Self.authFailure(error)
        }
    }

    // MARK: Moving between households

    /// My invite with this id, read through the rules' invitee path.
    func myInvite(_ id: UUID, email: String) async throws -> InviteDocument {
        let query = db.collection(Path.invites)
            .whereField("email", isEqualTo: email)
            .whereField("id", isEqualTo: id.uuidString)
        guard let data = try await documents(query).first else { throw HouseholdFailure.inviteNotFound }
        let invite = try FirestoreJSON.decode(InviteDocument.self, from: data)
        guard invite.status == .pending else { throw HouseholdFailure.inviteNotFound }
        return invite
    }

    /// Whether the owner flagged me as removed (or the household is gone or closed to me).
    func wasRemoved(from householdID: UUID, uid: String) async throws -> Bool {
        do {
            let household = try await readHousehold(householdID)
            return !household.isActiveMember(uid)
        } catch let error where Self.isPermissionDenied(error) {
            return true
        }
    }

    /// Leaves `householdID` for a new personal household, taking my entries along. Returns the
    /// new household's id.
    func moveToPersonalHousehold(profile: Profile, uid: String, from householdID: UUID) async throws -> UUID {
        let household = HouseholdDocument.personal(uid: uid, userID: profile.id, fullName: profile.fullName)
        try await householdRef(household.id).setData(try FirestoreJSON.encode(household))
        try await moveEntries(userID: profile.id, from: householdID, to: household.id)
        try await profileRef(uid).updateData(["active_household_id": household.id.uuidString])
        try await leave(householdID, uid: uid)
        return household.id
    }

    /// Moves my transactions and recurring charges to another household, matching categories
    /// by name and copying the ones it doesn't have.
    func moveEntries(userID: UUID, from source: UUID, to target: UUID) async throws {
        // A member who lost access to the old household's categories moves uncategorized.
        let oldCategories = (try? await fetchCategories(householdID: source)) ?? []
        let newCategories = try await fetchCategories(householdID: target)
        let remap = HouseholdMove.remapCategories(from: oldCategories, into: newCategories, targetHouseholdID: target)
        try await saveCategories(remap.copies)

        func mine<T: Decodable>(_ collection: String, as type: T.Type) async throws -> [T] {
            let query = db.collection(collection)
                .whereField("user_id", isEqualTo: userID.uuidString)
                .whereField("household_id", isEqualTo: source.uuidString)
            return try await documents(query).map { try FirestoreJSON.decode(type, from: $0) }
        }
        let transactions = HouseholdMove.move(try await mine(Path.transactions, as: TransactionRow.self), to: target, mapping: remap.mapping)
        let rules = HouseholdMove.move(try await mine(Path.recurringRules, as: RecurringRuleRow.self), to: target, mapping: remap.mapping)
        try await saveTransactions(transactions)
        for rule in rules {
            try await saveRecurringRule(rule)
        }
    }

    /// Takes me out of a household: hands ownership over if others stay, or deletes it with
    /// its shared data if I was the last one.
    func leave(_ householdID: UUID, uid: String) async throws {
        let household: HouseholdDocument
        do {
            household = try await readHousehold(householdID)
        } catch let error where Self.isPermissionDenied(error) {
            return // Already gone, or I was taken out entirely.
        }
        guard household.members[uid] != nil else { return }
        let remaining = household.activeMembers.filter { $0.uid != uid }
        if remaining.isEmpty, household.ownerUID == uid {
            // The last one in: the household goes, along with entries of removed members who
            // never moved out (their apps find it gone and move their entries on next launch).
            let others = household.members.keys.filter { $0 != uid }
            if !others.isEmpty {
                var update: [AnyHashable: Any] = [:]
                for other in others { update["members.\(other)"] = FieldValue.delete() }
                try await householdRef(householdID).updateData(update)
            }
            try await deleteHousehold(household)
            return
        }
        var update: [AnyHashable: Any] = ["members.\(uid)": FieldValue.delete()]
        if remaining.count < 2 { update["is_shared"] = false }
        if household.ownerUID == uid, let nextOwner = household.ownerAfterLeaving(uid) {
            update["owner_uid"] = nextOwner
        }
        try await householdRef(householdID).updateData(update)
    }

    /// The last member's household: its categories, merchant history and invites, then itself.
    func deleteHousehold(_ household: HouseholdDocument) async throws {
        var deletes: [(WriteBatch) -> Void] = []
        for collection in [Path.categories, Path.merchantMap, Path.invites] {
            let query = db.collection(collection).whereField("household_id", isEqualTo: household.id.uuidString)
            for document in try await query.getDocuments().documents {
                deletes.append { batch in _ = batch.deleteDocument(document.reference) }
            }
        }
        try await commit(deletes)
        try await householdRef(household.id).delete()
    }

    func saveCategories(_ categories: [CategoryItem]) async throws {
        let writes = try categories.map { category -> (WriteBatch) -> Void in
            let fields = try FirestoreJSON.encode(category)
            let reference = db.collection(Path.categories).document(category.id.uuidString)
            return { batch in _ = batch.setData(fields, forDocument: reference) }
        }
        try await commit(writes)
    }
}

// MARK: - DataRepository

extension FirebaseServices: DataRepository {
    @concurrent func fetchCategories(householdID: UUID) async throws -> [CategoryItem] {
        let query = db.collection(Path.categories).whereField("household_id", isEqualTo: householdID.uuidString)
        return try await documents(query)
            .map { try FirestoreJSON.decode(CategoryItem.self, from: $0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @concurrent func fetchMembers(householdID: UUID) async throws -> [HouseholdMember] {
        try await readHousehold(householdID).householdMembers
    }

    @concurrent func fetchTransactions(householdID: UUID, since: Date) async throws -> [TransactionRow] {
        let query = db.collection(Path.transactions)
            .whereField("household_id", isEqualTo: householdID.uuidString)
            .whereField("occurred_at", isGreaterThanOrEqualTo: FirestoreJSON.string(from: since))
            .order(by: "occurred_at", descending: true)
            .limit(to: 5000)
        return try await documents(query).map { try FirestoreJSON.decode(TransactionRow.self, from: $0) }
    }

    @concurrent func fetchTransactions(householdID: UUID, before: Date, limit: Int) async throws -> [TransactionRow] {
        let query = db.collection(Path.transactions)
            .whereField("household_id", isEqualTo: householdID.uuidString)
            .whereField("occurred_at", isLessThan: FirestoreJSON.string(from: before))
            .order(by: "occurred_at", descending: true)
            .limit(to: limit)
        return try await documents(query).map { try FirestoreJSON.decode(TransactionRow.self, from: $0) }
    }

    @concurrent func saveTransactions(_ rows: [TransactionRow]) async throws {
        let writes = try rows.map { row -> (WriteBatch) -> Void in
            let fields = try FirestoreJSON.encode(row)
            let reference = db.collection(Path.transactions).document(row.id.uuidString)
            return { batch in _ = batch.setData(fields, forDocument: reference) }
        }
        try await commit(writes)
    }

    /// Quick-log payments: skips any the household already has (same source and external id),
    /// e.g. uploaded from another session before this one caught up.
    @concurrent func insertIgnoringDuplicates(_ rows: [TransactionRow]) async throws {
        var fresh: [TransactionRow] = []
        for row in rows {
            if let externalID = row.externalID {
                let query = db.collection(Path.transactions)
                    .whereField("household_id", isEqualTo: row.householdID.uuidString)
                    .whereField("source", isEqualTo: row.source.rawValue)
                    .whereField("external_id", isEqualTo: externalID)
                    .limit(to: 1)
                if !(try await query.getDocuments().documents.isEmpty) { continue }
            }
            fresh.append(row)
        }
        try await saveTransactions(fresh)
    }

    @concurrent func deleteTransaction(id: UUID) async throws {
        try await db.collection(Path.transactions).document(id.uuidString).delete()
    }

    @concurrent func saveCategory(_ category: CategoryItem) async throws {
        try await saveCategories([category])
    }

    @concurrent func fetchRecurringRules(userID: UUID) async throws -> [RecurringRuleRow] {
        let query = db.collection(Path.recurringRules)
            .whereField("user_id", isEqualTo: userID.uuidString)
            .whereField("is_active", isEqualTo: true)
        return try await documents(query).map { try FirestoreJSON.decode(RecurringRuleRow.self, from: $0) }
    }

    @concurrent func saveRecurringRule(_ rule: RecurringRuleRow) async throws {
        try await db.collection(Path.recurringRules).document(rule.id.uuidString)
            .setData(try FirestoreJSON.encode(rule))
    }

    @concurrent func fetchExchangeRates() async throws -> ExchangeRates {
        try await ExchangeRatesSource.latest().exchangeRates()
    }

    @concurrent func fetchMerchantMap(householdID: UUID) async throws -> [MerchantCategoryRow] {
        let query = db.collection(Path.merchantMap)
            .whereField("household_id", isEqualTo: householdID.uuidString)
            .limit(to: 3000)
        return try await documents(query).map { try FirestoreJSON.decode(MerchantCategoryRow.self, from: $0) }
    }

    @concurrent func recordMerchantCategory(householdID: UUID, merchant: String, categoryID: UUID) async throws {
        let key = String(CategorySuggester.normalize(merchant).prefix(120))
        guard !key.isEmpty else { return }
        // Merchant names can hold "/", which document ids can't: the key goes in as hex.
        let hexKey = key.utf8.map { String(format: "%02x", $0) }.joined()
        let id = "\(householdID.uuidString)_\(hexKey)_\(categoryID.uuidString)"
        try await db.collection(Path.merchantMap).document(id).setData([
            "household_id": householdID.uuidString,
            "merchant_key": key,
            "category_id": categoryID.uuidString,
            "times_used": FieldValue.increment(Int64(1)),
            "updated_at": FirestoreJSON.string(from: .now),
        ], merge: true)
    }

    @concurrent func updateProfile(userID: UUID, changes: ProfileChanges) async throws {
        guard !changes.isEmpty else { return }
        let uid = try currentUID()
        try await profileRef(uid).updateData(try FirestoreJSON.encode(changes))
        // Partners see my name from the household's member list.
        if let name = changes.fullName, let profile = try await readProfile(uid: uid), let household = profile.activeHouseholdID {
            try? await householdRef(household).updateData(["members.\(uid).full_name": name])
        }
    }

    // MARK: Shared households

    @concurrent func fetchHousehold(id: UUID) async throws -> HouseholdRow {
        try await readHousehold(id).row
    }

    @concurrent func setHouseholdShared(id: UUID, isShared: Bool) async throws {
        try await householdRef(id).updateData(["is_shared": isShared])
    }

    @concurrent func fetchSentInvites(householdID: UUID) async throws -> [HouseholdInviteRow] {
        let query = db.collection(Path.invites)
            .whereField("household_id", isEqualTo: householdID.uuidString)
            .whereField("status", isEqualTo: HouseholdInviteRow.Status.pending.rawValue)
        return try await documents(query)
            .map { try FirestoreJSON.decode(HouseholdInviteRow.self, from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    @concurrent func sendInvite(householdID: UUID, email: String) async throws {
        do {
            let uid = try currentUID()
            let email = CredentialsValidator.normalizedEmail(email)
            let reference = db.collection(Path.invites)
                .document(InviteDocument.documentID(householdID: householdID, email: email))
            if let data = try await reference.getDocument().data(),
               (try? FirestoreJSON.decode(InviteDocument.self, from: data))?.status == .pending {
                throw HouseholdFailure.inviteAlreadyPending
            }
            let household = try await readHousehold(householdID)
            let invite = InviteDocument(
                householdID: householdID,
                email: email,
                invitedBy: uid,
                inviterName: household.members[uid]?.fullName ?? ""
            )
            try await reference.setData(try FirestoreJSON.encode(invite))
        } catch {
            throw Self.householdFailure(error)
        }
    }

    @concurrent func revokeInvite(_ id: UUID) async throws {
        let uid = try currentUID()
        guard let householdID = try await readProfile(uid: uid)?.activeHouseholdID else { return }
        let query = db.collection(Path.invites)
            .whereField("household_id", isEqualTo: householdID.uuidString)
            .whereField("id", isEqualTo: id.uuidString)
        for document in try await query.getDocuments().documents {
            try await document.reference.updateData(["status": HouseholdInviteRow.Status.revoked.rawValue])
        }
    }

    /// The owner flags the member; their app moves their entries out the next time it opens.
    @concurrent func removeMember(_ userID: UUID) async throws {
        do {
            let uid = try currentUID()
            guard let householdID = try await readProfile(uid: uid)?.activeHouseholdID else { throw HouseholdFailure.unknown }
            let household = try await readHousehold(householdID)
            guard household.ownerUID == uid else { throw HouseholdFailure.notOwner }
            guard let memberUID = household.uid(ofUser: userID) else { return }
            var update: [AnyHashable: Any] = ["members.\(memberUID).removed": true]
            if household.activeMembers.count <= 2 { update["is_shared"] = false }
            try await householdRef(householdID).updateData(update)
        } catch {
            throw Self.isPermissionDenied(error) ? HouseholdFailure.notOwner : Self.householdFailure(error)
        }
    }

    /// Partner notifications need a server, which the free plan doesn't have; partners see new
    /// entries when their app refreshes.
    @concurrent func notifyPartners(transactionID: UUID) async throws {}
}
