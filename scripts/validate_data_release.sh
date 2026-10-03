#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$(mktemp -d)"
trap 'rm -rf "$task_build"' EXIT
cat > "$task_build/main.swift" <<'SWIFT'
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let release = try JSONDecoder().decode(DataRelease.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
try release.validate(appBuild: release.minimumAppBuild)
let directory = root.appendingPathComponent(release.id)
for file in release.files { try DataRelease.verify(Data(contentsOf: directory.appendingPathComponent(file.path)), file: file) }
for file in release.files where file.path.hasPrefix("packs/") {
    let pack = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: directory.appendingPathComponent(file.path)))
    let expected = release.images.filter { $0.value.pack == file.path }
    guard Set(pack.keys) == Set(expected.keys) else { throw DataUpdateError.corruptDownload }
    for (name, picture) in expected {
        guard let encoded = pack[name], let png = Data(base64Encoded: encoded), png.count == picture.bytes,
              DataRelease.digest(png) == picture.sha256, DataRelease.isPNG(png) else { throw DataUpdateError.corruptDownload }
    }
}
let library = try DataLibrary.load(directory: directory.appendingPathComponent("data"), release: release)
print("Verified \(library.characters.catalog.units.count) characters, \(library.enemies.catalog.enemies.count) enemies, \(library.stages.catalog.stages.count) stages and \(release.images.count) images")
SWIFT
swiftc -O -module-cache-path "$task_build/modules" "$project_dir"/NyankoDB/Models/*.swift "$task_build/main.swift" -o "$task_build/validate"
"$task_build/validate" "$1"
