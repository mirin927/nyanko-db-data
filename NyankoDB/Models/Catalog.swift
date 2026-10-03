import Foundation

struct Catalog: Codable {
    let version: String
    let source: String
    let units: [Unit]
}

struct Unit: Codable, Identifiable, Hashable {
    let id: Int
    let rarity: Int
    let forms: [UnitForm]
    let growth: [Int]
    let maxBase: Int
    let maxPlus: Int
    let eggPortraits: [String: Int]?
    var rarityName: String { Self.rarities.indices.contains(rarity) ? Self.rarities[rarity] : "その他" }
    static let rarities = ["基本", "EX", "レア", "激レア", "超激レア", "伝説レア"]
    var latest: UnitForm { forms.max(by: { $0.number < $1.number })! }

    /// CSV growth bands start at level 2. Work in integer percentages to avoid rounding drift.
    func levelPercent(_ level: Int) -> Int {
        let clamped = max(1, min(level, maxBase + maxPlus))
        return 100 + (1..<clamped).reduce(0) { total, step in
            let band = min(step / 10, growth.count - 1)
            return total + (growth.isEmpty ? 20 : growth[band])
        }
    }
    func stats(for form: UnitForm, level: Int, hpBonus: Int = 0, attackBonus: Int = 0, comboBonuses: ComboStatBonuses = .none) -> Stats {
        let multiplier = Double(levelPercent(level)) / 100 * 2.5
        func adjusted(_ raw: Int, combo: Int, talent: Int) -> Int {
            let leveled = floor(Double(raw) * multiplier + 0.000001)
            let combined = floor(leveled * Double(100 + combo) / 100 + 0.000001)
            return Int(floor(combined * Double(100 + talent) / 100 + 0.000001))
        }
        let hp = adjusted(form.value(0), combo: comboBonuses.hpPercent, talent: hpBonus)
        let attack = [3, 59, 60].reduce(0) { $0 + adjusted(form.value($1), combo: comboBonuses.attackPercent, talent: attackBonus) }
        return Stats(hp: hp, attack: attack,
                     dps: form.freq > 0 ? Double(attack) * 30 / Double(form.freq) : 0,
                     range: form.value(5), speed: form.value(2), knockbacks: form.value(1),
                     cost: Int(Double(form.value(6)) * 1.5),
                     cooldown: Double(max(60, form.value(7) * 2 - 264)) / 30,
                     frequency: Double(form.freq) / 30,
                     startup: Double(form.value(13)) / 30)
    }
}

struct UnitForm: Codable, Hashable, Identifiable {
    let form: String
    let name: String
    let data: [Int]
    let freq: Int
    let talent: Int
    let superTalent: Int
    let talentData: [Int]
    var resistanceValues: [String: Int]?
    var id: String { form }
    var number: Int { ["f": 1, "c": 2, "s": 3, "u": 4][form] ?? 1 }
    func value(_ index: Int) -> Int { data.indices.contains(index) ? data[index] : 0 }
    var summonedUnitID: Int? {
        guard data.indices.contains(110), data[110] >= 0 else { return nil }
        return data[110]
    }
    var traits: [Trait] { Trait.allCases.filter { value($0.index) > 0 } }
    var abilities: [Ability] { Ability.allCases.filter { $0.isPresent(in: self) } }
    var attackRanges: [AttackRange] {
        var ranges: [AttackRange] = []
        if value(45) != 0 { ranges.append(AttackRange(hit: 1, start: value(44), width: value(45))) }
        if value(99) > 0 && value(101) != 0 { ranges.append(AttackRange(hit: 2, start: value(100), width: value(101))) }
        if value(102) > 0 && value(104) != 0 { ranges.append(AttackRange(hit: 3, start: value(103), width: value(104))) }
        return ranges
    }
    var attackTypes: [AttackType] {
        var types: [AttackType] = [value(12) > 0 ? .area : .single]
        if !attackRanges.isEmpty { types.append(attackRanges.contains { $0.start < 0 || $0.width < 0 } ? .omni : .longDistance) }
        return types
    }
}

struct AttackRange: Identifiable {
    let hit: Int
    let start: Int
    let width: Int
    var id: Int { hit }
    var lower: Int { min(start, start + width) }
    var upper: Int { max(start, start + width) }
}

struct Entry: Identifiable, Hashable {
    let unit: Unit
    let form: UnitForm
    var id: String { "\(unit.id)-\(form.form)" }
    var imageName: String {
        if let egg = unit.eggPortraits?[form.form] { return String(format: "egg%03d", egg) }
        return String(format: "unit%03d_%@", unit.id, form.form)
    }
}

struct Stats: Hashable {
    let hp: Int
    let attack: Int
    let dps: Double
    let range: Int
    let speed: Int
    let knockbacks: Int
    let cost: Int
    let cooldown: Double
    let frequency: Double
    let startup: Double
}

enum Trait: String, CaseIterable, Codable, Identifiable {
    case red = "赤", floating = "浮き", black = "黒", metal = "メタル", angel = "天使"
    case alien = "エイリアン", zombie = "ゾンビ", relic = "古代種", aku = "悪魔", traitless = "無属性"
    case witch = "魔女", eva = "使徒"
    var id: String { rawValue }
    var index: Int {
        switch self {
        case .red: 10; case .floating: 16; case .black: 17; case .metal: 18
        case .angel: 20; case .alien: 21; case .zombie: 22; case .relic: 78; case .aku: 96; case .traitless: 19
        case .witch: 54; case .eva: 76
        }
    }
}

enum AttackType: String, CaseIterable, Codable, Identifiable {
    case single = "単体", area = "範囲", longDistance = "遠方", omni = "全方位"
    var id: String { rawValue }
}

enum FeatureCategory: String, CaseIterable, Identifiable {
    case ability = "能力", immunity = "無効", effect = "効果", resistance = "耐性"
    var id: String { rawValue }
    var features: [Ability] { Ability.allCases.filter { $0.category == self } }
}

enum Ability: String, CaseIterable, Codable, Identifiable {
    // Target-dependent effects, including both control and attribute multipliers.
    case strong = "めっぽう強い", resistant = "打たれ強い", massive = "超ダメージ", insaneDamage = "極ダメージ", tough = "超打たれ強い"
    case freeze = "動きを止める", slow = "動きを遅くする", weaken = "攻撃力ダウン", knockback = "ふっとばす"
    case curse = "呪い", warp = "ワープ", attacksOnly = "ターゲット限定", dodge = "攻撃無効"
    // Abilities independent of the attack's single/area/long-distance classification.
    case wave = "波動", miniWave = "小波動", surge = "烈波", miniSurge = "小烈波", explosion = "爆波"
    case critical = "クリティカル", savage = "渾身の一撃", metalKiller = "メタルキラー"
    case strengthen = "攻撃力アップ", survive = "生き残る", zombieKiller = "ゾンビキラー", barrier = "バリアブレイク", shield = "シールドブレイク"
    case waveBlock = "波動ストッパー", counterSurge = "烈波反射", soul = "魂攻撃"
    case baseDestroyer = "城破壊", metal = "メタル", extraMoney = "お金2倍", summon = "召喚", suicide = "一回攻撃"
    case colossus = "超生命体特効", behemoth = "超獣特効", sage = "超賢者特効", witchKiller = "魔女キラー", evaKiller = "使徒キラー"
    // Fixed immunities. Attack dodge belongs to target-dependent effects above.
    case waveImmune = "波動無効", surgeImmune = "烈波無効", curseImmune = "古代の呪い無効"
    case freezeImmune = "停止無効", slowImmune = "鈍足無効", weakenImmune = "攻撃力ダウン無効", knockbackImmune = "ふっとばし無効", warpImmune = "ワープ無効"
    case toxicImmune = "毒撃無効", explosionImmune = "爆波無効", drainImmune = "再生産遅延無効", shockwaveImmune = "衝撃波無効"
    case weakenResist = "攻撃力ダウン耐性", freezeResist = "停止耐性", slowResist = "鈍足耐性", knockbackResist = "ふっとばし耐性"
    case waveResist = "波動耐性", warpResist = "ワープ耐性", curseResist = "古代の呪い耐性", toxicResist = "毒撃耐性", surgeResist = "烈波耐性"
    case explosionResist = "爆波耐性"
    var id: String { rawValue }
    var category: FeatureCategory {
        switch self {
        case .strong, .resistant, .massive, .insaneDamage, .tough, .freeze, .slow, .weaken, .knockback, .curse, .warp, .attacksOnly, .dodge: .effect
        case .waveImmune, .surgeImmune, .curseImmune, .freezeImmune, .slowImmune, .weakenImmune, .knockbackImmune, .warpImmune, .toxicImmune, .explosionImmune, .drainImmune, .shockwaveImmune: .immunity
        case .weakenResist, .freezeResist, .slowResist, .knockbackResist, .waveResist, .warpResist, .curseResist, .toxicResist, .surgeResist, .explosionResist: .resistance
        default: .ability
        }
    }
    var index: Int {
        switch self {
        case .strong: 23; case .resistant: 29; case .massive: 30; case .critical: 31
        case .freeze: 25; case .slow: 27; case .weaken: 37; case .knockback: 24
        case .curse: 92; case .warp: 71; case .attacksOnly: 32; case .dodge: 84
        case .wave, .miniWave: 35; case .surge, .miniSurge: 86; case .explosion: 113
        case .savage: 82; case .metalKiller: 112
        case .strengthen: 40; case .survive: 42; case .zombieKiller: 52; case .barrier: 70; case .shield: 95
        case .baseDestroyer: 34; case .metal: 43; case .extraMoney: 33; case .summon: 110; case .suicide: 58
        case .waveBlock: 47; case .waveImmune: 46; case .surgeImmune: 91; case .curseImmune: 79
        case .freezeImmune: 49; case .slowImmune: 50; case .weakenImmune: 51; case .knockbackImmune: 48; case .warpImmune: 75
        case .toxicImmune: 90; case .explosionImmune: 116; case .drainImmune: 117; case .shockwaveImmune: 56
        case .tough: 80; case .insaneDamage: 81; case .colossus: 97; case .behemoth: 105; case .sage: 111; case .soul: 98; case .counterSurge: 109
        case .witchKiller: 53; case .evaKiller: 77
        case .weakenResist, .freezeResist, .slowResist, .knockbackResist, .waveResist, .warpResist, .curseResist, .toxicResist, .surgeResist, .explosionResist: -1
        }
    }
    func isPresent(in form: UnitForm) -> Bool {
        if category == .resistance { return (form.resistanceValues?[rawValue] ?? 0) > 0 }
        return switch self {
        case .wave: form.value(35) > 0 && form.value(94) == 0
        case .miniWave: form.value(35) > 0 && form.value(94) > 0
        case .surge: form.value(86) > 0 && form.value(108) == 0
        case .miniSurge: form.value(86) > 0 && form.value(108) > 0
        // A missing legacy column defaults to 0, but summon ID 0 is valid.
        case .summon: form.summonedUnitID != nil
        case .suicide: form.value(58) == 2
        case .strengthen: form.value(41) > 0
        default: form.value(index) > 0
        }
    }

}

enum Metric: String, CaseIterable, Codable, Identifiable {
    case hp = "HP", attack = "ATK", dps = "DPS", range = "射程", speed = "速度", cost = "コスト", cooldown = "再生産", knockbacks = "KB", frequency = "攻撃頻度", startup = "攻撃発生"
    var id: String { rawValue }
    func value(_ s: Stats) -> Double {
        switch self {
        case .hp: Double(s.hp); case .attack: Double(s.attack); case .dps: s.dps; case .range: Double(s.range)
        case .speed: Double(s.speed); case .cost: Double(s.cost); case .cooldown: s.cooldown; case .knockbacks: Double(s.knockbacks); case .frequency: s.frequency; case .startup: s.startup
        }
    }
    func formatted(_ s: Stats) -> String {
        if [.cooldown, .frequency, .startup].contains(self) { return String(format: "%.2f秒", value(s)) }
        return Int(value(s).rounded(.down)).formatted(.number.locale(Locale(identifier: "en_US")))
    }
}
