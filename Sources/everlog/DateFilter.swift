import ArgumentParser
import Foundation

/// Shared `--from / --to / --year` flags. Compose into commands via `@OptionGroup`.
///
/// Accepts `YYYY-MM-DD` or full ISO 8601. `--year YYYY` is shorthand for
/// `--from YYYY-01-01 --to YYYY-12-31T23:59:59Z`.
struct DateFilter: ParsableArguments {
    @Option(name: .long, help: "Only include entries on or after this date (YYYY-MM-DD or ISO 8601).")
    var from: String?

    @Option(name: .long, help: "Only include entries on or before this date.")
    var to: String?

    @Option(name: .long, help: "Shorthand for --from YYYY-01-01 --to YYYY-12-31.")
    var year: Int?

    /// Returns Cocoa-epoch seconds (matching `ZDATE`) for the lower and upper bounds.
    /// nil means unbounded on that side.
    func cocoaRange() throws -> (Double?, Double?) {
        if year != nil && (from != nil || to != nil) {
            throw ValidationError("--year is mutually exclusive with --from / --to.")
        }
        if let y = year {
            let lower = try parseDate("\(String(format: "%04d", y))-01-01")
            let upper = try parseDate("\(String(format: "%04d", y))-12-31T23:59:59Z")
            return (lower, upper)
        }
        let lower = try from.map { try parseDate($0) }
        let upper = try to.map { try parseDate($0, endOfDayIfBare: true) }
        return (lower, upper)
    }

    private func parseDate(_ s: String, endOfDayIfBare: Bool = false) throws -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        // Bare YYYY-MM-DD
        if trimmed.count == 10, trimmed.contains("-") {
            let suffix = endOfDayIfBare ? "T23:59:59Z" : "T00:00:00Z"
            return try iso8601(trimmed + suffix)
        }
        return try iso8601(trimmed)
    }

    private func iso8601(_ s: String) throws -> Double {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) {
            return d.timeIntervalSinceReferenceDate
        }
        // Try with fractional seconds
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) {
            return d.timeIntervalSinceReferenceDate
        }
        throw ValidationError("Could not parse date '\(s)'. Use YYYY-MM-DD or ISO 8601.")
    }
}
