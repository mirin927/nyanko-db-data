import Foundation

/// The first row of a lineup is reconstructed from the chosen combos. Shared
/// characters use one slot, at the highest required evolution form.
struct VirtualComboLoadout: Codable, Equatable {
    var comboIDs: Set<Int> = []
    var enabled = true
    static let supportedEffects: Set<Int> = [0, 1, 14, 15, 16, 22, 23, 25]

    func members(in catalog: ComboCatalog, evaluating character: ComboCharacter? = nil) -> [ComboMember] {
        var forms: [Int: Int] = [:]
        for combo in catalog.combos where comboIDs.contains(combo.id) {
            for member in combo.members { forms[member.unitID] = max(forms[member.unitID] ?? 0, member.minimumForm) }
        }
        if let character, let form = character.form, forms[character.unitID] != nil { forms[character.unitID] = form }
        return forms.keys.sorted().map { ComboMember(unitID: $0, minimumForm: forms[$0]!) }
    }

    func canAdd(_ combo: NyanCombo, in catalog: ComboCatalog) -> Bool {
        var candidate = self
        candidate.comboIDs.insert(combo.id)
        return candidate.members(in: catalog).count <= 5
    }

    func activated(in catalog: ComboCatalog, evaluating character: ComboCharacter? = nil) -> [NyanCombo] {
        let team = members(in: catalog, evaluating: character)
        guard team.count <= 5 else { return [] }
        return ComboMaximumSolver(catalog: catalog).activatedCombos(in: ComboMaximumTeam(members: team, combos: []))
    }

    func bonuses(in catalog: ComboCatalog, unitID: Int, form: Int? = nil) -> ComboStatBonuses {
        enabled ? ComboStatBonuses(combos: activated(in: catalog, evaluating: ComboCharacter(unitID: unitID, form: form)), unitID: unitID) : .none
    }

    func sanitized(in catalog: ComboCatalog) -> Self {
        var clean = Self(enabled: enabled)
        for combo in catalog.combos.sorted(by: { $0.id < $1.id }) where comboIDs.contains(combo.id) && Self.supportedEffects.contains(combo.effectID) {
            if clean.canAdd(combo, in: catalog) { clean.comboIDs.insert(combo.id) }
        }
        return clean
    }
}

struct ComboStatBonuses: Equatable {
    // Charagroup.csv, group 10, in the bundled JDB revision.
    static let rangerIDs: Set<Int> = [831, 832, 833, 834, 835, 836, 857, 858]
    static let none = Self()
    private var values: [Int: Int] = [:]
    var attackPercent: Int { values[0] ?? 0 }
    var hpPercent: Int { values[1] ?? 0 }
    var strongPercent: Int { values[14] ?? 0 }
    var massivePercent: Int { values[15] ?? 0 }
    var resistantPercent: Int { values[16] ?? 0 }
    var witchPercent: Int { values[22] ?? 0 }
    var evaPercent: Int { values[23] ?? 0 }
    var kaijin: Bool { (values[25] ?? 0) > 0 }
    var isEmpty: Bool { values.isEmpty }

    init() {}
    init(combos: [NyanCombo], unitID: Int) {
        var seen: Set<Int> = []
        for combo in combos where seen.insert(combo.id).inserted && VirtualComboLoadout.supportedEffects.contains(combo.effectID) {
            guard combo.scope.isEmpty || (combo.scope == "にゃんこレンジャーのみ" && Self.rangerIDs.contains(unitID)) else { continue }
            values[combo.effectID, default: 0] += max(0, combo.effectValue)
        }
        values = values.filter { $0.value > 0 }
    }

    func summary(for form: UnitForm) -> String {
        var parts: [String] = []
        if hpPercent > 0 { parts.append("HP +\(hpPercent)%") }
        if attackPercent > 0 { parts.append("ATK +\(attackPercent)%") }
        if strongPercent > 0 && form.abilities.contains(.strong) { parts.append("めっぽう +\(strongPercent)%") }
        if massivePercent > 0 && form.abilities.contains(.massive) { parts.append("超ダメ +\(massivePercent)%") }
        if resistantPercent > 0 && form.abilities.contains(.resistant) { parts.append("打たれ強い +\(resistantPercent)%") }
        if witchPercent > 0 && form.abilities.contains(.witchKiller) { parts.append("魔女キラー強化") }
        if evaPercent > 0 && form.abilities.contains(.evaKiller) { parts.append("使徒キラー強化") }
        if kaijin { parts.append("怪人特効") }
        return parts.isEmpty ? "この形態に適用する補正なし" : parts.joined(separator: " · ")
    }
}
