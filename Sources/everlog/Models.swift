import Foundation

struct Journal: Codable {
    let name: String
    let count: Int
}

struct Tag: Codable {
    let name: String
    let count: Int
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
