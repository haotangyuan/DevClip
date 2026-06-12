@preconcurrency import GRDB
import Foundation

public protocol TransformPipelineStore: Sendable {
    func save(_ pipeline: TransformPipeline) async throws
    func pipeline(id: UUID) async throws -> TransformPipeline?
    func pipelines() async throws -> [TransformPipeline]
    func deletePipeline(id: UUID) async throws
}

public actor InMemoryTransformPipelineStore: TransformPipelineStore {
    private var pipelinesByID: [UUID: TransformPipeline] = [:]

    public init() {}

    public func save(_ pipeline: TransformPipeline) async throws {
        pipelinesByID[pipeline.id] = pipeline
    }

    public func pipeline(id: UUID) async throws -> TransformPipeline? {
        pipelinesByID[id]
    }

    public func pipelines() async throws -> [TransformPipeline] {
        pipelinesByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func deletePipeline(id: UUID) async throws {
        pipelinesByID.removeValue(forKey: id)
    }
}

public actor GRDBTransformPipelineStore: TransformPipelineStore {
    private let databasePool: DatabasePool

    public init(databasePool: DatabasePool) {
        self.databasePool = databasePool
    }

    public func save(_ pipeline: TransformPipeline) async throws {
        try await databasePool.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO transform_pipelines (
                        id, name, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    pipeline.id.uuidString,
                    pipeline.name,
                    pipeline.createdAt.timeIntervalSince1970,
                    pipeline.updatedAt.timeIntervalSince1970
                ]
            )
            try db.execute(
                sql: "DELETE FROM transform_steps WHERE pipeline_id = ?",
                arguments: [pipeline.id.uuidString]
            )

            for step in pipeline.steps.sorted(by: { $0.order < $1.order }) {
                try db.execute(
                    sql: """
                        INSERT INTO transform_steps (
                            id, pipeline_id, action_id, step_order, options_json
                        )
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        step.id.uuidString,
                        pipeline.id.uuidString,
                        step.actionID,
                        step.order,
                        try Self.encodeMetadata(step.options)
                    ]
                )
            }
        }
    }

    public func pipeline(id: UUID) async throws -> TransformPipeline? {
        try await databasePool.read { db in
            try Self.fetchPipeline(id: id, db: db)
        }
    }

    public func pipelines() async throws -> [TransformPipeline] {
        try await databasePool.read { db in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT id FROM transform_pipelines ORDER BY updated_at DESC, id ASC"
            )

            return try ids.compactMap { idString in
                guard let id = UUID(uuidString: idString) else {
                    return nil
                }

                return try Self.fetchPipeline(id: id, db: db)
            }
        }
    }

    public func deletePipeline(id: UUID) async throws {
        try await databasePool.write { db in
            try db.execute(
                sql: "DELETE FROM transform_pipelines WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    private static func fetchPipeline(id: UUID, db: Database) throws -> TransformPipeline? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM transform_pipelines WHERE id = ?",
            arguments: [id.uuidString]
        ) else {
            return nil
        }

        let steps = try Row.fetchAll(
            db,
            sql: """
                SELECT *
                FROM transform_steps
                WHERE pipeline_id = ?
                ORDER BY step_order ASC, id ASC
                """,
            arguments: [id.uuidString]
        ).map(decodeStep)

        return TransformPipeline(
            id: id,
            name: row["name"],
            steps: steps,
            createdAt: decodeDate(row["created_at"]),
            updatedAt: decodeDate(row["updated_at"])
        )
    }

    private static func decodeStep(_ row: Row) throws -> TransformStep {
        TransformStep(
            id: try decodeUUID(row["id"]),
            actionID: row["action_id"],
            order: row["step_order"],
            options: try decodeMetadata(row["options_json"])
        )
    }

    private static func encodeMetadata(_ metadata: ClipboardMetadata) throws -> String {
        let data = try JSONEncoder().encode(metadata)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法编码流水线步骤。")
        }

        return json
    }

    private static func decodeMetadata(_ json: String) throws -> ClipboardMetadata {
        guard let data = json.data(using: .utf8) else {
            throw DevClipError.invalidInput(reason: "无法读取流水线步骤。")
        }

        return try JSONDecoder().decode(ClipboardMetadata.self, from: data)
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

public actor PipelinePreviewService {
    private let repository: any ClipboardRepository
    private let transformEngine: TransformEngine

    public init(repository: any ClipboardRepository, transformEngine: TransformEngine) {
        self.repository = repository
        self.transformEngine = transformEngine
    }

    public func preview(
        pipeline: TransformPipeline,
        entryID: UUID,
        options: TransformOptions = TransformOptions()
    ) async throws -> TransformResult {
        guard let entry = try await repository.entry(id: entryID) else {
            throw DevClipError.invalidInput(reason: "找不到剪贴板记录。")
        }

        let representations = try await repository.representations(entryID: entryID)
        let data = representations
            .sorted { $0.priority < $1.priority }
            .compactMap(\.inlineData)
            .first ?? Data(entry.searchableText.utf8)
        let input = TransformInput(
            kind: entry.detectedKind,
            data: data,
            text: entry.searchableText.isEmpty ? entry.previewText : entry.searchableText,
            metadata: entry.metadata
        )

        return try await transformEngine.execute(
            pipeline: pipeline,
            input: input,
            options: options
        )
    }
}
