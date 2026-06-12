@preconcurrency import GRDB
import Foundation

public struct DatabasePlan: Equatable, Sendable {
    public var usesWAL: Bool
    public var usesForeignKeys: Bool
    public var usesMigrations: Bool
    public var usesFTS5: Bool

    public init(
        usesWAL: Bool = true,
        usesForeignKeys: Bool = true,
        usesMigrations: Bool = true,
        usesFTS5: Bool = true
    ) {
        self.usesWAL = usesWAL
        self.usesForeignKeys = usesForeignKeys
        self.usesMigrations = usesMigrations
        self.usesFTS5 = usesFTS5
    }
}

/// GRDB is linked in Phase 0; migrations and DatabasePool are implemented in Phase 2.
public enum DatabaseBootstrap {
    public static let linkedAdapterName = "GRDB"

    public static func phase0Plan() -> DatabasePlan {
        DatabasePlan()
    }

    public static func makePool(at path: String) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let pool = try DatabasePool(path: path, configuration: configuration)
        try pool.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        try migrator.migrate(pool)
        return pool
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_schema") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_groups (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at REAL NOT NULL,
                    source_app_name TEXT,
                    source_bundle_identifier TEXT,
                    item_count INTEGER NOT NULL,
                    metadata_json TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    group_id TEXT REFERENCES clipboard_groups(id) ON DELETE SET NULL,
                    title TEXT NOT NULL,
                    detected_kind TEXT NOT NULL,
                    source_app_name TEXT,
                    source_bundle_identifier TEXT,
                    content_hash TEXT NOT NULL UNIQUE,
                    searchable_text TEXT NOT NULL,
                    preview_text TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    last_used_at REAL,
                    copy_count INTEGER NOT NULL,
                    use_count INTEGER NOT NULL,
                    is_pinned INTEGER NOT NULL,
                    is_sensitive INTEGER NOT NULL,
                    expires_at REAL,
                    byte_count INTEGER NOT NULL,
                    metadata_json TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_representations (
                    id TEXT PRIMARY KEY NOT NULL,
                    entry_id TEXT NOT NULL REFERENCES clipboard_entries(id) ON DELETE CASCADE,
                    pasteboard_type TEXT NOT NULL,
                    uniform_type_identifier TEXT,
                    storage_kind TEXT NOT NULL,
                    inline_data BLOB,
                    external_file_path TEXT,
                    byte_count INTEGER NOT NULL,
                    text_encoding TEXT,
                    priority INTEGER NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS tags (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL UNIQUE,
                    created_at REAL NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS entry_tags (
                    entry_id TEXT NOT NULL REFERENCES clipboard_entries(id) ON DELETE CASCADE,
                    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY (entry_id, tag_id)
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS collections (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS collection_entries (
                    collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
                    entry_id TEXT NOT NULL REFERENCES clipboard_entries(id) ON DELETE CASCADE,
                    sort_order INTEGER NOT NULL,
                    PRIMARY KEY (collection_id, entry_id)
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS transform_pipelines (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS transform_steps (
                    id TEXT PRIMARY KEY NOT NULL,
                    pipeline_id TEXT NOT NULL REFERENCES transform_pipelines(id) ON DELETE CASCADE,
                    action_id TEXT NOT NULL,
                    step_order INTEGER NOT NULL,
                    options_json TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS transform_executions (
                    id TEXT PRIMARY KEY NOT NULL,
                    pipeline_id TEXT REFERENCES transform_pipelines(id) ON DELETE SET NULL,
                    entry_id TEXT REFERENCES clipboard_entries(id) ON DELETE SET NULL,
                    status TEXT NOT NULL,
                    started_at REAL NOT NULL,
                    finished_at REAL,
                    error_message TEXT
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_stacks (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    entry_ids_json TEXT NOT NULL,
                    current_index INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS settings_metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value_json TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(
                    entry_id UNINDEXED,
                    title,
                    searchable_text,
                    preview_text,
                    detected_kind,
                    source_app_name,
                    tokenize = 'trigram'
                );
                """)

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_entries_created_at ON clipboard_entries(created_at);")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_entries_updated_at ON clipboard_entries(updated_at);")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_entries_group_id ON clipboard_entries(group_id);")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_representations_entry_id ON clipboard_representations(entry_id);")
        }

        migrator.registerMigration("v2_create_phase7_schema") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS snippets (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    tags_json TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_snippets_updated_at ON snippets(updated_at);")
        }

        return migrator
    }
}
