import Foundation

/// `households/{id}` in Firestore. Membership lives in the document itself, keyed by the
/// Firebase Auth uid, so the security rules can check it with one read.
public struct HouseholdDocument: Codable, Equatable, Sendable {
    public struct Member: Codable, Equatable, Sendable {
        /// The app's user id (`profiles.id`), which transactions carry as `user_id`.
        public var userID: UUID
        public var fullName: String
        public var joinedAt: Date
        /// Set by the owner. The removed member's app moves their data out on next launch,
        /// then deletes the entry.
        public var removed: Bool?

        public init(userID: UUID, fullName: String, joinedAt: Date, removed: Bool? = nil) {
            self.userID = userID
            self.fullName = fullName
            self.joinedAt = joinedAt
            self.removed = removed
        }

        public var isRemoved: Bool { removed == true }

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case fullName = "full_name"
            case joinedAt = "joined_at"
            case removed
        }
    }

    public var id: UUID
    public var name: String
    public var isShared: Bool
    /// Firebase Auth uid of the owner.
    public var ownerUID: String
    /// Keyed by Firebase Auth uid.
    public var members: [String: Member]

    public init(id: UUID, name: String, isShared: Bool, ownerUID: String, members: [String: Member]) {
        self.id = id
        self.name = name
        self.isShared = isShared
        self.ownerUID = ownerUID
        self.members = members
    }

    /// A new personal household with `uid` as its only member and owner.
    public static func personal(id: UUID = UUID(), uid: String, userID: UUID, fullName: String, now: Date = .now) -> HouseholdDocument {
        HouseholdDocument(
            id: id,
            name: fullName,
            isShared: false,
            ownerUID: uid,
            members: [uid: Member(userID: userID, fullName: fullName, joinedAt: now)]
        )
    }

    public var row: HouseholdRow { HouseholdRow(id: id, name: name, isShared: isShared) }

    /// Current members (removed ones excluded), longest-standing first.
    public var activeMembers: [(uid: String, member: Member)] {
        members
            .filter { !$0.value.isRemoved }
            .sorted { ($0.value.joinedAt, $0.key) < ($1.value.joinedAt, $1.key) }
            .map { (uid: $0.key, member: $0.value) }
    }

    public var householdMembers: [HouseholdMember] {
        activeMembers.map {
            HouseholdMember(id: $0.member.userID, fullName: $0.member.fullName, isOwner: $0.uid == ownerUID)
        }
    }

    public func isActiveMember(_ uid: String) -> Bool {
        members[uid].map { !$0.isRemoved } ?? false
    }

    public func uid(ofUser userID: UUID) -> String? {
        members.first { $0.value.userID == userID }?.key
    }

    /// Who owns the household once `uid` leaves: the same owner, or else the longest-standing
    /// remaining member. Nil when nobody is left.
    public func ownerAfterLeaving(_ uid: String) -> String? {
        let remaining = activeMembers.filter { $0.uid != uid }
        if ownerUID != uid, remaining.contains(where: { $0.uid == ownerUID }) { return ownerUID }
        return remaining.first?.uid
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case isShared = "is_shared"
        case ownerUID = "owner_uid"
        case members
    }
}

/// `invites/{householdID}_{email}`. The id is derived from the household and the address, so
/// the security rules can check "this user has a pending invite" when they join.
public struct InviteDocument: Codable, Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var email: String
    public var status: HouseholdInviteRow.Status
    public var createdAt: Date
    /// Firebase Auth uid of whoever sent it.
    public var invitedBy: String
    public var inviterName: String

    public init(
        id: UUID = UUID(),
        householdID: UUID,
        email: String,
        status: HouseholdInviteRow.Status = .pending,
        createdAt: Date = .now,
        invitedBy: String,
        inviterName: String
    ) {
        self.id = id
        self.householdID = householdID
        self.email = email
        self.status = status
        self.createdAt = createdAt
        self.invitedBy = invitedBy
        self.inviterName = inviterName
    }

    public static func documentID(householdID: UUID, email: String) -> String {
        "\(householdID.uuidString)_\(email)"
    }

    public var documentID: String { Self.documentID(householdID: householdID, email: email) }

    public var row: HouseholdInviteRow {
        HouseholdInviteRow(id: id, householdID: householdID, email: email, status: status, createdAt: createdAt)
    }

    public var pending: PendingInvite {
        PendingInvite(id: id, householdID: householdID, inviterName: inviterName, createdAt: createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case email, status
        case createdAt = "created_at"
        case invitedBy = "invited_by"
        case inviterName = "inviter_name"
    }
}

/// Moving a member's data from one household to another (joining, leaving, being removed).
public enum HouseholdMove {
    /// For each category in the old household, the matching category in the new one (same name
    /// and kind), plus copies to create for those with no match. Trips keep their dates.
    public static func remapCategories(
        from source: [CategoryItem],
        into target: [CategoryItem],
        targetHouseholdID: UUID
    ) -> (mapping: [UUID: UUID], copies: [CategoryItem]) {
        var mapping: [UUID: UUID] = [:]
        var copies: [CategoryItem] = []
        var existing = target
        var nextOrder = (target.map(\.sortOrder).max() ?? -1) + 1
        for category in source.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = existing.first(where: {
                $0.kind == category.kind && $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == name
            }) {
                mapping[category.id] = match.id
                continue
            }
            var copy = category
            copy.id = UUID()
            copy.householdID = targetHouseholdID
            copy.sortOrder = nextOrder
            nextOrder += 1
            copies.append(copy)
            existing.append(copy)
            mapping[category.id] = copy.id
        }
        return (mapping, copies)
    }

    /// The rows moved to `householdID`, with their categories remapped.
    public static func move(_ rows: [TransactionRow], to householdID: UUID, mapping: [UUID: UUID]) -> [TransactionRow] {
        rows.map { row in
            var moved = row
            moved.householdID = householdID
            moved.categoryID = row.categoryID.flatMap { mapping[$0] }
            return moved
        }
    }

    public static func move(_ rules: [RecurringRuleRow], to householdID: UUID, mapping: [UUID: UUID]) -> [RecurringRuleRow] {
        rules.map { rule in
            var moved = rule
            moved.householdID = householdID
            moved.categoryID = rule.categoryID.flatMap { mapping[$0] }
            return moved
        }
    }
}
