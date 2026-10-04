import Darwin
import Foundation

/// Low-level process queries (libproc). All functions are safe to call from any thread.
enum ProcessTree {
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// `responsibility_get_pid_responsible_for_pid` maps helper/XPC processes to the app that
    /// launched them (e.g. Chrome renderers → Chrome, WebKit processes → Safari). It's a stable
    /// libSystem symbol but not in public headers, so it's looked up at runtime.
    private static let responsibleFunction: ResponsibleFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let function = responsibleFunction else { return pid }
        let responsible = function(pid)
        return responsible > 0 ? responsible : pid
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    /// Physical memory footprint (what Activity Monitor shows as "Memory"), or nil if not permitted.
    static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// The app (from `apps`, keyed by pid) that owns `pid`: itself, its responsible process,
    /// or the nearest ancestor that is an app.
    static func owner<Value>(of pid: pid_t, in apps: [pid_t: Value]) -> Value? {
        if let value = apps[pid] { return value }
        if let value = apps[responsiblePID(for: pid)] { return value }
        var current = pid
        for _ in 0..<8 {
            guard let parent = parentPID(of: current), parent > 1 else { return nil }
            if let value = apps[parent] { return value }
            current = parent
        }
        return nil
    }
}
