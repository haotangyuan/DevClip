import Foundation

public struct SensitiveEphemeralRecord: Equatable, Sendable {
    public var entry: ClipboardEntry
    public var representations: [ClipboardRepresentation]
    public var expiresAt: Date

    public init(
        entry: ClipboardEntry,
        representations: [ClipboardRepresentation],
        expiresAt: Date
    ) {
        self.entry = entry
        self.representations = representations
        self.expiresAt = expiresAt
    }
}

/// In-memory retention for secret entries that must not be persisted.
public actor SensitiveEphemeralStore {
    private var recordsByEntryID: [UUID: SensitiveEphemeralRecord] = [:]

    public init() {}

    public func store(
        entries: [ClipboardEntry],
        representations: [ClipboardRepresentation],
        defaultLifetime: TimeInterval = 60
    ) {
        let representationsByEntryID = Dictionary(grouping: representations, by: \.entryID)
        let now = Date()

        for entry in entries {
            let expiry = entry.expiresAt ?? now.addingTimeInterval(defaultLifetime)
            recordsByEntryID[entry.id] = SensitiveEphemeralRecord(
                entry: entry,
                representations: representationsByEntryID[entry.id] ?? [],
                expiresAt: expiry
            )
        }
    }

    @discardableResult
    public func purgeExpired(now: Date = Date()) -> Int {
        let expiredIDs = recordsByEntryID
            .filter { $0.value.expiresAt <= now }
            .map(\.key)

        for id in expiredIDs {
            recordsByEntryID.removeValue(forKey: id)
        }

        return expiredIDs.count
    }

    public func records(now: Date = Date()) -> [SensitiveEphemeralRecord] {
        recordsByEntryID.values
            .filter { $0.expiresAt > now }
            .sorted { $0.entry.createdAt < $1.entry.createdAt }
    }
}
