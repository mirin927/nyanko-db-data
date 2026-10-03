import Foundation

struct TalentOrb: Codable, Identifiable, Equatable {
    let id: String
    let effect: Int
    let grade: String
    let trait: Trait?
    let name: String
    let description: String
    let values: [Int]
    let repeatable: Bool
    let iconName: String
    var title: String { "\(name)【\(grade)】" + (trait.map { "【\($0.rawValue)】" } ?? "") }
    var requiredAbility: Ability? { [2: .strong, 3: .massive, 4: .resistant][effect] }
    var resistance: Ability? {
        [6: .waveResist, 8: .knockbackResist, 12: .toxicResist, 14: .slowResist,
         15: .curseResist, 20: .freezeResist, 21: .weakenResist, 23: .surgeResist, 25: .explosionResist][effect]
    }
    func unavailableReason(form: UnitForm) -> String? {
        if let ability = requiredAbility, (!form.abilities.contains(ability) || !(trait.map { form.traits.contains($0) } ?? false)) {
            return "この形態・本能設定に、対象属性への\(ability.rawValue)がありません。"
        }
        if effect == 10 && form.abilities.contains(.colossus) { return "超生命体特効を持つ形態には装着できません。" }
        return nil
    }
    var summary: String {
        let v = values.first ?? 0
        switch effect {
        case 0: return "基礎攻撃力の\(v)%を追加（レベル・お宝・本能・特性倍率の対象外）"
        case 1: return "対応属性からのダメージを\(v)%軽減"
        case 2: return "与ダメージ倍率 +\(String(format: "%.2f", Double(v)/1000))・被ダメージ \(values.count > 1 ? values[1] : 0)%軽減"
        case 3: return "超ダメージ倍率 +\(String(format: "%.2f", Double(v)/300))"
        case 4: return "打たれ強いの被ダメージを\(v)%軽減"
        case 6,8,12,14,15,20,21,23,25: return "\(v)%軽減（本能の耐性に加算・最大100%）"
        default: return description
        }
    }
}

struct OrbProfile: Codable, Equatable {
    var enabled = true
    var slots: [String?] = [nil, nil]
    mutating func set(_ orb: TalentOrb?, slot: Int) {
        guard (0..<2).contains(slot) else { return }
        while slots.count < 2 { slots.append(nil) }
        slots[slot] = orb?.id
    }
}
struct OrbProfileStorage: Codable { let version: Int; let profiles: [Int: OrbProfile] }

struct OrbSupport: Codable {
    let version: Int
    let catalogVersion: String
    let slots: [String: [Int]]
    let orbs: [TalentOrb]
    static let empty = OrbSupport(version: 1, catalogVersion: "", slots: [:], orbs: [])
    func validated(for catalog: Catalog) -> OrbSupport {
        let units = Set(catalog.units.map(\.id))
        guard version == 1, catalogVersion == catalog.version,
              Set(orbs.map(\.id)).count == orbs.count,
              orbs.allSatisfy({ (0..<26).contains($0.effect) && ["D","C","B","A","S"].contains($0.grade) && !$0.values.isEmpty && $0.values.allSatisfy { $0 >= 0 } && ($0.effect >= 5 ? $0.trait == nil : $0.trait != nil) }),
              slots.allSatisfy({ key, values in Int(key).map { units.contains($0) } == true && (values == [0] || values == [0,60]) }) else { return .empty }
        return self
    }
    func orb(_ id: String?) -> TalentOrb? { id.flatMap { key in orbs.first { $0.id == key } } }
    func requirements(for unitID: Int) -> [Int] { slots[String(unitID)] ?? [] }
    func sanitized(_ profiles: [Int: OrbProfile]) -> [Int: OrbProfile] {
        profiles.filter { !requirements(for: $0.key).isEmpty }.mapValues { profile in
            OrbProfile(enabled: profile.enabled, slots: (0..<2).map { profile.slots.indices.contains($0) ? orb(profile.slots[$0])?.id : nil })
        }
    }
    func active(entry: Entry, form: UnitForm, level: Int, profile: OrbProfile) -> [TalentOrb] {
        guard profile.enabled, entry.form.number >= 3 else { return [] }
        var used: Set<Int> = []
        return requirements(for: entry.unit.id).enumerated().compactMap { slot, unlock in
            guard min(level, entry.unit.maxBase + entry.unit.maxPlus) >= unlock, profile.slots.indices.contains(slot),
                  let orb = orb(profile.slots[slot]), orb.unavailableReason(form: form) == nil else { return nil }
            if !orb.repeatable && !used.insert(orb.effect).inserted { return nil }
            return orb
        }
    }
}

extension UnitPerformance {
    func applyingOrbResistances(_ orbs: [TalentOrb]) -> UnitPerformance {
        var form = self.form
        var values = form.resistanceValues ?? [:]
        for orb in orbs {
            if let ability = orb.resistance { values[ability.rawValue] = min(100, values[ability.rawValue, default: 0] + (orb.values.first ?? 0)) }
        }
        form.resistanceValues = values
        return UnitPerformance(form: form, stats: stats, applied: applied)
    }
}
