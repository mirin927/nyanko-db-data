import Foundation

enum TalentMode: String, CaseIterable, Codable, Identifiable {
    case none = "未解放", max = "MAX", saved = "保存設定"
    var id: String { rawValue }
}

struct TalentProfile: Codable, Equatable {
    var levels: [String: Int] = [:]
    func level(_ talent: TalentDefinition) -> Int { min(talent.maxLevel, max(0, levels[talent.id, default: 0])) }
    mutating func set(_ talent: TalentDefinition, level: Int) { levels[talent.id] = min(talent.maxLevel, max(0, level)) }
    mutating func maximize(_ talents: [TalentDefinition], form: UnitForm, level: Int, normalOnly: Bool = false) {
        for talent in talents where talent.available(form: form, level: level) && (!normalOnly || !talent.isSuper) {
            set(talent, level: talent.maxLevel)
        }
    }
}

struct TalentSupport: Decodable {
    struct Timing: Decodable { let interval: Int; let backswing: Int }
    let version: Int
    let catalogVersion: String
    let superUnlockLevel: Int
    let costs: [String: [Int]]
    let descriptions: [String: String]
    let timings: [String: Timing]
    static let empty = TalentSupport(version: 1, catalogVersion: "", superUnlockLevel: 60, costs: [:], descriptions: [:], timings: [:])
}

struct TalentDefinition: Identifiable, Hashable {
    let id: String
    let effect: Int
    let maxLevel: Int
    let isSuper: Bool
    let parameters: [Int]
    let costs: [Int]?
    let description: String
    let extraTraits: Int
    let unlockLevel: Int
    let supported: Bool

    static func decode(_ form: UnitForm, entryID: String, support: TalentSupport) -> [TalentDefinition] {
        let raw = form.allTalentData
        guard form.hasValidTalentLayout, !raw.isEmpty else { return [] }
        var duplicates: [String: Int] = [:]
        return stride(from: 1, to: raw.count, by: 14).compactMap { start in
            guard raw[start] > 0 else { return nil }
            let slot = Array(raw[start..<(start + 14)])
            let key = "\(slot[13] == 1 ? "super" : "normal")-\(slot[0])-\(slot[10])"
            let occurrence = duplicates[key, default: 0]; duplicates[key] = occurrence + 1
            let supported = supportedEffects.contains(slot[0]) && slot[1] >= 0 && slot[1] <= 10 &&
                (slot[13] == 0 || slot[13] == 1) && (slot[0] != 61 || support.timings[entryID] != nil)
            return TalentDefinition(id: occurrence == 0 ? key : "\(key)-\(occurrence)", effect: slot[0],
                maxLevel: max(1, slot[1]), isSuper: slot[13] == 1, parameters: Array(slot[2..<10]),
                costs: support.costs[String(slot[11])], description: support.descriptions[String(slot[10])] ?? "詳細未取得",
                extraTraits: raw[0], unlockLevel: support.superUnlockLevel, supported: supported)
        }
    }
    static let supportedEffects: Set<Int> = Set([1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69])
    func available(form: UnitForm, level: Int) -> Bool { supported && form.number >= 3 && (!isSuper || level >= unlockLevel) }
    func increments(at level: Int) -> [Int] {
        let rank = min(maxLevel, max(1, level))
        return stride(from: 0, to: 8, by: 2).map { i in
            maxLevel == 1 ? parameters[i] : parameters[i] + (rank - 1) * (parameters[i + 1] - parameters[i]) / (maxLevel - 1)
        }
    }
    func cost(to level: Int) -> Int? {
        guard level > 0 else { return 0 }
        guard let costs, costs.count >= level, level <= maxLevel else { return nil }
        return costs.prefix(level).reduce(0, +)
    }
    var ability: Ability? {
        switch effect {
        case 1: .weaken; case 2: .freeze; case 3: .slow; case 4: .attacksOnly
        case 5: .strong; case 6: .resistant; case 7: .massive; case 8: .knockback
        case 10: .strengthen; case 11: .survive; case 12: .baseDestroyer; case 13: .critical
        case 14: .zombieKiller; case 15: .barrier; case 16: .extraMoney; case 17: .wave
        case 18: .weakenResist; case 19: .freezeResist; case 20: .slowResist; case 21: .knockbackResist
        case 22: .waveResist; case 23: .waveBlock; case 24: .warpResist; case 29: .curseImmune; case 30: .curseResist
        case 44: .weakenImmune; case 45: .freezeImmune; case 46: .slowImmune; case 47: .knockbackImmune
        case 48: .waveImmune; case 49: .warpImmune; case 50: .savage; case 51: .dodge
        case 52: .toxicResist; case 53: .toxicImmune; case 54: .surgeResist; case 55: .surgeImmune
        case 56: .surge; case 58: .shield; case 59: .soul; case 60: .curse
        case 62: .miniWave; case 63: .colossus; case 64: .behemoth; case 65: .miniSurge
        case 66: .sage; case 67: .explosion; case 68: .counterSurge; case 69: .explosionImmune
        default: nil
        }
    }
    var trait: Trait? {
        switch effect {
        case 33: .red; case 34: .floating; case 35: .black; case 36: .metal; case 37: .angel
        case 38: .alien; case 39: .zombie; case 40: .relic; case 41: .traitless
        case 42: .witch; case 43: .eva; case 57: .aku
        default: nil
        }
    }
    var name: String {
        if let ability { return ability.rawValue }
        if let trait { return "対象属性追加：\(trait.rawValue)" }
        switch effect {
        case 25: return "生産コスト減少"; case 26: return "再生産短縮"; case 27: return "移動速度アップ"
        case 28: return "KB数アップ"; case 31: return "基本攻撃力アップ"; case 32: return "基本体力アップ"
        case 61: return "攻撃間隔短縮"
        case 70: return "基本攻撃力アップ（大幅）"
        case 71: return "基本体力アップ（大幅）"
        case 72: return "生産時間短縮"
        default: return "詳細未対応（\(effect)）"
        }
    }
    var iconName: String {
        if let ability { return ability.iconName }
        if let trait { return trait.iconName }
        switch effect {
        case 25: return "talent_cost"; case 26: return "talent_cooldown"; case 27: return "talent_speed"
        case 28: return "talent_knockbacks"; case 31: return "talent_attack"; case 32: return "talent_hp"
        case 61: return "talent_interval"
        case 70: return "talent_attack"
        case 71: return "talent_hp"
        case 72: return "talent_cooldown"
        default: return "talent_unknown"
        }
    }
    func summary(at level: Int) -> String {
        guard supported else { return "詳細未対応" }
        guard level > 0 else { return "未解放" }
        let p = increments(at: level)
        if ability?.category == .resistance { return "\(p[0])%軽減" }
        switch effect {
        case 31,32: return "＋\(p[0])%"
        case 27,28: return "＋\(p[0])"
        case 25: return "−\(Int(Double(p[0]) * 1.5))円"
        case 26: return "−\(Ability.seconds(p[0] * 2))"
        case 61: return "間隔−\(p[0])%"
        default: return maxLevel == 1 ? "解放" : "Lv.\(level)"
        }
    }
}

struct UnitPerformance {
    let form: UnitForm
    let stats: Stats
    let applied: [String: Int]
    var normalCount: Int { applied.keys.filter { $0.hasPrefix("normal-") }.count }
    var superCount: Int { applied.keys.filter { $0.hasPrefix("super-") }.count }
    func summary(_ talents: [TalentDefinition]) -> String {
        let normal = talents.filter { !$0.isSuper }.count, ultra = talents.filter(\.isSuper).count
        return "本能 \(normalCount)/\(normal)" + (ultra > 0 ? " · 超本能 \(superCount)/\(ultra)" : "")
    }
}

extension Unit {
    func performance(for original: UnitForm, level: Int, talents: [TalentDefinition], profile: TalentProfile,
                     timing: TalentSupport.Timing? = nil, comboBonuses: ComboStatBonuses = .none) -> UnitPerformance {
        let actualLevel = min(max(1, level), maxBase + maxPlus)
        let selected = talents.filter { profile.level($0) > 0 && $0.available(form: original, level: actualLevel) }
        guard !selected.isEmpty else { return UnitPerformance(form: original, stats: stats(for: original, level: actualLevel, comboBonuses: comboBonuses), applied: [:]) }
        var data = original.data
        if data.count < 119 {
            let hadSummon = data.indices.contains(110)
            data += Array(repeating: 0, count: 119 - data.count)
            if !hadSummon { data[110] = -1 }
        }
        var resist = original.resistanceValues ?? [:]
        var hpBonus = 0, attackBonus = 0, frequency = original.freq
        let applied = Dictionary(selected.map { ($0.id, profile.level($0)) }, uniquingKeysWith: { a, _ in a })
        for talent in selected {
            let p = talent.increments(at: profile.level(talent))
            if talent.ability?.category == .effect, talent.extraTraits != 0 {
                for (bit, trait) in [(1,Trait.red),(2,.floating),(4,.black),(8,.metal),(16,.angel),(32,.alien),(64,.zombie),(128,.relic),(256,.traitless),(512,.eva),(1024,.witch),(2048,.aku)] where talent.extraTraits & bit != 0 { data[trait.index] = 1 }
            }
            if let trait = talent.trait { data[trait.index] = 1; continue }
            if let ability = talent.ability, ability.category == .resistance { resist[ability.rawValue] = p[0]; continue }
            switch talent.effect {
            case 1: data[37] += p[0]; data[38] += p[1]; if p[2] > 0 { data[39] += 100 - p[2] }
            case 2: data[25] += p[0]; data[26] += p[1]
            case 3: data[27] += p[0]; data[28] += p[1]
            case 8,11,13,15,58: if let a = talent.ability { data[a.index] += p[0] }
            case 10:
                if data[41] == 0 { data[40] = 100 - p[0] }; data[41] += p[1]
            case 17,62:
                data[35] += p[0]; data[36] += p[1]; data[94] = talent.effect == 62 ? 20 : 0
            case 25: data[6] = max(0, data[6] - p[0])
            case 26: data[7] = max(0, data[7] - p[0])
            case 27: data[2] += p[0]
            case 28: data[1] += p[0]
            case 31: attackBonus = p[0]
            case 32: hpBonus = p[0]
            case 50: data[82] += p[0]; data[83] += p[1]
            case 51: data[84] += p[0]; data[85] += p[1]
            case 56,65:
                data[86] += p[0]; data[89] += p[1]; data[87] = p[2]; data[88] = p[3]; data[108] = talent.effect == 65 ? 20 : 0
            case 60: data[92] += p[1]; data[93] += p[0]
            case 61:
                if let timing {
                    let interval = timing.interval * (100 - p[0]) / 100
                    frequency = (data[62] != 0 ? data[62] : (data[61] != 0 ? data[61] : data[13])) + max(timing.backswing, interval - 1)
                }
            case 64: data[105] = 1; data[106] = p[0]; data[107] = p[1]
            case 67: data[113] += p[0]; data[114] = p[1]; data[115] = p[2]
            default: if let a = talent.ability { data[a.index] = max(1, data[a.index]) }
            }
        }
        // An already present chance and a talent can add up beyond 100;
        // the effective probability remains bounded by a certain activation.
        for index in [24,25,27,31,35,37,42,70,71,82,84,86,92,95,106,113] {
            data[index] = min(100, max(0, data[index]))
        }
        var form = UnitForm(form: original.form, name: original.name, data: data, freq: frequency,
                            talent: original.talent, superTalent: original.superTalent, talentData: original.talentData)
        form.resistanceValues = resist
        form.additionalTalentData = original.additionalTalentData
        return UnitPerformance(form: form, stats: stats(for: form, level: actualLevel, hpBonus: hpBonus, attackBonus: attackBonus, comboBonuses: comboBonuses), applied: applied)
    }
}

struct TalentProfileStorage: Codable {
    let version: Int
    let profiles: [Int: TalentProfile]
}
