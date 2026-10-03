import Foundation
import CoreFoundation

/// Run through generate_search_index.sh on macOS. No tokenizer is shipped in the app.
@main struct GenerateSearchIndex {
    private struct Names: Decodable {
        struct Unit: Decodable {
            struct Form: Decodable { let name: String }
            let forms: [Form]
        }
        let units: [Unit]
    }
    private struct ComboNames: Decodable {
        struct Combo: Decodable { let name: String }
        let combos: [Combo]
    }
    private struct EnemyNames: Decodable {
        struct Enemy: Decodable { let name: String }
        let enemies: [Enemy]
    }
    private struct StageNames: Decodable {
        struct Stage: Decodable { let name: String; let mapName: String }
        let stages: [Stage]
    }
    private static let han = try! NSRegularExpression(pattern: "\\p{Han}")
    private static func hasKanji(_ text: String) -> Bool {
        han.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func reading(_ name: String) -> String {
        // Preserve kana, Latin letters and digits, including long vowel marks.
        // Only dictionary-provided readings of tokens containing kanji are converted.
        let width = name.precomposedStringWithCompatibilityMapping
        let source = width as NSString
        guard let tokenizer = CFStringTokenizerCreate(nil, width as CFString,
            CFRange(location: 0, length: source.length),
            kCFStringTokenizerUnitWordBoundary | kCFStringTokenizerAttributeLatinTranscription,
            NSLocale(localeIdentifier: "ja_JP") as CFLocale) else { return name }
        var result = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = source.substring(with: NSRange(location: range.location, length: range.length))
            if hasKanji(token),
               let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
               let kana = latin.applyingTransform(.latinToHiragana, reverse: false) {
                result += kana
            } else {
                result += token
            }
        }
        return result.isEmpty ? name : result
    }

    static func main() {
        do { try generate() }
        catch {
            FileHandle.standardError.write(Data("Search index error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func generate() throws {
        guard (2...3).contains(CommandLine.arguments.count),
              CommandLine.arguments.count == 2 || ["--combos", "--enemies", "--stages"].contains(CommandLine.arguments[2]) else {
            throw NSError(domain: "SearchIndex", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pass the NyankoDB project directory."])
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let resources = root.appendingPathComponent("NyankoDB/Resources")
        let mode = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : ""
        let combos = mode == "--combos"
        let enemies = mode == "--enemies"
        let stages = mode == "--stages"
        let customFile = stages ? "custom-stage-readings.json" : enemies ? "custom-enemy-readings.json" : combos ? "custom-combo-readings.json" : "custom-readings.json"
        let indexFile = stages ? "stage-search-index.json" : enemies ? "enemy-search-index.json" : combos ? "combo-search-index.json" : "search-index.json"
        let unique: Set<String>
        if stages {
            let records = try JSONDecoder().decode(StageNames.self, from: Data(contentsOf: resources.appendingPathComponent("stage-catalog.json")))
            unique = Set(records.stages.flatMap { [$0.name, $0.mapName] })
        } else if enemies {
            let names = try JSONDecoder().decode(EnemyNames.self, from: Data(contentsOf: resources.appendingPathComponent("enemy-catalog.json")))
            unique = Set(names.enemies.map(\.name))
        } else if combos {
            let names = try JSONDecoder().decode(ComboNames.self, from: Data(contentsOf: resources.appendingPathComponent("combo-catalog.json")))
            unique = Set(names.combos.map(\.name))
        } else {
            let names = try JSONDecoder().decode(Names.self, from: Data(contentsOf: resources.appendingPathComponent("catalog.json")))
            unique = Set(names.units.flatMap { $0.forms.map(\.name) })
        }
        let custom = try JSONDecoder().decode([String: CustomReading].self,
            from: Data(contentsOf: resources.appendingPathComponent(customFile)))
        let unknown = Set(custom.keys).subtracting(unique)
        let empty = custom.filter { SearchText.normalize($0.value.reading).isEmpty }.keys.sorted()
        guard unknown.isEmpty, empty.isEmpty else {
            throw NSError(domain: "SearchIndex", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown names: \(unknown.sorted()); empty readings: \(empty)"])
        }
        var index: [String: SearchName] = [:]
        for name in unique.sorted() {
            index[name] = SearchName.generate(original: name, custom: custom[name], automatic: { reading(name) })
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: resources.appendingPathComponent(indexFile), options: .atomic)
        let unresolved = index.values.filter { $0.readingSource == .automatic && $0.readings.contains(where: hasKanji) }.sorted { $0.original < $1.original }
        print("Generated \(index.count) names, \(custom.count) custom readings, \(unresolved.count) readings with unresolved kanji.")
        for record in unresolved {
            print("Review: \(record.original) => \(record.readings.joined(separator: ", "))")
        }
        print("Automatic readings may still misread proper names. Review \(indexFile) and add corrections to \(customFile).")
    }
}
