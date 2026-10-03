import Foundation

extension Ability {
    var iconName: String { self == .explosionResist ? "orb_1225" : "ability_\(String(describing: self))" }
}

extension AttackType {
    var iconName: String { "attack_\(String(describing: self))" }
}

extension Trait {
    var iconName: String { "trait_\(String(describing: self))" }
}
