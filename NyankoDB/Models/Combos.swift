import Foundation

struct ComboChoice: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
}
struct ComboMember: Codable, Hashable, Identifiable {
    let unitID: Int
    let minimumForm: Int
    var id: Int { unitID }
    func entry(in repository: CatalogRepository) -> Entry? {
        guard (1...4).contains(minimumForm) else { return nil }
        return repository.entry("\(unitID)-\(["f", "c", "s", "u"][minimumForm - 1])")
    }
}
struct NyanCombo: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let effectID: Int
    let tierID: Int
    let effectValue: Int
    let amount: String
    let note: String
    let unlock: String
    let scope: String
    let members: [ComboMember]
    var slots: Int { members.count }
}
struct ComboCatalog: Codable {
    let version: Int
    let catalogVersion: String
    let region: String
    let effects: [ComboChoice]
    let tiers: [ComboChoice]
    let combos: [NyanCombo]
    static let empty = ComboCatalog(version: 1, catalogVersion: "", region: "ja", effects: [], tiers: [], combos: [])
}
struct ComboCharacter: Identifiable, Equatable {
    let unitID: Int
    var form: Int? = nil
    var id: Int { unitID }
}
enum ComboSort: String, CaseIterable, Identifiable {
    case slots = "枠数が少ない順", id = "図鑑順", name = "名前順"
    var id: String { rawValue }
}
struct ComboFilter: Equatable {
    var effects: Set<Int> = []
    var tiers: Set<Int> = []
    var slots: Set<Int> = []
    var characters: [ComboCharacter] = []
    var allCharacters = true
    var count: Int { effects.count + tiers.count + slots.count + characters.count }
    func matches(_ combo: NyanCombo) -> Bool {
        guard effects.isEmpty || effects.contains(combo.effectID),
              tiers.isEmpty || tiers.contains(combo.tierID),
              slots.isEmpty || slots.contains(combo.slots) else { return false }
        let contains: (ComboCharacter) -> Bool = { selected in
            combo.members.contains { $0.unitID == selected.unitID && (selected.form == nil || selected.form! >= $0.minimumForm) }
        }
        return characters.isEmpty || (allCharacters ? characters.allSatisfy(contains) : characters.contains(where: contains))
    }
}
struct ComboRepository {
    let catalog: ComboCatalog
    private let names: [Int: SearchName]
    let loadError: String?
    init(catalog: ComboCatalog, characters: Catalog, searchNames: [String: SearchName] = [:]) {
        let units = Dictionary(characters.units.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let valid = catalog.version == 1 && catalog.region == "ja" && catalog.catalogVersion == characters.version &&
            Set(catalog.combos.map(\.id)).count == catalog.combos.count &&
            Set(catalog.effects.map(\.id)).count == catalog.effects.count &&
            Set(catalog.tiers.map(\.id)).count == catalog.tiers.count && catalog.combos.allSatisfy { combo in
                !combo.name.isEmpty && (1...5).contains(combo.slots) &&
                Set(combo.members.map(\.unitID)).count == combo.slots &&
                catalog.effects.contains(where: { $0.id == combo.effectID }) && catalog.tiers.contains(where: { $0.id == combo.tierID }) &&
                combo.members.allSatisfy { member in units[member.unitID]?.forms.contains(where: { $0.number == member.minimumForm }) == true }
            }
        self.catalog = valid ? catalog : .empty
        loadError = valid ? nil : "コンボデータとキャラデータの組み合わせを確認できません。"
        names = Dictionary((valid ? catalog.combos : []).map { combo in
            let record = searchNames[combo.name]
            return (combo.id, record?.original == combo.name ? record! : SearchName(original: combo.name))
        }, uniquingKeysWith: { first, _ in first })
    }
    func effect(_ combo: NyanCombo) -> String { catalog.effects.first(where: { $0.id == combo.effectID })?.name ?? "" }
    func tier(_ combo: NyanCombo) -> String { catalog.tiers.first(where: { $0.id == combo.tierID })?.name ?? "" }
    func search(query: String = "", filter: ComboFilter = ComboFilter(), sort: ComboSort = .slots) -> [NyanCombo] {
        let q = SearchQuery(query)
        let ranked: [(NyanCombo, SearchName.MatchRank)] = catalog.combos.compactMap { combo in
            guard filter.matches(combo) else { return nil }
            if let ids = q.ids { return ids.contains(combo.id) ? (combo, .contains) : nil }
            if q.normalized.isEmpty { return (combo, .contains) }
            guard let rank = names[combo.id]?.rank(for: q) else { return nil }
            return (combo, rank)
        }
        return ranked.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            switch sort {
            case .slots: if a.0.slots != b.0.slots { return a.0.slots < b.0.slots }
            case .name: if a.0.name != b.0.name { return a.0.name < b.0.name }
            case .id: break
            }
            return a.0.id < b.0.id
        }.map { $0.0 }
    }
    func involving(_ entry: Entry) -> [NyanCombo] {
        search(filter: ComboFilter(characters: [ComboCharacter(unitID: entry.unit.id, form: entry.form.number)]))
    }
}
