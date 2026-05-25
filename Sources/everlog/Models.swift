import Foundation

struct Journal: Codable {
    let name: String
    let count: Int
}

struct Tag: Codable {
    let name: String
    let count: Int
}

struct StatsResult: Codable {
    let totalEntries: Int
    let totalWords: Int
    let daysWritten: Int
    let currentStreak: Int
    let longestStreak: Int
    let longestStreakStart: String?  // YYYY-MM-DD, nil if no entries
    let longestStreakEnd: String?
    let firstEntryDate: String?      // YYYY-MM-DD
    let lastEntryDate: String?
    let filter: StatsFilter
}

struct StatsFilter: Codable {
    let journal: String?
    let tag: String?
    let from: String?
    let to: String?
}

struct Entry: Codable {
    struct Location: Codable {
        let lat: Double
        let lng: Double
    }

    let identifier: String
    let date: String  // ISO 8601
    let journal: String
    let wordcount: Int
    let preview: String?
    let text: String?
    let tags: [String]
    let location: Location?
    let bookmarked: Bool
}
