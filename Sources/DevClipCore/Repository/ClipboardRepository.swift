import Foundation

public protocol ClipboardRepository: Sendable {
    func save(
        group: ClipboardGroup,
        entries: [ClipboardEntry],
        representations: [ClipboardRepresentation]
    ) async throws

    func entry(id: UUID) async throws -> ClipboardEntry?
    func entries() async throws -> [ClipboardEntry]
    func representations(entryID: UUID) async throws -> [ClipboardRepresentation]
    func groups() async throws -> [ClipboardGroup]
    func setPinned(_ isPinned: Bool, entryID: UUID) async throws
    func deleteEntry(id: UUID) async throws
    func deleteExpiredEntries(now: Date) async throws -> Int
}

/// Optional repository capability for SQLite FTS-backed full-text search.
public protocol FTSClipboardRepository: ClipboardRepository {
    func searchFTS(_ rawQuery: String) async throws -> [ClipboardEntry]
}

/// Actor-backed in-memory repository used by Phase 1 before GRDB persistence.
public actor InMemoryClipboardRepository: ClipboardRepository {
    private var groupsByID: [UUID: ClipboardGroup] = [:]
    private var entriesByID: [UUID: ClipboardEntry] = [:]
    private var representationsByEntryID: [UUID: [ClipboardRepresentation]] = [:]
    private var entryIDByContentHash: [String: UUID] = [:]

    public init() {}

    public func save(
        group: ClipboardGroup,
        entries: [ClipboardEntry],
        representations: [ClipboardRepresentation]
    ) async throws {
        var didInsertEntry = false

        for entry in entries {
            if let existingID = entryIDByContentHash[entry.contentHash] {
                mergeDuplicate(entry, into: existingID)
                continue
            }

            didInsertEntry = true
            entriesByID[entry.id] = entry
            entryIDByContentHash[entry.contentHash] = entry.id
            representationsByEntryID[entry.id] = representations
                .filter { $0.entryID == entry.id }
                .sorted { $0.priority < $1.priority }
        }

        if didInsertEntry {
            groupsByID[group.id] = group
        }
    }

    public func entry(id: UUID) async throws -> ClipboardEntry? {
        entriesByID[id]
    }

    public func entries() async throws -> [ClipboardEntry] {
        entriesByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.createdAt < rhs.createdAt
        }
    }

    public func representations(entryID: UUID) async throws -> [ClipboardRepresentation] {
        representationsByEntryID[entryID] ?? []
    }

    public func groups() async throws -> [ClipboardGroup] {
        groupsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.createdAt < rhs.createdAt
        }
    }

    public func setPinned(_ isPinned: Bool, entryID: UUID) async throws {
        guard var entry = entriesByID[entryID] else {
            return
        }

        entry.isPinned = isPinned
        entry.updatedAt = Date()
        entriesByID[entryID] = entry
    }

    public func deleteEntry(id: UUID) async throws {
        guard let entry = entriesByID.removeValue(forKey: id) else {
            return
        }

        entryIDByContentHash.removeValue(forKey: entry.contentHash)
        representationsByEntryID.removeValue(forKey: id)
    }

    public func deleteExpiredEntries(now: Date) async throws -> Int {
        let expiredIDs = entriesByID.values
            .filter { entry in
                guard let expiresAt = entry.expiresAt else {
                    return false
                }

                return expiresAt <= now
            }
            .map(\.id)

        for id in expiredIDs {
            try await deleteEntry(id: id)
        }

        return expiredIDs.count
    }

    private func mergeDuplicate(_ incoming: ClipboardEntry, into existingID: UUID) {
        guard var existing = entriesByID[existingID] else {
            return
        }

        existing.copyCount += incoming.copyCount
        existing.updatedAt = max(existing.updatedAt, incoming.updatedAt)
        existing.sourceAppName = incoming.sourceAppName ?? existing.sourceAppName
        existing.sourceBundleIdentifier = incoming.sourceBundleIdentifier ?? existing.sourceBundleIdentifier
        existing.byteCount = max(existing.byteCount, incoming.byteCount)
        existing.metadata.values["lastDuplicateChangeCount"] = incoming.metadata.values["snapshotChangeCount"]
        entriesByID[existingID] = existing
    }
}
