import Foundation

struct FeatureFact: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }
}

extension Ability {
    static func seconds(_ frames: Int) -> String {
        let value = Double(frames) / 30
        let text = String(format: "%.2f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return text + "秒"
    }
    /// Attribute treasures extend control effects only against their corresponding traits.
    func durationFacts(_ form: UnitForm, frames: Int) -> [FeatureFact] {
        let treasure = form.traits.filter(\.hasAttributeTreasure)
        let plain = form.traits.filter { !$0.hasAttributeTreasure }
        guard [.freeze,.slow,.weaken,.curse].contains(self), !treasure.isEmpty else {
            return [FeatureFact(label: "効果時間", value: Self.seconds(frames))]
        }
        let boosted = frames * 120 / 100
        if plain.isEmpty { return [FeatureFact(label: "効果時間（お宝MAX）", value: Self.seconds(boosted))] }
        return [FeatureFact(label: "時間：\(treasure.map(\.rawValue).joined(separator: "・"))", value: Self.seconds(boosted)),
                FeatureFact(label: "時間：\(plain.map(\.rawValue).joined(separator: "・"))", value: Self.seconds(frames))]
    }
    func facts(_ form: UnitForm) -> [FeatureFact] {
        let probability = FeatureFact(label: "発動確率", value: "\(form.value(index))%")
        let duration: Int? = switch self { case .freeze: 26; case .slow: 28; case .weaken: 38; case .curse: 93; case .dodge: 85; default: nil }
        if let duration {
            var result = [probability] + durationFacts(form, frames: form.value(duration))
            if self == .weaken { result.append(FeatureFact(label: "効果中の敵攻撃力", value: "\(form.value(39))%")) }
            return result
        }
        if category == .resistance {
            return [FeatureFact(label: "軽減率", value: "\(form.resistanceValues?[rawValue] ?? 0)%")]
        }
        switch self {
        case .wave,.miniWave:
            return [probability, FeatureFact(label: "波動レベル", value: "Lv.\(form.value(36))"),
                    FeatureFact(label: "波動の射程", value: String(format:"%.1f", 132.5 + Double(form.value(36)) * 200)),
                    FeatureFact(label: "ダメージ", value: self == .miniWave ? "通常攻撃の20%" : "通常攻撃の100%")]
        case .surge,.miniSurge:
            return [probability, FeatureFact(label: "烈波レベル", value: "Lv.\(form.value(89))"),
                    FeatureFact(label: "持続時間", value: Self.seconds(form.value(89) * 20)),
                    FeatureFact(label: "発生位置", value: "\(form.value(87) >> 2)〜\((form.value(87) >> 2) + (form.value(88) >> 2))"),
                    FeatureFact(label: "ダメージ", value: self == .miniSurge ? "1回あたり通常攻撃の20%" : "1回あたり通常攻撃の100%")]
        case .warp:
            return [probability, FeatureFact(label: "ワープ時間", value: Self.seconds(form.value(72))),
                    FeatureFact(label: "移動距離", value: "\(form.value(73))〜\(form.value(74))")]
        case .explosion:
            return [probability, FeatureFact(label: "発生位置", value: "\(form.value(114) >> 2)〜\((form.value(114) + form.value(115)) >> 2)")]
        case .savage:
            return [probability, FeatureFact(label: "発動時の攻撃力", value: "\(100 + form.value(83))%")]
        case .strengthen:
            return [FeatureFact(label: "発動条件", value: "残り体力\(form.value(40))%以下"), FeatureFact(label: "発動中の攻撃力", value: "\(100 + form.value(41))%")]
        case .metalKiller: return [FeatureFact(label: "追加ダメージ", value: "敵の現在体力の\(form.value(112))%")]
        case .critical: return [probability, FeatureFact(label: "ダメージ", value: "通常攻撃の2倍・メタルにも有効")]
        case .knockback,.survive,.barrier,.shield: return [probability]
        case .behemoth:
            var result = [FeatureFact(label: "与ダメージ", value: "2.5倍"), FeatureFact(label: "被ダメージ", value: "0.6倍")]
            if form.value(106) > 0 { result += [FeatureFact(label: "攻撃無効の確率", value: "\(form.value(106))%"), FeatureFact(label: "攻撃無効の時間", value: Self.seconds(form.value(107)))] }
            return result
        case .colossus: return [FeatureFact(label:"与ダメージ",value:"1.6倍"),FeatureFact(label:"被ダメージ",value:"0.7倍")]
        case .sage: return [FeatureFact(label:"与ダメージ",value:"1.2倍"),FeatureFact(label:"被ダメージ",value:"0.5倍"),FeatureFact(label:"妨害の時間",value:"70%軽減")]
        case .summon: return [FeatureFact(label:"召喚する精霊のID",value:"\(form.value(110))")]
        default: return []
        }
    }
    func badges(_ form: UnitForm) -> [String] {
        let f = facts(form)
        if let probability = f.first(where: { $0.label == "発動確率" }) {
            if [.wave,.miniWave].contains(self) { return [probability.value,"Lv.\(form.value(36))"] }
            if [.surge,.miniSurge].contains(self) {
                return [probability.value,"Lv.\(form.value(89))(\(Self.seconds(form.value(89) * 20)))"]
            }
            let time = f.filter { $0.label.contains("時間") }.map(\.value)
            if !time.isEmpty { return [probability.value, time.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator:"／")] }
            return [probability.value]
        }
        if category == .resistance { return ["\(form.resistanceValues?[rawValue] ?? 0)%"] }
        if self == .strengthen { return ["HP≤\(form.value(40))%","＋\(form.value(41))%"] }
        if self == .metalKiller { return ["\(form.value(112))%"] }
        return []
    }
    func explanation(_ form: UnitForm) -> String {
        let details = facts(form)
        if !details.isEmpty { return details.map { "\($0.label)：\($0.value)" }.joined(separator:"\n") }
        switch self {
        case .strong: return "対象属性に与えるダメージ1.5倍、被ダメージ1/2。対応するお宝MAX時は1.8倍、1/2.5。"
        case .massive: return "対象属性に与えるダメージ3倍。対応するお宝MAX時は4倍。"
        case .insaneDamage: return "対象属性に与えるダメージ5倍。対応するお宝MAX時は6倍。"
        case .resistant: return "対象属性から受けるダメージ1/4。対応するお宝MAX時は1/5。"
        case .tough: return "対象属性から受けるダメージ1/6。対応するお宝MAX時は1/7。"
        case .zombieKiller: return "このキャラで倒したゾンビの蘇生を防ぐ。"
        case .soul: return "ゾンビの潜伏・蘇生中の魂を攻撃できる。"
        case .extraMoney: return "敵撃破時のお金が2倍。"
        case .baseDestroyer: return "敵の城へのダメージが4倍。"
        case .attacksOnly: return "対象属性の敵と敵の城だけに攻撃する。"
        default: return category == .immunity ? "この効果を受けない。" : "\(rawValue)の特性を持つ。"
        }
    }
    func affectedHits(_ form: UnitForm) -> String? {
        let hits = [3,59,60].enumerated().filter { form.value($0.element) > 0 }
        guard hits.count > 1, form.data.count > 65, category != .immunity, category != .resistance else { return nil }
        let enabled = hits.filter { form.value(63 + $0.offset) > 0 }.map { "\($0.offset + 1)撃目" }
        return enabled.isEmpty ? nil : enabled.joined(separator:"・")
    }
}
