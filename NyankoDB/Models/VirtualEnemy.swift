import Foundation

/// Deterministic attribute modifiers, without probabilistic attacks or control effects.
struct VirtualEnemyScenario: Identifiable {
    enum Kind {
        case attribute, special, combined
        var title: String {
            switch self {
            case .attribute: "属性の効果のみ"
            case .special: "特効のみ"
            case .combined: "属性の効果＋特効"
            }
        }
    }
    let id: String
    let kind: Kind
    let traits: [Trait]
    let features: [Ability]
    let attackMultiplier: Double
    let damageReceivedMultiplier: Double
    var flatAttackBonus: Double = 0
    var hasOrbBonus = false
    var enemyLabel: String? = nil

    func adjusted(_ base: Stats) -> VirtualEnemyStats {
        VirtualEnemyStats(attack: Double(base.attack) * attackMultiplier + flatAttackBonus,
                          dps: base.dps * attackMultiplier + (base.frequency > 0 ? flatAttackBonus / base.frequency : 0),
                          effectiveHP: Double(base.hp) / damageReceivedMultiplier)
    }
}

struct VirtualEnemyStats {
    let attack: Double
    let dps: Double
    let effectiveHP: Double
    static func formatted(_ value: Double) -> String {
        Int(floor(value + 0.000001)).formatted(.number.locale(Locale(identifier: "en_US")))
    }
}

extension Trait {
    var hasAttributeTreasure: Bool {
        [.red, .floating, .black, .metal, .angel, .alien, .zombie].contains(self)
    }
}

extension UnitForm {
    var hasVirtualEnemyModifiers: Bool {
        abilities.contains { [.strong, .massive, .insaneDamage, .resistant, .tough,
                              .colossus, .behemoth, .sage, .witchKiller, .evaKiller].contains($0) }
    }

    func virtualEnemyScenarios(attributeTreasureMax: Bool, orbs: [TalentOrb] = [], orbBaseAttack: Int = 0,
                               combos: ComboStatBonuses = .none, includeNormal: Bool = false) -> [VirtualEnemyScenario] {
        let present = Set(abilities)
        // Attack and defense have independent precedence. Effects on the same axis
        // are not multiplied by one another; multiple target attributes are OR.
        let attackEffect: Ability? = [.massive, .insaneDamage, .strong].first { present.contains($0) }
        let defenseEffect: Ability? = [.resistant, .tough, .strong].first { present.contains($0) }
        let effectFeatures = [attackEffect, defenseEffect].compactMap { $0 }
            .reduce(into: [Ability]()) { if !$0.contains($1) { $0.append($1) } }
        var targets: [VirtualEnemyScenario] = []
        let ordinaryTraits = traits.filter {
            !($0 == .witch && present.contains(.witchKiller)) && !($0 == .eva && present.contains(.evaKiller))
        }
        if !effectFeatures.isEmpty {
            let groups: [(String, [Trait], Bool)] = attributeTreasureMax
                ? [("treasure", ordinaryTraits.filter(\.hasAttributeTreasure), true),
                   ("plain", ordinaryTraits.filter { !$0.hasAttributeTreasure }, false)]
                : [("plain", ordinaryTraits, false)]
            for (key, targetTraits, treasure) in groups where !targetTraits.isEmpty {
                let attack: Double = switch attackEffect {
                case .massive: (treasure ? 4 : 3) * (1 + Double(combos.massivePercent) / 100)
                case .insaneDamage: treasure ? 6 : 5
                case .strong: (treasure ? 1.8 : 1.5) * (1 + Double(combos.strongPercent) / 100)
                default: 1
                }
                let received: Double = switch defenseEffect {
                case .resistant: (treasure ? 1.0 / 5 : 1.0 / 4) * max(0.01, 1 - Double(combos.resistantPercent) / 100)
                case .tough: treasure ? 1.0 / 7 : 1.0 / 6
                case .strong: (treasure ? 1.0 / 2.5 : 1.0 / 2) * max(0.01, 1 - Double(combos.strongPercent) / 100)
                default: 1
                }
                targets.append(VirtualEnemyScenario(id: key, kind: .attribute, traits: targetTraits,
                    features: effectFeatures, attackMultiplier: attack, damageReceivedMultiplier: received))
            }
        }
        // Collaboration killers use their own fixed target multipliers.
        for (feature, trait, attack, received) in [(Ability.witchKiller, Trait.witch, 5.0, 0.1),
                                                   (.evaKiller, .eva, 5.0, 0.2)] where present.contains(feature) {
            targets.append(VirtualEnemyScenario(id: String(describing: trait), kind: .attribute,
                traits: [trait], features: [feature],
                attackMultiplier: attack * (1 + Double(feature == .witchKiller ? combos.witchPercent : combos.evaPercent) / 100),
                damageReceivedMultiplier: received / (1 + Double(feature == .witchKiller ? combos.witchPercent : combos.evaPercent) / 100)))
        }
        // An ordinary damage orb can target an attribute the character has no
        // innate effect against. An attacks-only character still cannot attack it.
        let orbTraits = Set(orbs.filter { $0.effect < 5 }.compactMap(\.trait))
        for trait in Trait.allCases where orbTraits.contains(trait) && !targets.contains(where: { $0.traits.contains(trait) }) {
            targets.append(VirtualEnemyScenario(id: "orb-\(trait.id)", kind: .attribute, traits: [trait], features: [],
                attackMultiplier: present.contains(.attacksOnly) && !traits.contains(trait) ? 0 : 1, damageReceivedMultiplier: 1))
        }
        var result = targets
        // Each special enemy class is a separate case. Never multiply different
        // special classes together. They do stack with a matching attribute effect.
        for (feature, attack, received) in [(Ability.colossus, 1.6, 0.7),
                                            (.behemoth, 2.5, 0.6), (.sage, 1.2, 0.5)] where present.contains(feature) {
            let key = String(describing: feature)
            result.append(VirtualEnemyScenario(id: key, kind: .special, traits: [], features: [feature],
                attackMultiplier: present.contains(.attacksOnly) ? 0 : attack, damageReceivedMultiplier: received))
            for target in targets {
                result.append(VirtualEnemyScenario(id: "\(target.id)-\(key)", kind: .combined,
                    traits: target.traits, features: target.features + [feature],
                    attackMultiplier: target.attackMultiplier * attack,
                    damageReceivedMultiplier: target.damageReceivedMultiplier * received))
            }
        }
        if combos.kaijin {
            result.append(VirtualEnemyScenario(id: "kaijin", kind: .special, traits: [], features: [],
                attackMultiplier: present.contains(.attacksOnly) ? 0 : 25, damageReceivedMultiplier: 1.0 / 25, enemyLabel: "怪人"))
            for target in targets {
                result.append(VirtualEnemyScenario(id: "\(target.id)-kaijin", kind: .combined, traits: target.traits, features: target.features,
                    attackMultiplier: target.attackMultiplier * 25, damageReceivedMultiplier: target.damageReceivedMultiplier / 25, enemyLabel: "怪人"))
            }
        }
        if result.isEmpty && includeNormal {
            result.append(VirtualEnemyScenario(id: "normal", kind: .attribute, traits: present.contains(.attacksOnly) ? traits : [], features: [],
                attackMultiplier: 1, damageReceivedMultiplier: 1, enemyLabel: present.contains(.attacksOnly) ? "対象属性の敵" : "通常の敵"))
        }
        guard !orbTraits.isEmpty else { return result }
        return result.flatMap { scenario -> [VirtualEnemyScenario] in
            guard scenario.traits.contains(where: { orbTraits.contains($0) }) else { return [scenario] }
            // Split formerly shared attribute rows so a red orb never buffs black.
            let changed = scenario.traits.filter { orbTraits.contains($0) }
            let unchanged = scenario.traits.filter { !orbTraits.contains($0) }
            let groups = changed.map { [$0] } + (unchanged.isEmpty ? [] : [unchanged])
            return groups.map { targetTraits in
                let trait = targetTraits[0]
                let matching = orbs.filter { $0.trait == trait && $0.effect < 5 }
                func sum(_ effect: Int, _ index: Int = 0) -> Double {
                    Double(matching.filter { $0.effect == effect }.reduce(0) { $0 + ($1.values.indices.contains(index) ? $1.values[index] : 0) })
                }
                let special = scenario.features.reduce(1.0) { value, feature in
                    value * ([Ability.colossus: 1.6, .behemoth: 2.5, .sage: 1.2][feature] ?? 1)
                } * (scenario.enemyLabel == "怪人" ? 25 : 1)
                var attack = scenario.attackMultiplier
                var received = scenario.damageReceivedMultiplier * (1 - sum(1)/100)
                if scenario.features.contains(.strong) {
                    if attackEffect == .strong { attack += sum(2)/1000 * special }
                    if defenseEffect == .strong { received *= 1 - sum(2, 1)/100 }
                }
                if scenario.features.contains(.massive) && attackEffect == .massive { attack += sum(3)/300 * special }
                if scenario.features.contains(.resistant) && defenseEffect == .resistant { received *= 1 - sum(4)/100 }
                return VirtualEnemyScenario(id: scenario.traits.count > 1 ? "\(scenario.id)-\(matching.isEmpty ? "unchanged" : trait.id)" : scenario.id,
                    kind: scenario.kind, traits: targetTraits, features: scenario.features,
                    attackMultiplier: attack, damageReceivedMultiplier: received,
                    flatAttackBonus: attack > 0 ? Double(orbBaseAttack) * sum(0)/100 : 0,
                    hasOrbBonus: !matching.isEmpty, enemyLabel: scenario.enemyLabel)
            }
        }
    }
}
