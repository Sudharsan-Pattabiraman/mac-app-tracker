import Foundation

/// Minimal test harness: no XCTest needed, so checks run with the Command Line Tools alone.
struct Harness {
    private(set) var passed = 0
    private(set) var failures: [String] = []
    private var current = ""

    mutating func group(_ name: String, _ body: (inout Harness) -> Void) {
        current = name
        body(&self)
    }

    mutating func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                         file: StaticString = #fileID, line: UInt = #line) {
        if condition {
            passed += 1
        } else {
            failures.append("✗ [\(current)] \(message())  (\(file):\(line))")
        }
    }

    mutating func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "",
                                      file: StaticString = #fileID, line: UInt = #line) {
        expect(actual == expected, "\(label.isEmpty ? "" : label + ": ")expected \(expected), got \(actual)",
               file: file, line: line)
    }

    func report() -> Int32 {
        failures.forEach { print($0) }
        print(failures.isEmpty
              ? "✓ All \(passed) checks passed."
              : "\(failures.count) failed, \(passed) passed.")
        return failures.isEmpty ? 0 : 1
    }
}
