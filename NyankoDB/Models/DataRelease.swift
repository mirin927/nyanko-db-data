import Foundation
import CryptoKit

struct DataRelease: Codable, Equatable {
    struct File: Codable, Equatable { let path: String; let bytes: Int; let sha256: String }
    struct Picture: Codable, Equatable { let bytes: Int; let sha256: String; let pack: String }
    let formatVersion: Int
    let minimumAppBuild: Int
    let sequence: Int64
    let id: String
    let version: String
    let publishedAt: String
    let sourceRevision: String
    let files: [File]
    let images: [String: Picture]
    static let requiredData = Set(["catalog", "search-index", "enemy-catalog", "enemy-search-index", "stage-catalog", "stage-search-index", "combo-catalog", "combo-search-index", "talent-support", "evolution-support", "orb-support"].map { "data/\($0).json" })
    func validate(appBuild: Int) throws {
        guard formatVersion == 1, minimumAppBuild <= appBuild else { throw DataUpdateError.appUpdateRequired }
        guard minimumAppBuild > 0, sequence >= 0, !version.isEmpty, version.count <= 100,
              sourceRevision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              id.range(of: "^release-\(sequence)-[a-f0-9]{12}$", options: .regularExpression) != nil,
              files.count <= 300, images.count <= 12000, !images.isEmpty,
              Set(files.map(\.path)).count == files.count,
              Set(files.filter { $0.path.hasPrefix("data/") }.map(\.path)) == Self.requiredData,
              files.allSatisfy({ file in
                  (Self.requiredData.contains(file.path) || file.path.range(of: "^packs/[a-f0-9]{2}\\.json$", options: .regularExpression) != nil) &&
                  file.bytes > 0 && file.bytes <= 40_000_000 && Self.validDigest(file.sha256)
              }), files.reduce(Int64(0), { $0 + Int64($1.bytes) }) <= 250_000_000,
              images.allSatisfy({ name, picture in
                  name.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil && picture.bytes > 0 && picture.bytes <= 2_000_000 &&
                  Self.validDigest(picture.sha256) && files.contains { $0.path == picture.pack && $0.path.hasPrefix("packs/") }
              }), images.values.reduce(Int64(0), { $0 + Int64($1.bytes) }) <= 64_000_000 else { throw DataUpdateError.invalidRelease }
    }
    static func validDigest(_ digest: String) -> Bool { digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func verify(_ data: Data, file: File) throws {
        guard data.count == file.bytes, digest(data) == file.sha256 else { throw DataUpdateError.corruptDownload }
    }
    static func isPNG(_ data: Data) -> Bool {
        guard data.count >= 33, Array(data.prefix(8)) == [137,80,78,71,13,10,26,10], String(data: data[12..<16], encoding: .ascii) == "IHDR" else { return false }
        func dimension(_ start: Int) -> UInt32 { data[start..<start+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        return (1...4096).contains(dimension(16)) && (1...4096).contains(dimension(20))
    }
    static func endpoint(_ text: String, allowLocalHTTP: Bool = false) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.scheme == "https" || (allowLocalHTTP && url.scheme == "http" && ["127.0.0.1", "localhost"].contains(host)) else { throw DataUpdateError.invalidEndpoint }
        return url
    }
}

enum DataUpdateError: Error, LocalizedError {
    case invalidEndpoint, invalidRelease, corruptDownload, incompatibleData, appUpdateRequired, olderRelease, network, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "配信先のHTTPS URLを確認してください。"
        case .invalidRelease: "更新データの形式を確認できませんでした。"
        case .corruptDownload: "ダウンロードしたデータを確認できませんでした。"
        case .incompatibleData: "更新データの組み合わせを確認できませんでした。"
        case .appUpdateRequired: "このデータには新しいアプリが必要です。"
        case .olderRelease: "現在より古いデータのため、更新しませんでした。"
        case .network: "配信先に接続できませんでした。"
        case .tooLarge: "更新データが大きすぎるため、更新しませんでした。"
        }
    }
}

/// One consistent library, constructed off the UI thread before publishing an update.
struct DataLibrary {
    let characters: CatalogRepository
    let enemies: EnemyRepository
    let stages: StageRepository
    let combos: ComboRepository
    let orbs: OrbSupport
    static func load(directory: URL, release: DataRelease? = nil) throws -> Self {
        func decode<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            try JSONDecoder().decode(type, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
        }
        let cats = try decode("catalog", as: Catalog.self)
        let enemies = try decode("enemy-catalog", as: EnemyCatalog.self)
        let stages = try decode("stage-catalog", as: StageCatalog.self)
        let talent = try decode("talent-support", as: TalentSupport.self)
        let evolution = try decode("evolution-support", as: EvolutionSupport.self)
        let orbs = try decode("orb-support", as: OrbSupport.self)
        let combos = try decode("combo-catalog", as: ComboCatalog.self)
        func names(_ file: String, originals: Set<String>) throws -> [String: SearchName] {
            let index = try decode(file, as: [String: SearchName].self)
            guard originals.isSubset(of: Set(index.keys)), index.allSatisfy({ key, value in
                value.original == key && value == SearchName(original: key, readings: value.readings, source: value.readingSource)
            }) else { throw DataUpdateError.incompatibleData }
            return index
        }
        guard !cats.units.isEmpty, cats.units.count <= 30000, Set(cats.units.map(\.id)).count == cats.units.count,
              cats.units.allSatisfy({ unit in unit.id >= 0 && (0...5).contains(unit.rarity) && !unit.forms.isEmpty && unit.forms.count <= 4 &&
                  Set(unit.forms.map(\.form)).count == unit.forms.count && unit.forms.allSatisfy { ["f","c","s","u"].contains($0.form) && !$0.name.isEmpty && $0.data.count >= 14 && $0.data.count <= 256 && $0.freq > 0 } }),
              !enemies.enemies.isEmpty, enemies.enemies.count <= 30000, Set(enemies.enemies.map(\.id)).count == enemies.enemies.count,
              enemies.enemies.allSatisfy({ $0.id >= 0 && !$0.name.isEmpty && $0.data.count >= 14 && $0.data.count <= 256 && $0.freq > 0 }),
              stages.version == enemies.version, stages.stages.count <= 100000, !stages.stages.isEmpty,
              Set(stages.stages.map(\.id)).count == stages.stages.count,
              stages.stages.allSatisfy({ stage in !stage.name.isEmpty && !stage.mapName.isEmpty && stage.stars.count <= 4 && !stage.stars.isEmpty &&
                  stage.stars.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 100000 } && stage.spawns.count <= 1000 &&
                  stage.spawns.allSatisfy { $0.count == 14 && $0.allSatisfy { $0.isFinite && abs($0) <= 1_000_000_000 } } }),
              talent.version == 1, evolution.version == 1, orbs.version == 1,
              talent.catalogVersion == cats.version, evolution.catalogVersion == cats.version, orbs.catalogVersion == cats.version,
              !orbs.validated(for: cats).orbs.isEmpty,
              [cats.source,enemies.source,stages.source].allSatisfy({ (try? DataRelease.endpoint($0)) != nil }) else { throw DataUpdateError.incompatibleData }
        let repository = CatalogRepository(catalog: cats, searchNames: try names("search-index", originals: Set(cats.units.flatMap { $0.forms.map(\.name) })), talentSupport: talent, evolutionSupport: evolution)
        // Unknown effect IDs remain visible as unsupported; broken/missing slots must
        // never replace a working library with a catalog that silently loses talents.
        guard repository.entries.allSatisfy({ entry in
            let form = entry.form, decoded = repository.talents(for: entry)
            guard form.hasValidTalentLayout else { return false }
            let raw = form.allTalentData
            let expected = raw.isEmpty ? 0 : stride(from: 1, to: raw.count, by: 14).filter { raw[$0] > 0 }.count
            return decoded.count == expected && (form.talent == 0 || !decoded.isEmpty) &&
                (form.superTalent == 0 || decoded.contains(where: \.isSuper)) &&
                decoded.allSatisfy { $0.cost(to: $0.maxLevel) != nil && $0.description != "詳細未取得" }
        }) else { throw DataUpdateError.incompatibleData }
        let enemyRepo = EnemyRepository(catalog: enemies, searchNames: try names("enemy-search-index", originals: Set(enemies.enemies.map(\.name))))
        let stageRepo = StageRepository(catalog: stages, searchNames: try names("stage-search-index", originals: Set(stages.stages.flatMap { [$0.name,$0.mapName] })))
        let comboRepo = ComboRepository(catalog: combos, characters: cats, searchNames: try names("combo-search-index", originals: Set(combos.combos.map(\.name))))
        guard comboRepo.loadError == nil else { throw DataUpdateError.incompatibleData }
        if let release {
            let required = Set(repository.entries.map(\.imageName) + enemies.enemies.map(\.imageName) + orbs.orbs.map(\.iconName) + evolution.materials.values.map(\.iconName))
            guard required.isSubset(of: Set(release.images.keys)) else { throw DataUpdateError.incompatibleData }
        }
        return Self(characters: repository, enemies: enemyRepo, stages: stageRepo, combos: comboRepo, orbs: orbs)
    }
}
