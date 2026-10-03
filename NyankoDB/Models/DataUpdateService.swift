import Foundation

struct InstalledData {
    let release: DataRelease
    let library: DataLibrary
    let directory: URL
    var imagesDirectory: URL { directory.appendingPathComponent("images") }
}

/// Builds an entire verified snapshot before atomically changing the active pointer.
actor DataUpdateService {
    typealias Fetch = @Sendable (URL, Int) async throws -> Data
    struct Pointer: Codable { let current: String; let previous: String? }
    let root: URL
    let bundledData: URL
    let baseline: DataRelease
    let appBuild: Int
    let fetch: Fetch
    private var busy = false
    init(root: URL, bundledData: URL, baseline: DataRelease, appBuild: Int, fetch: @escaping Fetch = { url, maximum in try await DataUpdateService.download(url, maximum: maximum) }) {
        self.root = root; self.bundledData = bundledData; self.baseline = baseline; self.appBuild = appBuild; self.fetch = fetch
    }
    static func readInstalled(root: URL, baseline: DataRelease, appBuild: Int) -> InstalledData? {
        guard let bytes = try? Data(contentsOf: root.appendingPathComponent("current.json")),
              let pointer = try? JSONDecoder().decode(Pointer.self, from: bytes) else { return nil }
        for id in [pointer.current, pointer.previous].compactMap({ $0 }) {
            guard id.range(of: "^release-[0-9]+-[a-f0-9]{12}$", options: .regularExpression) != nil else { continue }
            let directory = root.appendingPathComponent(id)
            if let snapshot = try? loadInstalled(directory: directory, baseline: baseline, appBuild: appBuild), snapshot.release.id == id { return snapshot }
        }
        return nil
    }
    static func loadInstalled(directory: URL, baseline: DataRelease, appBuild: Int) throws -> InstalledData {
        let release = try JSONDecoder().decode(DataRelease.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        try release.validate(appBuild: appBuild)
        for file in release.files where file.path.hasPrefix("data/") {
            try DataRelease.verify(Data(contentsOf: directory.appendingPathComponent(file.path)), file: file)
        }
        for (name, image) in release.images where baseline.images[name]?.sha256 != image.sha256 {
            let data = try Data(contentsOf: directory.appendingPathComponent("images/\(name).png"))
            guard data.count == image.bytes, DataRelease.digest(data) == image.sha256, DataRelease.isPNG(data) else { throw DataUpdateError.corruptDownload }
        }
        return InstalledData(release: release, library: try DataLibrary.load(directory: directory.appendingPathComponent("data"), release: release), directory: directory)
    }
    func check(endpoint: URL) async throws -> InstalledData? {
        guard !busy else { return nil }; busy = true; defer { busy = false }
        let raw = try await fetch(endpoint, 2_000_000)
        guard raw.count <= 2_000_000 else { throw DataUpdateError.tooLarge }
        let release = try JSONDecoder().decode(DataRelease.self, from: raw)
        try release.validate(appBuild: appBuild)
        let installed = Self.readInstalled(root: root, baseline: baseline, appBuild: appBuild)
        let current = installed?.release ?? baseline
        if release.id == current.id { return nil }
        guard release.sequence > current.sequence else { throw DataUpdateError.olderRelease }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString)")
        try manager.createDirectory(at: staging.appendingPathComponent("images"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let base = endpoint.deletingLastPathComponent().appendingPathComponent(release.id)
        for file in release.files {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(file.path)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let baselineFile = baseline.files.first { $0.path == file.path && $0.sha256 == file.sha256 }
            // Identical bundled image packs already exist in the compiled asset catalog.
            if file.path.hasPrefix("packs/"), baselineFile != nil { continue }
            let local: URL?
            if let installed, installed.release.files.contains(where: { $0.path == file.path && $0.sha256 == file.sha256 }) {
                local = installed.directory.appendingPathComponent(file.path)
            } else if baselineFile != nil, file.path.hasPrefix("data/") {
                local = bundledData.appendingPathComponent(destination.lastPathComponent)
            } else { local = nil }
            let data: Data
            if let local, let cached = try? Data(contentsOf: local), (try? DataRelease.verify(cached, file: file)) != nil { data = cached }
            else { data = try await fetch(base.appendingPathComponent(file.path), file.bytes) }
            try DataRelease.verify(data, file: file)
            try data.write(to: destination)
            if file.path.hasPrefix("packs/") {
                let pack = try JSONDecoder().decode([String: String].self, from: data)
                let expected = release.images.filter { $0.value.pack == file.path }
                guard Set(pack.keys) == Set(expected.keys) else { throw DataUpdateError.corruptDownload }
                for (name, picture) in expected {
                    guard let encoded = pack[name], let png = Data(base64Encoded: encoded), png.count == picture.bytes,
                          DataRelease.digest(png) == picture.sha256, DataRelease.isPNG(png) else { throw DataUpdateError.corruptDownload }
                    if baseline.images[name]?.sha256 != picture.sha256 { try png.write(to: staging.appendingPathComponent("images/\(name).png")) }
                }
            }
        }
        try raw.write(to: staging.appendingPathComponent("manifest.json"))
        let checked = try Self.loadInstalled(directory: staging, baseline: baseline, appBuild: appBuild)
        try Task.checkCancellation()
        let destination = root.appendingPathComponent(release.id)
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: staging, to: destination)
        let pointer = Pointer(current: release.id, previous: installed?.release.id)
        try JSONEncoder().encode(pointer).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        // Keep one known-good previous snapshot. Incomplete work never becomes current.
        for url in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if (url.lastPathComponent.hasPrefix("release-") && ![pointer.current, pointer.previous].contains(url.lastPathComponent)) || url.lastPathComponent.hasPrefix("staging-") {
                try? manager.removeItem(at: url)
            }
        }
        return InstalledData(release: release, library: checked.library, directory: destination)
    }
    static func download(_ url: URL, maximum: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let final = response.url,
              final.scheme == url.scheme, final.host == url.host, final.port == url.port else { throw DataUpdateError.network }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maximum else { throw DataUpdateError.tooLarge }
        return try Data(contentsOf: temporary)
    }
}
