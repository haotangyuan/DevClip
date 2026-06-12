@preconcurrency import GRDB
import Foundation

public struct ClipboardSnippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var kind: ClipboardContentKind
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        kind: ClipboardContentKind = .plainText,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.kind = kind
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public protocol SnippetStore: Sendable {
    func save(_ snippet: ClipboardSnippet) async throws
    func snippet(id: UUID) async throws -> ClipboardSnippet?
    func snippets() async throws -> [ClipboardSnippet]
    func deleteSnippet(id: UUID) async throws
}

public actor InMemorySnippetStore: SnippetStore {
    private var snippetsByID: [UUID: ClipboardSnippet] = [:]

    public init() {}

    public func save(_ snippet: ClipboardSnippet) async throws {
        snippetsByID[snippet.id] = snippet
    }

    public func snippet(id: UUID) async throws -> ClipboardSnippet? {
        snippetsByID[id]
    }

    public func snippets() async throws -> [ClipboardSnippet] {
        snippetsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func deleteSnippet(id: UUID) async throws {
        snippetsByID.removeValue(forKey: id)
    }
}

public actor GRDBSnippetStore: SnippetStore {
    private let databasePool: DatabasePool

    public init(databasePool: DatabasePool) {
        self.databasePool = databasePool
    }

    public func save(_ snippet: ClipboardSnippet) async throws {
        try await databasePool.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO snippets (
                        id, title, content, kind, tags_json, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    snippet.id.uuidString,
                    snippet.title,
                    snippet.content,
                    snippet.kind.rawValue,
                    try Self.encodeTags(snippet.tags),
                    snippet.createdAt.timeIntervalSince1970,
                    snippet.updatedAt.timeIntervalSince1970
                ]
            )
        }
    }

    public func snippet(id: UUID) async throws -> ClipboardSnippet? {
        try await databasePool.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM snippets WHERE id = ?",
                arguments: [id.uuidString]
            ).map(Self.decodeSnippet)
        }
    }

    public func snippets() async throws -> [ClipboardSnippet] {
        try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM snippets ORDER BY updated_at DESC, id ASC"
            ).map(Self.decodeSnippet)
        }
    }

    public func deleteSnippet(id: UUID) async throws {
        try await databasePool.write { db in
            try db.execute(
                sql: "DELETE FROM snippets WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    private static func decodeSnippet(_ row: Row) throws -> ClipboardSnippet {
        let kindRaw: String = row["kind"]
        return ClipboardSnippet(
            id: try decodeUUID(row["id"]),
            title: row["title"],
            content: row["content"],
            kind: ClipboardContentKind(rawValue: kindRaw) ?? .plainText,
            tags: try decodeTags(row["tags_json"]),
            createdAt: decodeDate(row["created_at"]),
            updatedAt: decodeDate(row["updated_at"])
        )
    }

    private static func encodeTags(_ tags: [String]) throws -> String {
        let data = try JSONEncoder().encode(tags)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法编码片段标签。")
        }

        return json
    }

    private static func decodeTags(_ json: String) throws -> [String] {
        guard let data = json.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法读取片段标签。")
        }

        return try JSONDecoder().decode([String].self, from: data)
    }

    private static func decodeUUID(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw DevClipError.invalidInput(reason: "数据库中存在无效 UUID。")
        }

        return uuid
    }

    private static func decodeDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value)
    }
}

public actor SnippetLibrary {
    private let store: any SnippetStore

    public init(store: any SnippetStore) {
        self.store = store
    }

    public func save(
        title: String,
        content: String,
        kind: ClipboardContentKind = .plainText,
        tags: [String] = []
    ) async throws -> ClipboardSnippet {
        let snippet = ClipboardSnippet(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名片段" : title,
            content: content,
            kind: kind,
            tags: tags
        )
        try await store.save(snippet)
        return snippet
    }

    public func snippets() async throws -> [ClipboardSnippet] {
        try await store.snippets()
    }

    public func deleteSnippet(id: UUID) async throws {
        try await store.deleteSnippet(id: id)
    }

    public func transformInput(for snippetID: UUID) async throws -> TransformInput {
        guard let snippet = try await store.snippet(id: snippetID) else {
            throw DevClipError.invalidInput(reason: "找不到片段。")
        }

        return TransformInput(
            kind: snippet.kind,
            data: Data(snippet.content.utf8),
            text: snippet.content,
            metadata: ClipboardMetadata(values: ["snippetTitle": snippet.title])
        )
    }
}
