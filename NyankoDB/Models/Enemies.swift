import Foundation

/// The enemy catalog has a different CSV schema and ID namespace from allied units.
struct EnemyCatalog: Codable {
    let version: String
    let source: String
    let enemies: [Enemy]
    static let empty = Self(version: "未読み込み", source: "https://jarjarblink.github.io/JDB/tunit_search.html?cc=ja", enemies: [])
}

struct EnemyMagnification: Equatable {
    let hp: Double
    let attack: Double
    init(hp: Double = 100, attack: Double = 100, maximum: Double = 100_000) {
        func safe(_ value: Double) -> Double { value.isFinite ? min(maximum.isFinite ? max(100_000, min(1_000_000_000, maximum)) : 100_000, max(0.1, value)) : 100 }
        self.hp = safe(hp); self.attack = safe(attack)
    }
    static let base = Self()
}

struct Enemy: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let data: [Int]
    let freq: Int
    func value(_ index: Int) -> Int { data.indices.contains(index) ? data[index] : 0 }
    var imageName: String { String(format: "enemy%03d", id) }
    var traits: [EnemyTrait] { EnemyTrait.allCases.filter { value($0.index) > 0 && ($0 != .starredAlien || value(69) == 1) } }
    var abilities: [EnemyAbility] { EnemyAbility.allCases.filter { $0.isPresent(in: self) } }
    var attackRanges: [AttackRange] {
        var ranges: [AttackRange] = []
        if value(36) != 0 { ranges.append(AttackRange(hit: 1, start: value(35), width: value(36))) }
        if value(95) > 0 && value(97) != 0 { ranges.append(AttackRange(hit: 2, start: value(96), width: value(97))) }
        if value(98) > 0 && value(100) != 0 { ranges.append(AttackRange(hit: 3, start: value(99), width: value(100))) }
        return ranges
    }
    var attackTypes: [AttackType] {
        var types: [AttackType] = [value(11) > 0 ? .area : .single]
        if !attackRanges.isEmpty { types.append(attackRanges.contains { $0.start < 0 || $0.width < 0 } ? .omni : .longDistance) }
        return types
    }
    func stats(at magnification: EnemyMagnification = .base) -> EnemyStats {
        let attacks = [3, 55, 56].map { Int(floor(Double(max(0, value($0))) * magnification.attack / 100 + 0.000001)) }
        let attack = attacks.reduce(0, +)
        return EnemyStats(hp: Int(floor(Double(max(0, value(0))) * magnification.hp / 100 + 0.000001)),
            attack: attack, hits: attacks, dps: freq > 0 ? Double(attack) * 30 / Double(freq) : 0,
            range: value(5), speed: value(2), knockbacks: value(1), money: value(6),
            frequency: Double(max(0, freq)) / 30, startup: Double(value(12)) / 30)
    }
}

struct EnemyStats {
    let hp: Int
    let attack: Int
    let hits: [Int]
    let dps: Double
    let range: Int
    let speed: Int
    let knockbacks: Int
    let money: Int
    let frequency: Double
    let startup: Double
}

enum EnemyMetric: String, CaseIterable, Codable, Identifiable {
    case hp = "HP", attack = "ATK", dps = "DPS", range = "射程", speed = "速度", knockbacks = "KB"
    case frequency = "攻撃頻度", startup = "攻撃発生", money = "お金（基本値）"
    var id: String { rawValue }
    func value(_ stats: EnemyStats) -> Double {
        switch self {
        case .hp: Double(stats.hp); case .attack: Double(stats.attack); case .dps: stats.dps
        case .range: Double(stats.range); case .speed: Double(stats.speed); case .knockbacks: Double(stats.knockbacks)
        case .frequency: stats.frequency; case .startup: stats.startup; case .money: Double(stats.money)
        }
    }
    func formatted(_ stats: EnemyStats) -> String {
        if [.frequency, .startup].contains(self) { return String(format: "%.2f秒", value(stats)) }
        return Int(value(stats).rounded(.down)).formatted(.number.locale(Locale(identifier: "en_US")))
    }
}

enum EnemyTrait: String, CaseIterable, Codable, Identifiable {
    case red = "赤", floating = "浮き", black = "黒", metal = "メタル", angel = "天使"
    case alien = "エイリアン", starredAlien = "スターエイリアン", zombie = "ゾンビ", relic = "古代種"
    case aku = "悪魔", traitless = "無属性", witch = "魔女", eva = "使徒"
    case colossus = "超生命体", behemoth = "超獣", sage = "超賢者", kaijin = "怪人"
    var id: String { rawValue }
    var index: Int {
        switch self {
        case .red: 10; case .floating: 13; case .black: 14; case .metal: 15; case .traitless: 16
        case .angel: 17; case .alien: 18; case .starredAlien: 69; case .zombie: 19; case .witch: 48
        case .eva: 71; case .relic: 72; case .aku: 93; case .colossus: 94; case .behemoth: 101
        case .sage: 104; case .kaijin: 110
        }
    }
    var iconName: String {
        switch self {
        case .colossus, .behemoth, .sage, .kaijin: "enemyTrait_\(String(describing: self))"
        case .starredAlien: "trait_alien"
        default: "trait_\(String(describing: self))"
        }
    }
}

enum EnemyAbility: String, CaseIterable, Codable, Identifiable {
    case freeze = "動きを止める", slow = "動きを遅くする", weaken = "攻撃力ダウン", knockback = "ふっとばす"
    case curse = "呪い", warp = "ワープ", dodge = "攻撃無効", toxic = "毒撃", productionDelay = "再生産遅延"
    case wave = "波動", miniWave = "小波動", surge = "烈波", miniSurge = "小烈波", explosion = "爆波"
    case critical = "クリティカル", savage = "渾身の一撃", strengthen = "攻撃力アップ", survive = "生き残る"
    case waveBlock = "波動ストッパー", counterSurge = "烈波反射", baseDestroyer = "城破壊"
    case burrow = "潜伏", revive = "蘇生", barrier = "バリア", shield = "悪魔シールド", deathSurge = "死亡時烈波", finiteAttacks = "攻撃回数制限"
    case waveImmune = "波動無効", surgeImmune = "烈波無効", curseImmune = "呪い無効", freezeImmune = "停止無効"
    case slowImmune = "鈍足無効", weakenImmune = "攻撃力ダウン無効", knockbackImmune = "ふっとばし無効"
    case warpImmune = "ワープ無効", explosionImmune = "爆波無効"
    var id: String { rawValue }
    static let categories: [FeatureCategory] = [.effect, .ability, .immunity]
    var category: FeatureCategory {
        switch self {
        case .freeze, .slow, .weaken, .knockback, .curse, .warp, .dodge, .toxic, .productionDelay: .effect
        case .waveImmune, .surgeImmune, .curseImmune, .freezeImmune, .slowImmune, .weakenImmune, .knockbackImmune, .warpImmune, .explosionImmune: .immunity
        default: .ability
        }
    }
    var index: Int {
        switch self {
        case .knockback: 20; case .freeze: 21; case .slow: 23; case .critical: 25; case .baseDestroyer: 26
        case .wave, .miniWave: 27; case .weaken: 29; case .strengthen: 33; case .survive: 34
        case .waveImmune: 37; case .waveBlock: 38; case .knockbackImmune: 39; case .freezeImmune: 40
        case .slowImmune: 41; case .weakenImmune: 42; case .burrow: 43; case .revive: 45
        case .finiteAttacks: 50; case .barrier: 64; case .warp: 65; case .warpImmune: 70; case .curse: 73
        case .savage: 75; case .dodge: 77; case .toxic: 79; case .surge, .miniSurge: 81
        case .surgeImmune: 85; case .shield: 87; case .deathSurge: 89; case .counterSurge: 103
        case .curseImmune: 105; case .explosion: 106; case .explosionImmune: 109; case .productionDelay: 111
        }
    }
    var iconName: String {
        switch self {
        case .burrow, .revive, .barrier, .shield, .deathSurge, .toxic, .productionDelay: "enemyAbility_\(String(describing: self))"
        case .finiteAttacks: "ability_suicide"
        default: "ability_\(String(describing: self))"
        }
    }
    func isPresent(in enemy: Enemy) -> Bool {
        if [.burrow, .revive].contains(self) { return enemy.value(index) != 0 }
        guard enemy.value(index) > 0 else { return false }
        switch self {
        case .wave: return enemy.value(86) == 0
        case .miniWave: return enemy.value(86) > 0
        case .surge: return enemy.value(102) == 0
        case .miniSurge: return enemy.value(102) > 0
        default: return true
        }
    }
    func facts(_ enemy: Enemy, magnification: EnemyMagnification = .base) -> [FeatureFact] {
        func fact(_ label: String, _ value: String) -> FeatureFact { FeatureFact(label: label, value: value) }
        func seconds(_ column: Int) -> String { Ability.seconds(enemy.value(column)) }
        let probability = fact("発動確率", "\(enemy.value(index))%")
        let duration: Int? = switch self { case .freeze: 22; case .slow: 24; case .weaken: 30; case .curse: 74; case .dodge: 78; default: nil }
        if let duration {
            var facts = [probability, fact("効果時間", seconds(duration))]
            if self == .weaken { facts.append(fact("効果中の味方攻撃力", "\(enemy.value(31))%")) }
            return facts
        }
        switch self {
        case .wave, .miniWave:
            return [probability, fact("波動レベル", "Lv.\(enemy.value(28))"),
                fact("波動の射程", String(format: "%.1f", 267.5 + Double(enemy.value(28)) * 200)),
                fact("ダメージ", self == .miniWave ? "通常攻撃の20%" : "通常攻撃の100%")]
        case .surge, .miniSurge, .deathSurge:
            let level = enemy.value(self == .deathSurge ? 92 : 84)
            let start = enemy.value(self == .deathSurge ? 90 : 82) >> 2
            let width = enemy.value(self == .deathSurge ? 91 : 83) >> 2
            return [probability, fact("烈波レベル", "Lv.\(level)"), fact("持続時間", Ability.seconds(level * 20)),
                fact("発生位置", "\(start)〜\(start + width)"),
                fact("ダメージ", self == .miniSurge ? "1回あたり通常攻撃の20%" : "1回あたり通常攻撃の100%")]
        case .explosion:
            return [probability, fact("発生位置", "\(enemy.value(107) >> 2)〜\((enemy.value(107) + enemy.value(108)) >> 2)")]
        case .warp: return [probability, fact("ワープ時間", seconds(66)), fact("移動距離", "\(enemy.value(67))〜\(enemy.value(68))")]
        case .savage: return [probability, fact("発動時の攻撃力", "\(100 + enemy.value(76))%")]
        case .strengthen: return [fact("発動条件", "残り体力\(enemy.value(32))%以下"), fact("発動中の攻撃力", "\(100 + enemy.value(33))%")]
        case .knockback, .survive: return [probability]
        case .critical: return [probability, fact("ダメージ", "通常攻撃の2倍・メタルにも有効")]
        case .burrow: return [fact("潜伏回数", enemy.value(43) == -1 ? "無制限" : "\(enemy.value(43))回"), fact("潜伏距離", "\(enemy.value(44))")]
        case .revive: return [fact("蘇生回数", enemy.value(45) == -1 ? "無制限" : "\(enemy.value(45))回"),
            fact("蘇生までの時間", seconds(46)), fact("蘇生時の体力", "\(enemy.value(47))%")]
        case .barrier, .shield:
            // Barrier durability is fixed; the Aku shield follows HP magnification.
            let durability = self == .shield ? Int(floor(Double(enemy.value(87)) * magnification.hp / 100 + 0.000001)) : enemy.value(64)
            var facts = [fact("耐久値", durability.formatted())]
            if self == .shield { facts.append(fact("KB時のシールド再生", "\(enemy.value(88))%")) }
            return facts
        case .toxic: return [probability, fact("追加ダメージ", "味方の最大体力の\(enemy.value(80))%")]
        case .productionDelay: return [probability, fact("再生産時間の延長", "\(enemy.value(112))%")]
        case .finiteAttacks: return [fact("攻撃回数", "\(enemy.value(50))回")]
        default: return []
        }
    }
    func badges(_ enemy: Enemy, magnification: EnemyMagnification = .base) -> [String] {
        let facts = facts(enemy, magnification: magnification)
        if let probability = facts.first(where: { $0.label == "発動確率" }) {
            if [.wave, .miniWave].contains(self) { return [probability.value, "Lv.\(enemy.value(28))"] }
            if [.surge, .miniSurge, .deathSurge].contains(self) {
                let level = enemy.value(self == .deathSurge ? 92 : 84)
                return [probability.value, "Lv.\(level)(\(Ability.seconds(level * 20)))"]
            }
            return [probability.value] + facts.filter { $0.label.contains("時間") }.prefix(1).map(\.value)
        }
        if self == .strengthen { return ["HP≤\(enemy.value(32))%", "＋\(enemy.value(33))%"] }
        if self == .revive { return Array(facts.prefix(2).map(\.value)) }
        if [.burrow, .barrier, .shield, .finiteAttacks].contains(self) { return Array(facts.prefix(1).map(\.value)) }
        return []
    }
    func explanation(_ enemy: Enemy, magnification: EnemyMagnification = .base) -> String {
        let facts = facts(enemy, magnification: magnification)
        if !facts.isEmpty { return facts.map { "\($0.label)：\($0.value)" }.joined(separator: "\n") }
        switch self {
        case .baseDestroyer: return "味方の城へのダメージが4倍。"
        case .waveBlock: return "波動・小波動を打ち消す。"
        case .counterSurge: return "受けた烈波を反射する。"
        default: return category == .immunity ? "この効果を受けない。" : "\(rawValue)の特性を持つ。"
        }
    }
    func affectedHits(_ enemy: Enemy) -> String? {
        let hits = [3, 55, 56].enumerated().filter { enemy.value($0.element) > 0 }
        guard hits.count > 1, category != .immunity,
              ![.burrow, .revive, .barrier, .shield, .deathSurge, .strengthen, .survive, .finiteAttacks].contains(self) else { return nil }
        let enabled = hits.filter { enemy.value(59 + $0.offset) > 0 }.map { "\($0.offset + 1)撃目" }
        return enabled.isEmpty ? nil : enabled.joined(separator: "・")
    }
}
