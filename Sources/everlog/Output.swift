import Foundation

private extension String {
    func paddedRight(to width: Int) -> String {
        if count >= width { return self }
        return self + String(repeating: " ", count: width - count)
    }
    func paddedLeft(to width: Int) -> String {
        if count >= width { return self }
        return String(repeating: " ", count: width - count) + self
    }
}

// ANSI color codes — kept minimal, no rich-style dep needed.
enum ANSI {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let cyan = "\u{001B}[36m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
}

enum Output {
    static var useColor: Bool {
        // Respect NO_COLOR convention; default to on when stdout is a TTY
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(fileno(stdout)) != 0
    }

    static func emitJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("json encode failed\n".utf8))
            exit(1)
        }
        print(str)
    }

    static func emitJournals(_ rows: [Journal]) {
        let nameWidth = max(14, rows.map { $0.name.count }.max() ?? 14)
        for r in rows {
            let name = r.name.paddedRight(to: nameWidth)
            let count = String(r.count).paddedLeft(to: 5)
            print("  \(name)  \(count)")
        }
    }

    static func emitTags(_ rows: [Tag]) {
        let nameWidth = max(14, rows.map { $0.name.count }.max() ?? 14)
        for r in rows {
            let tag = "#\(r.name)".paddedRight(to: nameWidth + 1)
            let count = String(r.count).paddedLeft(to: 5)
            print("  \(tag)  \(count)")
        }
    }

    static func emitEntries(_ rows: [Entry]) {
        if rows.isEmpty {
            print("(no results)")
            return
        }
        for r in rows { renderEntryRow(r) }
    }

    static func emitEntry(_ entry: Entry?) {
        guard let e = entry else {
            print("(not found)")
            return
        }
        if useColor {
            print("\(ANSI.bold)\(e.date)\(ANSI.reset)  \(ANSI.green)\(e.journal)\(ANSI.reset)")
        } else {
            print("=== \(e.date) — \(e.journal) ===")
        }
        let tagStr = e.tags.isEmpty ? "(none)" : e.tags.joined(separator: ", ")
        print("Identifier: \(e.identifier)")
        print("Tags:       \(tagStr)")
        print("Wordcount:  \(e.wordcount)")
        if let loc = e.location {
            let lat = String(format: "%.4f", loc.lat)
            let lng = String(format: "%.4f", loc.lng)
            print("Location:   \(lat), \(lng)")
        }
        if e.bookmarked {
            print("Bookmarked: yes")
        }
        print("")
        print(e.text ?? "(empty)")
    }

    // MARK: - private

    private static func renderEntryRow(_ r: Entry) {
        let datePart = String(r.date.prefix(10))
        let idShort = String(r.identifier.prefix(8))
        let wc = r.wordcount > 0 ? " · \(r.wordcount)w" : ""
        if useColor {
            print("")
            print("  \(ANSI.cyan)\(datePart)\(ANSI.reset)  \(ANSI.green)\(r.journal)\(ANSI.reset)\(wc)  \(ANSI.dim)(\(idShort))\(ANSI.reset)")
        } else {
            print("")
            print("  \(datePart) · \(r.journal)\(wc)  (\(idShort))")
        }
        if let p = r.preview {
            let oneLine = p.replacingOccurrences(of: "\n", with: " ")
            let trimmed = oneLine.count > 160 ? String(oneLine.prefix(160)) + "…" : oneLine
            print("  \(trimmed)")
        }
    }
}
