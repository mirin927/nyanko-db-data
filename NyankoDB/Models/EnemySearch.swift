import Foundation

enum DatabaseKind: String, CaseIterable, Identifiable {
    case cats = "ネコ", enemies = "敵"
    var id: String { rawValue }
}

enum EnemySortOrder: String, CaseIterable, Identifiable {
    case id = "ID順", name = "名前順", hp = "HP", attack = "ATK", dps = "DPS", range = "射程"
    case speed = "速度", knockbacks = "KB", frequency = "攻撃頻度", startup = "攻撃発生", money = "お金（基本値）"
    var id: String { rawValue }
    var metric: EnemyMetric? {
        switch self {
        case .hp: .hp; case .attack: .attack; case .dps: .dps; case .range: .range
        case .speed: .speed; case .knockbacks: .knockbacks; case .frequency: .frequency
        case .startup: .startup; case .money: .money; case .id, .name: nil
        }
    }
    var defaultDirection: SortDirection { [.frequency, .startup].contains(self) ? .ascending : .descending }

}

struct EnemySearchFilter {
    var traits: Set<EnemyTrait> = []
    var abilities: Set<EnemyAbility> = []
    var attacks: Set<AttackType> = []
    var traitMode: MatchMode = .any
    var attackMode: MatchMode = .all
    var effectMode: MatchMode = .all
    var abilityMode: MatchMode = .all
    var immunityMode: MatchMode = .all
    var ranges: [EnemyMetric: NumberRange] = [:]
    var count: Int { traits.count + abilities.count + attacks.count + ranges.values.filter(\.active).count }
    var valid: Bool { ranges.values.allSatisfy(\.valid) }
    func mode(for category: FeatureCategory) -> MatchMode {
        switch category { case .effect: effectMode; case .ability: abilityMode; default: immunityMode }
    }
    mutating func setMode(_ mode: MatchMode, for category: FeatureCategory) {
        switch category { case .effect: effectMode = mode; case .ability: abilityMode = mode; default: immunityMode = mode }
    }
    func resultMetrics(configured: [EnemyMetric]) -> [EnemyMetric] {
        configured + EnemyMetric.allCases.filter { !configured.contains($0) && ranges[$0]?.active == true }
    }
    private func match<T: Hashable>(_ wanted: Set<T>, in available: [T], mode: MatchMode) -> Bool {
        wanted.isEmpty || (mode == .all ? wanted.isSubset(of: Set(available)) : !wanted.isDisjoint(with: available))
    }
    func matches(_ enemy: Enemy, magnification: EnemyMagnification) -> Bool {
        guard valid else { return false }
        if !traits.isEmpty && !match(traits, in: enemy.traits, mode: traitMode) { return false }
        if !attacks.isEmpty && !match(attacks, in: enemy.attackTypes, mode: attackMode) { return false }
        if !abilities.isEmpty {
            let available = enemy.abilities
            guard EnemyAbility.categories.allSatisfy({ category in
                match(Set(abilities.filter { $0.category == category }), in: available, mode: mode(for: category))
            }) else { return false }
        }
        let active = ranges.filter { $0.value.active }
        guard !active.isEmpty else { return true }
        let stats = enemy.stats(at: magnification)
        return active.allSatisfy { $0.value.contains($0.key.value(stats)) }
    }
}

struct EnemyRepository {
    let catalog: EnemyCatalog
    private let byID: [Int: Enemy]
    private let nameIndex: [Int: SearchName]
    init(catalog: EnemyCatalog, searchNames: [String: SearchName] = [:]) {
        self.catalog = catalog
        byID = Dictionary(catalog.enemies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        nameIndex = Dictionary(catalog.enemies.map { enemy in
            let supplied = searchNames[enemy.name]
            return (enemy.id, supplied?.original == enemy.name ? supplied! : SearchName(original: enemy.name))
        }, uniquingKeysWith: { a, _ in a })
    }
    func enemy(_ id: Int) -> Enemy? { byID[id] }
    func search(query: String, filter: EnemySearchFilter = EnemySearchFilter(),
                sort: EnemySortOrder = .id, direction: SortDirection? = nil, magnification: EnemyMagnification = .base) -> [Enemy] {
        let query = SearchQuery(query)
        var ranks: [Int: SearchName.MatchRank] = [:]
        let results = catalog.enemies.filter { enemy in
            if let ids = query.ids {
                guard ids.contains(enemy.id) else { return false }
            } else if !query.normalized.isEmpty {
                guard let rank = nameIndex[enemy.id]?.rank(for: query) else { return false }
                ranks[enemy.id] = rank
            }
            return filter.matches(enemy, magnification: magnification)
        }
        let values = sort.metric.map { metric in Dictionary(results.map { ($0.id, metric.value($0.stats(at: magnification))) }, uniquingKeysWith: { a, _ in a }) } ?? [:]
        let direction = direction ?? sort.defaultDirection
        return results.sorted { a, b in
            if sort == .id, let ra = ranks[a.id], let rb = ranks[b.id], ra != rb { return ra < rb }
            if sort == .name, a.name != b.name { return a.name < b.name }
            if sort.metric != nil, values[a.id] != values[b.id] { return direction.precedes(values[a.id, default: 0], values[b.id, default: 0]) }
            return a.id < b.id
        }
    }
}
