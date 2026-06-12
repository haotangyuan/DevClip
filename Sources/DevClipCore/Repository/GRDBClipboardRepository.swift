@preconcurrency import GRDB
import Foundation

/// GRDB-backed clipboard repository introduced in Phase 2.
public actor GRDBClipboardRepository: FTSClipboardRepository {
    private let databasePool: DatabasePool
    private let blobStore: (any BlobStore)?

    public init(databasePool: DatabasePool, blobStore: (any BlobStore)? = nil) {
        self.databasePool = databasePool
        self.blobStore = blobStore
    }

    public init(databasePath: String, blobStore: (any BlobStore)? = nil) throws {
        self.databasePool = try DatabaseBootstrap.makePool(at: databasePath)
        self.blobStore = blobStore
    }

    public func save(
        group: ClipboardGroup,
        entries: [ClipboardEntry],
        representations: [ClipboardRepresentation]
    ) async throws {
        try await databasePool.write { db in
            var insertedEntryIDs: Set<UUID> = []

            for entry in entries {
                if let existingID = try Self.existingEntryID(forContentHash: entry.contentHash, db: db) {
                    try Self.mergeDuplicate(entry, into: existingID, db: db)
                } else {
                    if insertedEntryIDs.isEmpty {
                        try Self.insert(group: group, db: db)
                    }

                    try Self.insert(entry: entry, db: db)
                    try Self.replaceFTS(entry: entry, db: db)
                    insertedEntryIDs.insert(entry.id)
                }
            }

            for representation in representations where insertedEntryIDs.contains(representation.entryID) {
                try Self.insert(representation: representation, db: db)
            }
        }
    }

    public func entry(id: UUID) async throws -> ClipboardEntry? {
        try await databasePool.read { db in
            try Self.fetchEntry(id: id, db: db)
        }
    }

    public func entries() async throws -> [ClipboardEntry] {
        try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM clipboard_entries ORDER BY created_at ASC, id ASC"
            ).map(Self.decodeEntry)
        }
    }

    public func representations(entryID: UUID) async throws -> [ClipboardRepresentation] {
        try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM clipboard_representations
                    WHERE entry_id = ?
                    ORDER BY priority ASC, id ASC
                    """,
                arguments: [entryID.uuidString]
            ).map(Self.decodeRepresentation)
        }
    }

    public func groups() async throws -> [ClipboardGroup] {
        try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM clipboard_groups ORDER BY created_at ASC, id ASC"
            ).map(Self.decodeGroup)
        }
    }

    public func deleteEntry(id: UUID) async throws {
        let referencedPaths = try await databasePool.write { db in
            try db.execute(sql: "DELETE FROM clipboard_fts WHERE entry_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM clipboard_entries WHERE id = ?", arguments: [id.uuidString])
            return try Self.referencedExternalPaths(db: db)
        }

        try await blobStore?.deleteOrphanedBlobs(referencedPaths: referencedPaths)
    }

    public func deleteExpiredEntries(now: Date) async throws -> Int {
        let result = try await databasePool.write { db in
            let ids = try String.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM clipboard_entries
                    WHERE expires_at IS NOT NULL AND expires_at <= ?
                    """,
                arguments: [now.timeIntervalSince1970]
            )

            guard !ids.isEmpty else {
                return (0, try Self.referencedExternalPaths(db: db))
            }

            try db.execute(
                sql: "DELETE FROM clipboard_fts WHERE entry_id IN \(Self.sqlPlaceholders(count: ids.count))",
                arguments: StatementArguments(ids)
            )
            try db.execute(
                sql: "DELETE FROM clipboard_entries WHERE id IN \(Self.sqlPlaceholders(count: ids.count))",
                arguments: StatementArguments(ids)
            )

            return (ids.count, try Self.referencedExternalPaths(db: db))
        }

        try await blobStore?.deleteOrphanedBlobs(referencedPaths: result.1)
        return result.0
    }

    public func searchFTS(_ rawQuery: String) async throws -> [ClipboardEntry] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let query = "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
        return try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.*
                    FROM clipboard_fts f
                    JOIN clipboard_entries e ON e.id = f.entry_id
                    WHERE clipboard_fts MATCH ?
                    ORDER BY rank, e.created_at DESC
                    """,
                arguments: [query]
            ).map(Self.decodeEntry)
        }
    }

    public func referencedExternalPaths() async throws -> Set<String> {
        try await databasePool.read { db in
            try Self.referencedExternalPaths(db: db)
        }
    }

    public func setPinned(_ isPinned: Bool, entryID: UUID) async throws {
        try await databasePool.write { db in
            try db.execute(
                sql: """
                    UPDATE clipboard_entries
                    SET is_pinned = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    isPinned ? 1 : 0,
                    Date().timeIntervalSince1970,
                    entryID.uuidString
                ]
            )

            if let entry = try Self.fetchEntry(id: entryID, db: db) {
                try Self.replaceFTS(entry: entry, db: db)
            }
        }
    }

    private static func insert(group: ClipboardGroup, db: Database) throws {
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO clipboard_groups (
                    id, created_at, source_app_name, source_bundle_identifier,
                    item_count, metadata_json
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                group.id.uuidString,
                group.createdAt.timeIntervalSince1970,
                group.sourceAppName,
                group.sourceBundleIdentifier,
                group.itemCount,
                try encodeMetadata(group.metadata)
            ]
        )
    }

    private static func insert(entry: ClipboardEntry, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO clipboard_entries (
                    id, group_id, title, detected_kind, source_app_name,
                    source_bundle_identifier, content_hash, searchable_text,
                    preview_text, created_at, updated_at, last_used_at,
                    copy_count, use_count, is_pinned, is_sensitive, expires_at,
                    byte_count, metadata_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                entry.id.uuidString,
                entry.groupID?.uuidString,
                entry.title,
                entry.detectedKind.rawValue,
                entry.sourceAppName,
                entry.sourceBundleIdentifier,
                entry.contentHash,
                entry.searchableText,
                entry.previewText,
                entry.createdAt.timeIntervalSince1970,
                entry.updatedAt.timeIntervalSince1970,
                entry.lastUsedAt?.timeIntervalSince1970,
                entry.copyCount,
                entry.useCount,
                entry.isPinned ? 1 : 0,
                entry.isSensitive ? 1 : 0,
                entry.expiresAt?.timeIntervalSince1970,
                entry.byteCount,
                try encodeMetadata(entry.metadata)
            ]
        )
    }

    private static func insert(representation: ClipboardRepresentation, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO clipboard_representations (
                    id, entry_id, pasteboard_type, uniform_type_identifier,
                    storage_kind, inline_data, external_file_path, byte_count,
                    text_encoding, priority
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                representation.id.uuidString,
                representation.entryID.uuidString,
                representation.pasteboardType,
                representation.uniformTypeIdentifier,
                representation.storageKind.rawValue,
                representation.inlineData,
                representation.externalFilePath,
                representation.byteCount,
                representation.textEncoding,
                representation.priority
            ]
        )
    }

    private static func replaceFTS(entry: ClipboardEntry, db: Database) throws {
        try db.execute(sql: "DELETE FROM clipboard_fts WHERE entry_id = ?", arguments: [entry.id.uuidString])
        guard entry.metadata.values["shouldIndex"] != "false" else {
            return
        }

        try db.execute(
            sql: """
                INSERT INTO clipboard_fts (
                    entry_id, title, searchable_text, preview_text,
                    detected_kind, source_app_name
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                entry.id.uuidString,
                entry.title,
                entry.searchableText,
                entry.previewText,
                entry.detectedKind.rawValue,
                entry.sourceAppName ?? ""
            ]
        )
    }

    private static func existingEntryID(forContentHash contentHash: String, db: Database) throws -> UUID? {
        guard
            let idString = try String.fetchOne(
                db,
                sql: "SELECT id FROM clipboard_entries WHERE content_hash = ?",
                arguments: [contentHash]
            )
        else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    private static func mergeDuplicate(_ incoming: ClipboardEntry, into existingID: UUID, db: Database) throws {
        guard var existing = try fetchEntry(id: existingID, db: db) else {
            return
        }

        existing.copyCount += incoming.copyCount
        existing.updatedAt = max(existing.updatedAt, incoming.updatedAt)
        existing.sourceAppName = incoming.sourceAppName ?? existing.sourceAppName
        existing.sourceBundleIdentifier = incoming.sourceBundleIdentifier ?? existing.sourceBundleIdentifier
        existing.byteCount = max(existing.byteCount, incoming.byteCount)
        existing.metadata.values["lastDuplicateChangeCount"] = incoming.metadata.values["snapshotChangeCount"]

        try db.execute(
            sql: """
                UPDATE clipboard_entries
                SET updated_at = ?, copy_count = ?, source_app_name = ?,
                    source_bundle_identifier = ?, byte_count = ?, metadata_json = ?
                WHERE id = ?
                """,
            arguments: [
                existing.updatedAt.timeIntervalSince1970,
                existing.copyCount,
                existing.sourceAppName,
                existing.sourceBundleIdentifier,
                existing.byteCount,
                try encodeMetadata(existing.metadata),
                existing.id.uuidString
            ]
        )
        try replaceFTS(entry: existing, db: db)
    }

    private static func fetchEntry(id: UUID, db: Database) throws -> ClipboardEntry? {
        try Row.fetchOne(
            db,
            sql: "SELECT * FROM clipboard_entries WHERE id = ?",
            arguments: [id.uuidString]
        ).map(decodeEntry)
    }

    private static func referencedExternalPaths(db: Database) throws -> Set<String> {
        let paths = try String.fetchAll(
            db,
            sql: """
                SELECT external_file_path
                FROM clipboard_representations
                WHERE external_file_path IS NOT NULL
                """
        )

        return Set(paths)
    }

    private static func sqlPlaceholders(count: Int) -> String {
        "(\(Array(repeating: "?", count: count).joined(separator: ",")))"
    }

    private static func decodeEntry(_ row: Row) throws -> ClipboardEntry {
        let detectedKindRaw: String = row["detected_kind"]
        return ClipboardEntry(
            id: try decodeUUID(row["id"]),
            groupID: try decodeOptionalUUID(row["group_id"]),
            title: row["title"],
            detectedKind: ClipboardContentKind(rawValue: detectedKindRaw) ?? .binary,
            sourceAppName: row["source_app_name"],
            sourceBundleIdentifier: row["source_bundle_identifier"],
            contentHash: row["content_hash"],
            searchableText: row["searchable_text"],
            previewText: row["preview_text"],
            createdAt: decodeDate(row["created_at"]),
            updatedAt: decodeDate(row["updated_at"]),
            lastUsedAt: decodeOptionalDate(row["last_used_at"]),
            copyCount: row["copy_count"],
            useCount: row["use_count"],
            isPinned: (row["is_pinned"] as Int) != 0,
            isSensitive: (row["is_sensitive"] as Int) != 0,
            expiresAt: decodeOptionalDate(row["expires_at"]),
            byteCount: row["byte_count"],
            metadata: try decodeMetadata(row["metadata_json"])
        )
    }

    private static func decodeRepresentation(_ row: Row) throws -> ClipboardRepresentation {
        let storageKindRaw: String = row["storage_kind"]
        return ClipboardRepresentation(
            id: try decodeUUID(row["id"]),
            entryID: try decodeUUID(row["entry_id"]),
            pasteboardType: row["pasteboard_type"],
            uniformTypeIdentifier: row["uniform_type_identifier"],
            storageKind: RepresentationStorageKind(rawValue: storageKindRaw) ?? .inlineData,
            inlineData: row["inline_data"],
            externalFilePath: row["external_file_path"],
            byteCount: row["byte_count"],
            textEncoding: row["text_encoding"],
            priority: row["priority"]
        )
    }

    private static func decodeGroup(_ row: Row) throws -> ClipboardGroup {
        ClipboardGroup(
            id: try decodeUUID(row["id"]),
            createdAt: decodeDate(row["created_at"]),
            sourceAppName: row["source_app_name"],
            sourceBundleIdentifier: row["source_bundle_identifier"],
            itemCount: row["item_count"],
            metadata: try decodeMetadata(row["metadata_json"])
        )
    }

    private static func encodeMetadata(_ metadata: ClipboardMetadata) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法编码元数据。")
        }

        return json
    }

    private static func decodeMetadata(_ json: String) throws -> ClipboardMetadata {
        guard let data = json.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法读取元数据。")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ClipboardMetadata.self, from: data)
    }

    private static func decodeUUID(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw DevClipError.invalidInput(reason: "数据库中存在无效 UUID。")
        }

        return uuid
    }

    private static func decodeOptionalUUID(_ value: String?) throws -> UUID? {
        guard let value else {
            return nil
        }

        return try decodeUUID(value)
    }

    private static func decodeDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private static func decodeOptionalDate(_ value: Double?) -> Date? {
        value.map(Date.init(timeIntervalSince1970:))
    }
}
