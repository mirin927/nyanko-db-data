import Foundation

/// Shared by the app and offline index generator. This only normalizes text;
/// Japanese word/reading analysis lives exclusively in the generation script.
struct SearchText {
    private static let ignored = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters).union(.symbols)
    static func normalize(_ text: String) -> String {
        let width = text.precomposedStringWithCompatibilityMapping
        // ICU's reverse kana transform can expand ー into a context-dependent
        // vowel. Map kana scalars directly so names keep their long vowel mark.
        let kana = String(width.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 0x30A1...0x30F6, 0x30FD...0x30FE:
                return String(UnicodeScalar(scalar.value - 0x60)!)
            case 0x30F7: return "わ\u{3099}"
            case 0x30F8: return "ゐ\u{3099}"
            case 0x30F9: return "ゑ\u{3099}"
            case 0x30FA: return "を\u{3099}"
            default: return String(scalar)
            }
        }.joined())
        let folded = kana.lowercased(with: Locale(identifier: "ja_JP")).precomposedStringWithCanonicalMapping
        return String(folded.unicodeScalars.filter { !ignored.contains($0) })
    }
}

struct SearchQuery {
    let original: String
    let normalized: String
    let ids: Set<Int>?
    init(_ text: String) {
        original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let width = original.precomposedStringWithCompatibilityMapping
        let parts = width.split { $0.isWhitespace || $0 == "," || $0 == "、" }
        let numbers = parts.compactMap { Int($0) }
        ids = !parts.isEmpty && numbers.count == parts.count ? Set(numbers) : nil
        normalized = SearchText.normalize(original)
    }
}

struct CustomReading: Codable {
    let reading: String
    var aliases: [String] = []
    private enum CodingKeys: String, CodingKey { case reading, aliases }
    init(reading: String, aliases: [String] = []) { self.reading = reading; self.aliases = aliases }
    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            reading = text; aliases = []
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reading = try container.decode(String.self, forKey: .reading)
            aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        }
    }
}

struct SearchName: Codable, Equatable {
    enum Source: String, Codable { case automatic, custom, nameOnly }
    enum MatchRank: Int, Comparable {
        case originalExact, normalizedExact, namePrefix, readingPrefix, contains
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    let original: String
    let normalizedName: String
    let readings: [String]
    let searchText: String
    let readingSource: Source

    init(original: String, readings: [String] = [], source: Source = .nameOnly) {
        self.original = original
        normalizedName = SearchText.normalize(original)
        self.readings = readings.map(SearchText.normalize).reduce(into: []) {
            if !$1.isEmpty && !$0.contains($1) { $0.append($1) }
        }
        searchText = ([normalizedName] + self.readings).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }.joined(separator: " ")
        readingSource = source
    }

    /// Custom data takes precedence and prevents an incorrect automatic reading
    /// from being included unless it was explicitly supplied as an alias.
    static func generate(original: String, custom: CustomReading?, automatic: () -> String) -> Self {
        if let custom {
            return Self(original: original, readings: [custom.reading] + custom.aliases, source: .custom)
        }
        return Self(original: original, readings: [automatic()], source: .automatic)
    }

    func rank(for query: SearchQuery) -> MatchRank? {
        if original == query.original { return .originalExact }
        if normalizedName == query.normalized { return .normalizedExact }
        if normalizedName.hasPrefix(query.normalized) { return .namePrefix }
        if readings.contains(where: { $0.hasPrefix(query.normalized) }) { return .readingPrefix }
        if searchText.contains(query.normalized) { return .contains }
        return nil
    }
}
