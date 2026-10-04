import Foundation
import GRDB
import TikTikCore

/// SQLite persistence for recorded intervals (SPEC 4), via GRDB.
///
/// - Finished intervals go into `interval`, one row per local day (split at midnight).
/// - The interval in progress is checkpointed into the single-row `open_interval` table every
///   minute and turned into a real row on the next launch if TikTik didn't close it (crash, force quit).
/// - Times are stored as seconds since 1970 (REAL); `day` is the local day key (yyyymmdd).
public final class TrackerStore: @unchecked Sendable {
    // GRDB's database writers are thread-safe; @unchecked because the protocol existential isn't
    // statically Sendable on every toolchain.
    private let writer: any DatabaseWriter
    /// File path, or nil for an in-memory database (tests, sample mode).
    public let path: String?

    public init(path: String?) throws {
        self.path = path
        if let path {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            writer = try DatabasePool(path: path)
        } else {
            writer = try DatabaseQueue()
        }
        try Self.migrator.migrate(writer)
    }

    /// `~/Library/Application Support/TikTik/tiktik.sqlite`
    public static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TikTik/tiktik.sqlite").path
    }

    // MARK: - Schema

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "app") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bundle_id", .text).notNull().unique()
                t.column("name", .text).notNull()
            }
            try db.create(table: "domain") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }
            try db.create(table: "interval") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start_at", .double).notNull()
                t.column("end_at", .double).notNull()
                t.column("day", .integer).notNull()
                t.column("state", .integer).notNull()
                t.column("app_id", .integer).references("app")
                t.column("domain_id", .integer).references("domain")
            }
            try db.create(index: "interval_day", on: "interval", columns: ["day"])
            try db.create(index: "interval_start", on: "interval", columns: ["start_at"])
            try db.create(index: "interval_app_day", on: "interval", columns: ["app_id", "day"])
            try db.create(table: "open_interval") { t in
                t.column("id", .integer).primaryKey()
                t.column("start_at", .double).notNull()
                t.column("end_at", .double).notNull()
                t.column("state", .integer).notNull()
                t.column("app_id", .integer)
                t.column("domain_id", .integer)
            }
        }
        return migrator
    }

    // MARK: - Writing

    /// Stores finished intervals, splitting any that cross midnight.
    public func append(_ intervals: [TrackedInterval], calendar: Calendar) throws {
        let pieces = intervals.flatMap { DaySplitter.split($0, calendar: calendar) }
        guard !pieces.isEmpty else { return }
        try writer.write { db in
            for piece in pieces {
                try Self.insert(piece, day: DaySplitter.dayKey(piece.start, calendar: calendar), db: db)
            }
        }
    }

    /// Turns Active time inside `range` into Idle (late idle detection, see TrackerEngine).
    public func reclassifyAsIdle(_ range: DateInterval) throws {
        let lower = range.start.timeIntervalSince1970
        let upper = range.end.timeIntervalSince1970
        guard upper > lower else { return }
        try writer.write { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, start_at, end_at, day, app_id, domain_id FROM interval
                WHERE state = ? AND start_at < ? AND end_at > ?
                """, arguments: [ActivityState.active.rawValue, upper, lower])
            for row in rows {
                let id: Int64 = row["id"]
                let start: Double = row["start_at"]
                let end: Double = row["end_at"]
                let day: Int = row["day"]
                let appID: Int64? = row["app_id"]
                let domainID: Int64? = row["domain_id"]
                try db.execute(sql: "DELETE FROM interval WHERE id = ?", arguments: [id])
                if start < lower {
                    try Self.insertRaw(start: start, end: lower, day: day, state: .active, appID: appID, domainID: domainID, db: db)
                }
                try Self.insertRaw(start: max(start, lower), end: min(end, upper), day: day, state: .idle, appID: nil, domainID: nil, db: db)
                if end > upper {
                    try Self.insertRaw(start: upper, end: end, day: day, state: .active, appID: appID, domainID: domainID, db: db)
                }
            }
        }
    }

    /// Saves the interval in progress (or clears it when nil) so a crash loses at most a minute.
    public func checkpoint(_ open: TrackedInterval?) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM open_interval")
            guard let open, open.end > open.start else { return }
            try db.execute(sql: """
                INSERT INTO open_interval (id, start_at, end_at, state, app_id, domain_id) VALUES (1, ?, ?, ?, ?, ?)
                """, arguments: [open.start.timeIntervalSince1970, open.end.timeIntervalSince1970, open.state.rawValue,
                                 try Self.appID(open.app, db: db), try Self.domainID(open.domain, db: db)])
        }
    }

    /// At launch: turns a leftover checkpoint into real rows. Returns what was recovered.
    @discardableResult
    public func recoverOpenInterval(calendar: Calendar) throws -> TrackedInterval? {
        let recovered: TrackedInterval? = try writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT o.start_at, o.end_at, o.state, a.bundle_id, a.name, d.name AS domain_name
                FROM open_interval o
                LEFT JOIN app a ON a.id = o.app_id
                LEFT JOIN domain d ON d.id = o.domain_id
                """).map(Self.interval(from:))
        }
        if let recovered { try append([recovered], calendar: calendar) }
        try checkpoint(nil)
        return recovered
    }

    // MARK: - Reading

    /// Intervals overlapping `window` (not clipped), oldest first. Optionally only some states.
    public func intervals(overlapping window: DateInterval, states: Set<ActivityState>? = nil) throws -> [TrackedInterval] {
        var sql = """
            SELECT i.start_at, i.end_at, i.state, a.bundle_id, a.name, d.name AS domain_name
            FROM interval i
            LEFT JOIN app a ON a.id = i.app_id
            LEFT JOIN domain d ON d.id = i.domain_id
            WHERE i.start_at < ? AND i.end_at > ?
            """
        var arguments: StatementArguments = [window.end.timeIntervalSince1970, window.start.timeIntervalSince1970]
        if let states, states.count < 3 {
            sql += " AND i.state IN (\(states.map { _ in "?" }.joined(separator: ",")))"
            for state in states.sorted(by: { $0.rawValue < $1.rawValue }) { arguments += [state.rawValue] }
        }
        sql += " ORDER BY i.start_at"
        let query = sql
        let args = arguments
        return try writer.read { db in
            try Row.fetchAll(db, sql: query, arguments: args).map(Self.interval(from:))
        }
    }

    /// Seconds per day, state, app and domain for days `from...through` (day keys).
    public func dailyRollup(fromDay: Int, throughDay: Int) throws -> [DailyRow] {
        try writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT i.day, i.state, a.bundle_id, a.name, d.name AS domain_name, SUM(i.end_at - i.start_at) AS seconds
                FROM interval i
                LEFT JOIN app a ON a.id = i.app_id
                LEFT JOIN domain d ON d.id = i.domain_id
                WHERE i.day BETWEEN ? AND ?
                GROUP BY i.day, i.state, i.app_id, i.domain_id
                ORDER BY i.day
                """, arguments: [fromDay, throughDay]).map { row in
                    let bundleID: String? = row["bundle_id"]
                    let name: String? = row["name"]
                    return DailyRow(
                        day: row["day"],
                        state: ActivityState(rawValue: row["state"]) ?? .away,
                        app: bundleID.map { AppIdentity(bundleID: $0, name: name ?? $0) },
                        domain: row["domain_name"],
                        seconds: row["seconds"]
                    )
                }
        }
    }

    /// When the earliest recorded interval started.
    public func earliestStart() throws -> Date? {
        try writer.read { db in
            try Double.fetchOne(db, sql: "SELECT MIN(start_at) FROM interval").map { Date(timeIntervalSince1970: $0) }
        }
    }

    public func hasAnyData() throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM interval) OR EXISTS (SELECT 1 FROM open_interval)") ?? false
        }
    }

    // MARK: - Maintenance

    /// Deletes days before the retention window (SPEC 4: keep 182 days including today). Returns rows deleted.
    @discardableResult
    public func applyRetention(now: Date, keepDays: Int = 182, calendar: Calendar) throws -> Int {
        let today = calendar.startOfDay(for: now)
        guard let firstKept = calendar.date(byAdding: .day, value: -(keepDays - 1), to: today) else { return 0 }
        let cutoff = DaySplitter.dayKey(firstKept, calendar: calendar)
        return try writer.write { db in
            try db.execute(sql: "DELETE FROM interval WHERE day < ?", arguments: [cutoff])
            return db.changesCount
        }
    }

    /// Deletes everything (Settings → Clear all data).
    public func deleteAll() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM interval; DELETE FROM open_interval; DELETE FROM domain; DELETE FROM app;")
        }
        try writer.vacuum()
    }

    /// Size on disk, including the WAL files.
    public func fileSize() -> Int64 {
        guard let path else { return 0 }
        return ["", "-wal", "-shm"].reduce(Int64(0)) { total, suffix in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path + suffix)
            return total + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    // MARK: - Row helpers

    private static func insert(_ interval: TrackedInterval, day: Int, db: Database) throws {
        try insertRaw(start: interval.start.timeIntervalSince1970, end: interval.end.timeIntervalSince1970, day: day,
                      state: interval.state, appID: try appID(interval.app, db: db),
                      domainID: try domainID(interval.domain, db: db), db: db)
    }

    private static func insertRaw(start: Double, end: Double, day: Int, state: ActivityState,
                                  appID: Int64?, domainID: Int64?, db: Database) throws {
        guard end > start else { return }
        try db.execute(sql: """
            INSERT INTO interval (start_at, end_at, day, state, app_id, domain_id) VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [start, end, day, state.rawValue, appID, domainID])
    }

    private static func appID(_ app: AppIdentity?, db: Database) throws -> Int64? {
        guard let app else { return nil }
        if let id = try Int64.fetchOne(db, sql: "SELECT id FROM app WHERE bundle_id = ?", arguments: [app.bundleID]) {
            try db.execute(sql: "UPDATE app SET name = ? WHERE id = ? AND name != ?", arguments: [app.name, id, app.name])
            return id
        }
        try db.execute(sql: "INSERT INTO app (bundle_id, name) VALUES (?, ?)", arguments: [app.bundleID, app.name])
        return db.lastInsertedRowID
    }

    private static func domainID(_ domain: String?, db: Database) throws -> Int64? {
        guard let domain else { return nil }
        if let id = try Int64.fetchOne(db, sql: "SELECT id FROM domain WHERE name = ?", arguments: [domain]) {
            return id
        }
        try db.execute(sql: "INSERT INTO domain (name) VALUES (?)", arguments: [domain])
        return db.lastInsertedRowID
    }

    private static func interval(from row: Row) -> TrackedInterval {
        let bundleID: String? = row["bundle_id"]
        let name: String? = row["name"]
        return TrackedInterval(
            start: Date(timeIntervalSince1970: row["start_at"]),
            end: Date(timeIntervalSince1970: row["end_at"]),
            state: ActivityState(rawValue: row["state"]) ?? .away,
            app: bundleID.map { AppIdentity(bundleID: $0, name: name ?? $0) },
            domain: row["domain_name"]
        )
    }
}

/// One line of the daily rollup.
public struct DailyRow: Equatable, Sendable {
    public let day: Int
    public let state: ActivityState
    public let app: AppIdentity?
    public let domain: String?
    public let seconds: TimeInterval
}
