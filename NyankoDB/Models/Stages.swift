import Foundation

struct StageCatalog: Codable {
    let version: String
    let source: String
    let stages: [BattleStage]
    let enemyNames: [String: String]
    static let empty = StageCatalog(version: "未読み込み", source: "", stages: [], enemyNames: [:])
}

struct BattleStage: Codable, Identifiable, Hashable {
    let id: String
    let mapID: Int
    let number: Int
    let name: String
    let mapName: String
    let category: String
    let energy: Int
    let baseXP: Int
    let width: Int
    let castleHP: Int
    let maxEnemies: Int
    let timeLimit: Int
    let bossGuard: Bool
    let baseEnemyID: Int?
    let noContinue: Bool
    let stars: [Double]
    let spawns: [[Double]]
    let limits: [[Int]]
    var enemyIDs: Set<Int> { Set(spawnRows.map(\.enemyID)) }
    var spawnRows: [StageSpawn] { spawns.enumerated().map { StageSpawn(id: $0.offset, data: $0.element) } }
    func starMultiplier(_ star: Int) -> Double { stars.indices.contains(star) ? stars[star] : stars.first ?? 100 }
    func restrictions(star: Int) -> [String] {
        var result: [String] = []
        let rarities = ["基本", "EX", "レア", "激レア", "超激レア", "伝説レア"]
        for row in limits where row.count >= 9 && (row[1] == -1 || row[1] == star) {
            if row[3] > 0 { result.append("出撃可能：" + rarities.enumerated().filter { row[3] & (1 << $0.offset) != 0 }.map(\.element).joined(separator: "・")) }
            if row[4] > 0 { result.append("出撃上限 \(row[4])体") }
            if row[5] > 0 { result.append("編成上限 \(row[5])枠") }
            if row[6] > 0 { result.append("コスト \(row[6].formatted())円以上") }
            if row[7] > 0 { result.append("コスト \(row[7].formatted())円以下") }
            if row[8] > 0 { result.append("指定キャラの出撃制限あり") }
        }
        if noContinue { result.append("コンティニュー不可") }
        if bossGuard { result.append("ボス撃破まで敵城を破壊できない") }
        return result.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}

struct StageSpawn: Identifiable, Hashable {
    let id: Int
    let data: [Double]
    private func value(_ column: Int) -> Double { data.indices.contains(column) ? data[column] : 0 }
    var enemyID: Int { Int(value(0)) - 2 }
    var count: Int { Int(value(1)) }
    var isBoss: Bool { value(8) != 0 }
    var castlePercent: Int { Int(value(5)) }
    var killedCats: Int { Int(value(13)) }
    var isDelayedAfterCastle: Bool { value(12) == 1 }
    var firstSeconds: Double { value(2) * 2 / 30 }
    var minIntervalSeconds: Double { value(3) * 2 / 30 }
    var maxIntervalSeconds: Double { value(4) * 2 / 30 }
    func magnification(starMultiplier: Double) -> EnemyMagnification {
        EnemyMagnification(hp: value(9) * starMultiplier / 100, attack: value(11) * starMultiplier / 100, maximum: 1_000_000_000)
    }
    var timing: String {
        if killedCats > 0 { return "味方\(killedCats)体撃破後" }
        if castlePercent <= 0 { return "敵城として出現" }
        if castlePercent < 100 {
            return "城HP \(castlePercent)%以下" + (isDelayedAfterCastle ? "・\(Self.seconds(firstSeconds))後" : "")
        }
        return "開始\(Self.seconds(firstSeconds))後"
    }
    func timingDescription(in stage: BattleStage) -> String {
        if stage.baseEnemyID == enemyID { return "敵城として出現" }
        if stage.timeLimit > 0 { return "敵城に\(castlePercent.formatted())ダメージ後" }
        return timing
    }
    var interval: String {
        guard count != 1 else { return "" }
        return minIntervalSeconds == maxIntervalSeconds ? Self.seconds(minIntervalSeconds) : "\(Self.seconds(minIntervalSeconds))〜\(Self.seconds(maxIntervalSeconds))"
    }
    static func seconds(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) + "秒" }
}

struct StageEnemyDestination: Hashable {
    let enemy: Enemy
    let hp: Double
    let attack: Double
}

enum StageRoute: Hashable { case all, enemy(Int), map(Int) }

struct StageSearchFilter {
    var category: String? = nil
    var mapID: Int? = nil
    var enemyIDs: Set<Int> = []
    var enemyMode: MatchMode = .all
    var favoritesOnly = false
    var count: Int { (category == nil ? 0 : 1) + (mapID == nil ? 0 : 1) + enemyIDs.count + (favoritesOnly ? 1 : 0) }
}

struct StageRepository {
    let catalog: StageCatalog
    let categories: [String]
    private let byID: [String: BattleStage]
    private let names: [String: SearchName]
    private let reverse: [Int: Set<String>]
    private let normalizedIDs: [String: String]
    init(catalog: StageCatalog, searchNames: [String: SearchName] = [:]) {
        self.catalog = catalog
        categories = catalog.stages.map(\.category).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        byID = Dictionary(catalog.stages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        normalizedIDs = Dictionary(catalog.stages.map { ($0.id, SearchText.normalize($0.id)) }, uniquingKeysWith: { a, _ in a })
        let allNames = Set(catalog.stages.flatMap { [$0.name, $0.mapName] })
        names = Dictionary(allNames.map { ($0, searchNames[$0]?.original == $0 ? searchNames[$0]! : SearchName(original: $0)) }, uniquingKeysWith: { a, _ in a })
        var links: [Int: Set<String>] = [:]
        for stage in catalog.stages { for enemy in stage.enemyIDs { links[enemy, default: []].insert(stage.id) } }
        reverse = links
    }
    func stage(_ id: String) -> BattleStage? { byID[id] }
    func stages(for enemyID: Int) -> [BattleStage] { catalog.stages.filter { reverse[enemyID]?.contains($0.id) == true } }
    func appearanceCount(_ enemyID: Int) -> Int { reverse[enemyID]?.count ?? 0 }
    func search(query: String, filter: StageSearchFilter = StageSearchFilter(), favorites: Set<String> = []) -> [BattleStage] {
        let query = SearchQuery(query)
        var candidates: Set<String>? = nil
        if !filter.enemyIDs.isEmpty {
            let sets = filter.enemyIDs.sorted().map { reverse[$0] ?? [] }
            candidates = sets.dropFirst().reduce(sets[0]) { filter.enemyMode == .all ? $0.intersection($1) : $0.union($1) }
        }
        let nameRanks = query.normalized.isEmpty ? [:] : names.compactMapValues { $0.rank(for: query) }
        var ranks: [String: SearchName.MatchRank] = [:]
        let results = catalog.stages.filter { stage in
            if let candidates, !candidates.contains(stage.id) { return false }
            if let category = filter.category, category != stage.category { return false }
            if let mapID = filter.mapID, mapID != stage.mapID { return false }
            if filter.favoritesOnly && !favorites.contains(stage.id) { return false }
            guard !query.normalized.isEmpty else { return true }
            // Stage IDs are compound strings, not character IDs; numeric words also match names.
            if normalizedIDs[stage.id] == query.normalized { ranks[stage.id] = .originalExact; return true }
            let matches = [nameRanks[stage.name], nameRanks[stage.mapName]].compactMap { $0 }
            guard let rank = matches.min() else { return false }
            ranks[stage.id] = rank
            return true
        }
        guard !query.normalized.isEmpty else { return results }
        return results.sorted { a,b in
            if ranks[a.id] != ranks[b.id] { return ranks[a.id, default: .contains] < ranks[b.id, default: .contains] }
            return a.mapID == b.mapID ? a.number < b.number : a.mapID < b.mapID
        }
    }
}
