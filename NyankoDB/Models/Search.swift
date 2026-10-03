import Foundation

enum MatchMode: String, CaseIterable { case any = "OR", all = "AND" }
enum FormMode: String, CaseIterable { case latest = "最高形態", all = "全形態", first = "第1", second = "第2", third = "第3", fourth = "第4"
    var number: Int? { switch self { case .first: 1; case .second: 2; case .third: 3; case .fourth: 4; default: nil } }
}
enum SortOrder: String, CaseIterable, Identifiable {
    case id = "ID順", name = "名前順", hp = "HPが高い順", dps = "DPSが高い順", range = "射程が長い順", cost = "コストが低い順"
    var id: String { rawValue }
}
struct NumberRange: Equatable {
    var minimum = ""
    var maximum = ""
    var active: Bool { !minimum.isEmpty || !maximum.isEmpty }
    var valid: Bool {
        let low = Double(minimum), high = Double(maximum)
        if !minimum.isEmpty && (low == nil || !(low!.isFinite) || low! < 0) { return false }
        if !maximum.isEmpty && (high == nil || !(high!.isFinite) || high! < 0) { return false }
        if let low, let high, low > high { return false }
        return true
    }
    func contains(_ number: Double) -> Bool {
        valid && number >= (Double(minimum) ?? -.infinity) && number <= (Double(maximum) ?? .infinity)
    }
}
struct SearchFilter {
    var traits: Set<Trait> = []
    var abilities: Set<Ability> = []
    var rarities: Set<Int> = []
    var attacks: Set<AttackType> = []
    var traitMode: MatchMode = .any
    var abilityMode: MatchMode = .all
    var immunityMode: MatchMode = .all
    var effectMode: MatchMode = .all
    var resistanceMode: MatchMode = .all
    var attackMode: MatchMode = .all
    var formMode: FormMode = .latest
    var talentsOnly = false
    var ranges: [Metric: NumberRange] = [:]
    var count: Int { traits.count + abilities.count + rarities.count + attacks.count + ranges.values.filter(\.active).count + (talentsOnly ? 1 : 0) + (formMode == .latest ? 0 : 1) }
    var valid: Bool { ranges.values.allSatisfy(\.valid) }
    /// Add active numeric constraints to this search's display without changing saved preferences.
    func resultMetrics(configured: [Metric]) -> [Metric] {
        configured + Metric.allCases.filter { !configured.contains($0) && ranges[$0]?.active == true }
    }
    func match<T: Hashable>(_ wanted: Set<T>, in available: [T], mode: MatchMode) -> Bool {
        wanted.isEmpty || (mode == .all ? wanted.isSubset(of: Set(available)) : !wanted.isDisjoint(with: available))
    }
    func matches(_ entry: Entry, level: Int, performance: UnitPerformance? = nil) -> Bool {
        let f = performance?.form ?? entry.form
        guard rarities.isEmpty || rarities.contains(entry.unit.rarity),
              (traits.isEmpty || match(traits, in: f.traits, mode: traitMode)),
              (abilities.isEmpty || FeatureCategory.allCases.allSatisfy({ category in
                  let selected = Set(abilities.filter { $0.category == category })
                  let mode: MatchMode = switch category { case .effect: effectMode; case .immunity: immunityMode; case .resistance: resistanceMode; case .ability: abilityMode }
                  return match(selected, in: f.abilities, mode: mode)
              })),
              (attacks.isEmpty || match(attacks, in: f.attackTypes, mode: attackMode)),
              !talentsOnly || f.talent > 0 || f.superTalent > 0 else { return false }
        let activeRanges = ranges.filter { $0.value.active }
        guard !activeRanges.isEmpty else { return true }
        let stats = performance?.stats ?? entry.unit.stats(for: f, level: level)
        return activeRanges.allSatisfy { $0.value.contains($0.key.value(stats)) }
    }
}
struct CatalogRepository {
    let catalog: Catalog
    let entries: [Entry]
    private let entriesByID: [String: Entry]
    private let nameIndex: [String: SearchName]
    let talentSupport: TalentSupport
    let evolutionSupport: EvolutionSupport
    private let talentIndex: [String: [TalentDefinition]]

    init(catalog: Catalog, searchNames: [String: SearchName] = [:], talentSupport: TalentSupport = .empty, evolutionSupport: EvolutionSupport = .empty) {
        self.catalog = catalog
        self.talentSupport = talentSupport
        self.evolutionSupport = evolutionSupport.version == 1 && evolutionSupport.catalogVersion == catalog.version ? evolutionSupport : .empty
        talentIndex = Dictionary(catalog.units.flatMap { unit in unit.forms.map { form in
            let id = "\(unit.id)-\(form.form)"
            return (id, TalentDefinition.decode(form, entryID: id, support: talentSupport))
        } }, uniquingKeysWith: { a, _ in a })
        entries = catalog.units.flatMap { unit in unit.forms.map { Entry(unit: unit, form: $0) } }
        entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        nameIndex = Dictionary(entries.map { entry in
            let form = entry.form
            let record: SearchName = {
                if let record = searchNames[form.name], record.original == form.name { return record }
                // Older catalogs remain searchable by their written names. Never
                // fall back to Japanese reading analysis during typing.
                return SearchName(original: form.name)
            }()
            return (entry.id, record)
        }, uniquingKeysWith: { first, _ in first })
    }

    func entry(_ id: String) -> Entry? { entriesByID[id] }
    /// The summon column is a unit ID, not the summoner's evolution form.
    /// Spirits use their own first-form data and never inherit the parent's talents.
    func summonedSpirit(for form: UnitForm) -> Entry? {
        guard let id = form.summonedUnitID else { return nil }
        return entry("\(id)-f")
    }
    func talents(for entry: Entry, includingLocked: Bool = false) -> [TalentDefinition] {
        let own = talentIndex[entry.id] ?? []
        if !includingLocked || !own.isEmpty { return own }
        guard let form = entry.unit.forms.first(where: { $0.number >= 3 && !$0.talentData.isEmpty }) else { return [] }
        return talentIndex["\(entry.unit.id)-\(form.form)"] ?? []
    }
    func profile(for entry: Entry, level: Int, mode: TalentMode, saved: [Int: TalentProfile]) -> TalentProfile {
        switch mode {
        case .none: return TalentProfile()
        case .saved: return saved[entry.unit.id] ?? TalentProfile()
        case .max:
            var profile = TalentProfile()
            profile.maximize(talents(for: entry), form: entry.form, level: min(level, entry.unit.maxBase + entry.unit.maxPlus))
            return profile
        }
    }
    func performance(_ entry: Entry, level: Int, mode: TalentMode = .none, saved: [Int: TalentProfile] = [:]) -> UnitPerformance {
        entry.unit.performance(for: entry.form, level: level, talents: talents(for: entry),
            profile: profile(for: entry, level: level, mode: mode, saved: saved), timing: talentSupport.timings[entry.id])
    }
    static func normalized(_ text: String) -> String { SearchText.normalize(text) }

    func search(query: String, filter: SearchFilter, level: Int, sort: SortOrder, talentMode: TalentMode = .none, profiles: [Int: TalentProfile] = [:]) -> [Entry] {
        let q = SearchQuery(query)
        var ranks: [String: SearchName.MatchRank] = [:]
        var performances: [String: UnitPerformance] = [:]
        let result = catalog.units.flatMap { unit -> [Entry] in
            if let ids = q.ids {
                guard ids.contains(unit.id) else { return [] }
            }
            let forms: [UnitForm]
            switch filter.formMode {
            case .latest: forms = [unit.latest]
            case .all: forms = unit.forms
            default: forms = unit.forms.filter { $0.number == filter.formMode.number }
            }
            // Match only the displayed form's own name, reading and custom aliases.
            // A sibling evolution must not make an unrelated form a search result.
            return forms.map { Entry(unit: unit, form: $0) }.filter { entry in
                if q.ids == nil && !q.normalized.isEmpty {
                    guard let rank = nameIndex[entry.id]?.rank(for: q) else { return false }
                    ranks[entry.id] = rank
                }
                if talentMode == .none { return filter.matches(entry, level: level) }
                let adjusted = performance(entry, level: level, mode: talentMode, saved: profiles)
                performances[entry.id] = adjusted
                return filter.matches(entry, level: level, performance: adjusted)
            }
        }
        let metric: Metric? = switch sort {
        case .hp: .hp; case .dps: .dps; case .range: .range; case .cost: .cost
        case .id, .name: nil
        }
        // Compute numeric sort keys once per result, not in every comparison.
        let values: [String: Double] = metric.map { metric in
            Dictionary(result.map { ($0.id, metric.value(performances[$0.id]?.stats ?? $0.unit.stats(for: $0.form, level: level))) },
                       uniquingKeysWith: { first, _ in first })
        } ?? [:]
        return result.sorted { a, b in
            // Relevance improves the default ID order for name searches. Explicit
            // name/stat sorting and numeric ID searches keep their existing behavior.
            if sort == .id, let ra = ranks[a.id], let rb = ranks[b.id], ra != rb { return ra < rb }
            switch sort {
            case .name: if a.form.name != b.form.name { return a.form.name < b.form.name }
            case .hp, .dps, .range:
                if values[a.id] != values[b.id] { return values[a.id, default: 0] > values[b.id, default: 0] }
            case .cost:
                if values[a.id] != values[b.id] { return values[a.id, default: 0] < values[b.id, default: 0] }
            case .id: break
            }
            return a.unit.id == b.unit.id ? a.form.number < b.form.number : a.unit.id < b.unit.id
        }
    }
}
