import Foundation

struct EvolutionMaterial: Decodable {
    let name: String
    let isCatfruit: Bool
    let iconName: String
}

struct EvolutionIngredient: Decodable, Identifiable {
    let itemID: Int
    let count: Int
    var id: Int { itemID }
}

struct EvolutionRequirement: Decodable {
    let items: [EvolutionIngredient]
}

struct EvolutionSupport: Decodable {
    let version: Int
    let catalogVersion: String
    let materials: [String: EvolutionMaterial]
    let requirements: [String: EvolutionRequirement]
    static let empty = EvolutionSupport(version: 1, catalogVersion: "", materials: [:], requirements: [:])

    func material(_ ingredient: EvolutionIngredient) -> EvolutionMaterial? { materials[String(ingredient.itemID)] }

    func requirement(for entry: Entry) -> EvolutionRequirement? {
        guard entry.form.number >= 3, let recipe = requirements[entry.id], !recipe.items.isEmpty,
              Set(recipe.items.map(\.itemID)).count == recipe.items.count,
              recipe.items.allSatisfy({ $0.count > 0 && material($0) != nil }),
              recipe.items.contains(where: { material($0)?.isCatfruit == true }) else { return nil }
        return recipe
    }
}
