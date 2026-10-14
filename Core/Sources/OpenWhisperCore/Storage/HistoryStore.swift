import Foundation
import GRDB

public enum DictationStatus: String, Codable, Sendable {
    case recorded, transcribed, processed, inserted, failed
}

public struct DictationRecord: Codable, Equatable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dictation"

    public var id: String
    public var createdAt: Date
    public var profileID: String
    public var status: DictationStatus
    public var postprocessFailed: Bool
    public var error: String?
    public var rawText: String?
    public var finalText: String?
    /// Имя файла в каталоге аудио (`<uuid>.m4a`); nil после ротации.
    public var audioFileName: String?
    public var durationSec: Double
    public var transcriptionModel: String?
    public var llmModel: String?
    public var costUSD: Double

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case profileID = "profile_id"
        case status
        case postprocessFailed = "postprocess_failed"
        case error
        case rawText = "raw_text"
        case finalText = "final_text"
        case audioFileName = "audio_path"
        case durationSec = "duration_sec"
        case transcriptionModel = "transcription_model"
        case llmModel = "llm_model"
        case costUSD = "cost_usd"
    }

    public init(id: String, createdAt: Date, profileID: String, durationSec: Double, audioFileName: String?) {
        self.id = id
        self.createdAt = createdAt
        self.profileID = profileID
        self.status = .recorded
        self.postprocessFailed = false
        self.error = nil
        self.rawText = nil
        self.finalText = nil
        self.audioFileName = audioFileName
        self.durationSec = durationSec
        self.transcriptionModel = nil
        self.llmModel = nil
        self.costUSD = 0
    }

    public var displayText: String { finalText ?? rawText ?? "" }
}

public final class HistoryStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "OpenWhisper/history.sqlite")
    }

    public static func open(at url: URL) throws -> HistoryStore {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return try HistoryStore(dbQueue: DatabaseQueue(path: url.path))
    }

    public static func inMemory() throws -> HistoryStore {
        try HistoryStore(dbQueue: DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "dictation") { t in
                t.primaryKey("id", .text)
                t.column("created_at", .datetime).notNull().indexed()
                t.column("profile_id", .text).notNull()
                t.column("status", .text).notNull()
                t.column("postprocess_failed", .boolean).notNull().defaults(to: false)
                t.column("error", .text)
                t.column("raw_text", .text)
                t.column("final_text", .text)
                t.column("audio_path", .text)
                t.column("duration_sec", .double).notNull()
                t.column("transcription_model", .text)
                t.column("llm_model", .text)
                t.column("cost_usd", .double).notNull().defaults(to: 0)
            }
            try db.create(virtualTable: "dictation_fts", using: FTS5()) { t in
                t.synchronize(withTable: "dictation")
                t.tokenizer = .unicode61()
                t.column("raw_text")
                t.column("final_text")
            }
        }
        return migrator
    }

    public func insert(_ record: DictationRecord) throws {
        try dbQueue.write { try record.insert($0) }
    }

    public func update(_ record: DictationRecord) throws {
        try dbQueue.write { try record.update($0) }
    }

    public func record(id: String) throws -> DictationRecord? {
        try dbQueue.read { try DictationRecord.fetchOne($0, key: id) }
    }

    public func delete(id: String) throws {
        _ = try dbQueue.write { try DictationRecord.deleteOne($0, key: id) }
    }

    public func recent(limit: Int = 500) throws -> [DictationRecord] {
        try dbQueue.read { db in
            try DictationRecord.order(Column("created_at").desc).limit(limit).fetchAll(db)
        }
    }

    /// Пустой или «бессловесный» запрос (только пробелы, кавычки, знаки) возвращает recent().
    public func search(_ query: String, limit: Int = 500) throws -> [DictationRecord] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return try recent(limit: limit)
        }
        return try dbQueue.read { db in
            try DictationRecord.fetchAll(db, sql: """
                SELECT dictation.* FROM dictation
                JOIN dictation_fts ON dictation_fts.rowid = dictation.rowid
                WHERE dictation_fts MATCH ?
                ORDER BY dictation.created_at DESC
                LIMIT ?
                """, arguments: [pattern, limit])
        }
    }

    public func totalCost(since date: Date) throws -> Double {
        try dbQueue.read { db in
            try Double.fetchOne(
                db, sql: "SELECT COALESCE(SUM(cost_usd), 0) FROM dictation WHERE created_at >= ?",
                arguments: [date]
            ) ?? 0
        }
    }

    public func allIDs() throws -> Set<String> {
        Set(try dbQueue.read { try String.fetchAll($0, sql: "SELECT id FROM dictation") })
    }

    public func clearAudio(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        _ = try dbQueue.write { db in
            try DictationRecord.filter(keys: ids).updateAll(db, Column("audio_path").set(to: nil))
        }
    }
}
