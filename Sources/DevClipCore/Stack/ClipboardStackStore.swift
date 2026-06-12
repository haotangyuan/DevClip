@preconcurrency import GRDB
import Foundation

public struct ClipboardStackPasteCandidate: Equatable, Sendable {
    public var stack: ClipboardStack
    public var entryID: UUID
    public var pasteRequest: PasteRequest

    public init(stack: ClipboardStack, entryID: UUID, pasteRequest: PasteRequest) {
        self.stack = stack
        self.entryID = entryID
        self.pasteRequest = pasteRequest
    }
}

public struct SequentialPasteResult: Equatable, Sendable {
    public var candidate: ClipboardStackPasteCandidate
    public var pasteResult: PasteExecutionResult

    public init(candidate: ClipboardStackPasteCandidate, pasteResult: PasteExecutionResult) {
        self.candidate = candidate
        self.pasteResult = pasteResult
    }
}

public protocol ClipboardStackStore: Sendable {
    func save(_ stack: ClipboardStack) async throws
    func stack(id: UUID) async throws -> ClipboardStack?
    func stacks() async throws -> [ClipboardStack]
    func deleteStack(id: UUID) async throws
}

public actor InMemoryClipboardStackStore: ClipboardStackStore {
    private var stacksByID: [UUID: ClipboardStack] = [:]

    public init() {}

    public func save(_ stack: ClipboardStack) async throws {
        stacksByID[stack.id] = stack
    }

    public func stack(id: UUID) async throws -> ClipboardStack? {
        stacksByID[id]
    }

    public func stacks() async throws -> [ClipboardStack] {
        stacksByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func deleteStack(id: UUID) async throws {
        stacksByID.removeValue(forKey: id)
    }
}

public actor GRDBClipboardStackStore: ClipboardStackStore {
    private let databasePool: DatabasePool

    public init(databasePool: DatabasePool) {
        self.databasePool = databasePool
    }

    public func save(_ stack: ClipboardStack) async throws {
        try await databasePool.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO clipboard_stacks (
                        id, name, entry_ids_json, current_index, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    stack.id.uuidString,
                    stack.name,
                    try Self.encodeEntryIDs(stack.entryIDs),
                    stack.currentIndex,
                    stack.createdAt.timeIntervalSince1970,
                    stack.updatedAt.timeIntervalSince1970
                ]
            )
        }
    }

    public func stack(id: UUID) async throws -> ClipboardStack? {
        try await databasePool.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM clipboard_stacks WHERE id = ?",
                arguments: [id.uuidString]
            ).map(Self.decodeStack)
        }
    }

    public func stacks() async throws -> [ClipboardStack] {
        try await databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM clipboard_stacks ORDER BY updated_at DESC, id ASC"
            ).map(Self.decodeStack)
        }
    }

    public func deleteStack(id: UUID) async throws {
        try await databasePool.write { db in
            try db.execute(
                sql: "DELETE FROM clipboard_stacks WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    private static func decodeStack(_ row: Row) throws -> ClipboardStack {
        ClipboardStack(
            id: try decodeUUID(row["id"]),
            name: row["name"],
            entryIDs: try decodeEntryIDs(row["entry_ids_json"]),
            currentIndex: row["current_index"],
            createdAt: decodeDate(row["created_at"]),
            updatedAt: decodeDate(row["updated_at"])
        )
    }

    private static func encodeEntryIDs(_ ids: [UUID]) throws -> String {
        let data = try JSONEncoder().encode(ids.map(\.uuidString))
        guard let json = String(data: data, encoding: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法编码剪贴板栈。")
        }

        return json
    }

    private static func decodeEntryIDs(_ json: String) throws -> [UUID] {
        guard let data = json.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法读取剪贴板栈。")
        }

        let values = try JSONDecoder().decode([String].self, from: data)
        return try values.map(decodeUUID)
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

public actor ClipboardStackService {
    private let repository: any ClipboardRepository
    private let store: any ClipboardStackStore

    public init(repository: any ClipboardRepository, store: any ClipboardStackStore) {
        self.repository = repository
        self.store = store
    }

    public func createStack(name: String, entryIDs: [UUID]) async throws -> ClipboardStack {
        let uniqueEntryIDs = Array(NSOrderedSet(array: entryIDs).compactMap { $0 as? UUID })
        try await validateEntriesExist(uniqueEntryIDs)

        let stack = ClipboardStack(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名栈" : name,
            entryIDs: uniqueEntryIDs,
            currentIndex: 0
        )
        try await store.save(stack)
        return stack
    }

    public func append(entryID: UUID, to stackID: UUID) async throws -> ClipboardStack {
        guard var stack = try await store.stack(id: stackID) else {
            throw DevClipError.invalidInput(reason: "找不到剪贴板栈。")
        }

        try await validateEntriesExist([entryID])
        guard !stack.entryIDs.contains(entryID) else {
            return stack
        }

        stack.entryIDs.append(entryID)
        stack.updatedAt = Date()
        try await store.save(stack)
        return stack
    }

    public func remove(entryID: UUID, from stackID: UUID) async throws -> ClipboardStack {
        guard var stack = try await store.stack(id: stackID) else {
            throw DevClipError.invalidInput(reason: "找不到剪贴板栈。")
        }

        stack.entryIDs.removeAll { $0 == entryID }
        if stack.entryIDs.isEmpty {
            stack.currentIndex = 0
        } else {
            stack.currentIndex = min(stack.currentIndex, stack.entryIDs.count - 1)
        }
        stack.updatedAt = Date()
        try await store.save(stack)
        return stack
    }

    public func nextPasteRequest(
        stackID: UUID,
        mode: PasteMode = .pasteOriginal,
        targetApplication: PasteTargetApplication? = nil
    ) async throws -> ClipboardStackPasteCandidate {
        guard var stack = try await store.stack(id: stackID) else {
            throw DevClipError.invalidInput(reason: "找不到剪贴板栈。")
        }
        guard !stack.entryIDs.isEmpty else {
            throw DevClipError.invalidInput(reason: "剪贴板栈为空。")
        }

        let safeIndex = min(max(stack.currentIndex, 0), stack.entryIDs.count - 1)
        let entryID = stack.entryIDs[safeIndex]
        guard try await repository.entry(id: entryID) != nil else {
            throw DevClipError.invalidInput(reason: "剪贴板栈包含不存在的记录。")
        }

        stack.currentIndex = (safeIndex + 1) % stack.entryIDs.count
        stack.updatedAt = Date()
        try await store.save(stack)

        return ClipboardStackPasteCandidate(
            stack: stack,
            entryID: entryID,
            pasteRequest: PasteRequest(
                entryID: entryID,
                mode: mode,
                targetApplication: targetApplication
            )
        )
    }

    public func stacks() async throws -> [ClipboardStack] {
        try await store.stacks()
    }

    private func validateEntriesExist(_ entryIDs: [UUID]) async throws {
        for entryID in entryIDs {
            guard try await repository.entry(id: entryID) != nil else {
                throw DevClipError.invalidInput(reason: "剪贴板记录不存在，无法加入栈。")
            }
        }
    }
}

public actor SequentialPasteService {
    private let stackService: ClipboardStackService
    private let pasteEngine: PasteEngine

    public init(stackService: ClipboardStackService, pasteEngine: PasteEngine) {
        self.stackService = stackService
        self.pasteEngine = pasteEngine
    }

    public func pasteNext(
        stackID: UUID,
        mode: PasteMode = .pasteOriginal,
        targetApplication: PasteTargetApplication? = nil
    ) async throws -> SequentialPasteResult {
        let candidate = try await stackService.nextPasteRequest(
            stackID: stackID,
            mode: mode,
            targetApplication: targetApplication
        )
        let pasteResult = try await pasteEngine.perform(candidate.pasteRequest)
        return SequentialPasteResult(candidate: candidate, pasteResult: pasteResult)
    }
}
