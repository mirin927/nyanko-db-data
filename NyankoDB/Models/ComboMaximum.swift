import Foundation

struct ComboMaximumTeam: Identifiable, Equatable {
    let members: [ComboMember]
    let combos: [NyanCombo]
    var id: String { members.map { "\($0.unitID)-\($0.minimumForm)" }.joined(separator: ",") }
}

struct ComboMaximum: Identifiable {
    let effect: ComboChoice
    /// Empty means the ordinary scope; restricted results also include ordinary
    /// combos, since their bonuses apply to the restricted characters as well.
    let scope: String
    let value: Int
    let teams: [ComboMaximumTeam]
    let candidateCount: Int
    var id: String { "\(effect.id):\(scope)" }
    var amount: String {
        switch effect.id {
        case 4: return "初期レベル +\(value)"
        case 5: return "初期所持金 +\(value)円"
        case 7: return "チャージ \(value / 30)秒短縮"
        case 11: return "研究力補正 +\(value)%"
        case 22, 23, 25, 26, 28: return teams.first?.combos.first?.amount ?? "効果を付与"
        case 24: return "発動率 +\(value)ポイント"
        case 27: return "生産コスト \(value)%割引"
        default: return "+\(value)%"
        }
    }
    var note: String {
        switch effect.id {
        case 3: return "初期ゲージは最大100%です。"
        case 4: return "初期レベルは最大8。ネコボン使用時はネコボンが優先されます。"
        case 7: return "コンボの短縮量の合計。実際の短縮はチャージ時間の下限までです。"
        case 11: return "研究力補正の合計。短縮量は研究力・お宝により変わり、再生産は最短2秒です。"
        default: return teams.first?.combos.first?.note ?? ""
        }
    }
}

/// Exact search over unions of combo members, rather than all 5-character
/// subsets of the character database. Every useful team is such a union:
/// removing characters that activate no target combo cannot lower its score.
struct ComboMaximumSolver {
    let catalog: ComboCatalog

    func solve(candidateLimit: Int = 5) -> [ComboMaximum] {
        catalog.effects.flatMap { effect -> [ComboMaximum] in
            let combos = catalog.combos.filter { $0.effectID == effect.id }
            let scopes = Set(combos.map(\.scope)).sorted()
            return scopes.compactMap { scope in
                solve(effect: effect, scope: scope,
                      combos: combos.filter { $0.scope.isEmpty || $0.scope == scope },
                      candidateLimit: max(1, candidateLimit))
            }
        }
    }

    private func solve(effect: ComboChoice, scope: String, combos: [NyanCombo], candidateLimit: Int) -> ComboMaximum? {
        let definitions = combos.sorted { $0.id < $1.id }
        guard !definitions.isEmpty else { return nil }
        let units = definitions.map { Set($0.members.map(\.unitID)) }
        var visited: Set<[Int]> = []
        var bestValue = -1
        var fewestSlots = 6
        var bestTeams: [[Int]] = []
        var candidateCount = 0

        func search(_ team: Set<Int>) {
            guard !Task.isCancelled else { return }
            let key = team.sorted()
            guard visited.insert(key).inserted else { return }
            let active = definitions.indices.filter { units[$0].isSubset(of: team) }
            let raw = active.reduce(0) { $0 + contribution(definitions[$1]) }
            let value: Int
            switch effect.id {
            case 3: value = min(100, raw) // Initial cannon gauge cannot exceed full.
            case 4: value = min(7, raw)   // Worker starts at level 1, max level 8.
            case 25, 26, 28: value = min(1, raw) // Granted abilities do not stack.
            default: value = raw
            }
            if !team.isEmpty && (value > bestValue || (value == bestValue && team.count < fewestSlots)) {
                bestValue = value; fewestSlots = team.count
                bestTeams = []; candidateCount = 0
            }
            if !team.isEmpty && value == bestValue && team.count == fewestSlots {
                candidateCount += 1
                bestTeams.append(key)
                bestTeams.sort { $0.lexicographicallyPrecedes($1) }
                if bestTeams.count > candidateLimit { bestTeams.removeLast() }
            }
            for members in units {
                let merged = team.union(members)
                if merged.count <= 5 && merged.count > team.count { search(merged) }
            }
        }
        search([])
        guard bestValue > 0 else { return nil }
        let teams = bestTeams.map { ids -> ComboMaximumTeam in
            let active = definitions.filter { Set($0.members.map(\.unitID)).isSubset(of: Set(ids)) }
            // Later forms preserve combo eligibility. Show the lowest form that
            // satisfies every target combo activated by this set of characters.
            let members = ids.map { id in
                ComboMember(unitID: id, minimumForm: active.flatMap(\.members).filter { $0.unitID == id }.map(\.minimumForm).max() ?? 1)
            }
            return ComboMaximumTeam(members: members, combos: active)
        }
        return ComboMaximum(effect: effect, scope: scope, value: bestValue, teams: teams, candidateCount: candidateCount)
    }

    private func contribution(_ combo: NyanCombo) -> Int {
        if combo.effectID == 7 {
            // Source values 20/30/40 are not durations. Verified tier amounts
            // are 150/300/450 frames; sum those when optimizing charge time.
            return [0: 150, 1: 300, 2: 450][combo.tierID] ?? 0
        }
        if [25, 26, 28].contains(combo.effectID) { return 1 }
        return max(0, combo.effectValue)
    }

    func activatedCombos(in team: ComboMaximumTeam) -> [NyanCombo] {
        let forms = Dictionary(uniqueKeysWithValues: team.members.map { ($0.unitID, $0.minimumForm) })
        return catalog.combos.filter { combo in
            combo.members.allSatisfy { (forms[$0.unitID] ?? 0) >= $0.minimumForm }
        }.sorted { $0.id < $1.id }
    }
}
