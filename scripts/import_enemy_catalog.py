#!/usr/bin/env python3
"""Import the pinned JDB enemy database and cache its unmodified PNG assets."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import time
import urllib.request

REVISION = SOURCE_REVISION
BASE = f"https://raw.githubusercontent.com/JarJarBlink/JDB/{REVISION}/"
ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "NyankoDB/Resources"
ASSETS = ROOT / "NyankoDB/Assets.xcassets"
ICONS = {
    "enemyAbility_barrier": "Barrier.png",
    "enemyAbility_burrow": "Burrow.png",
    "enemyAbility_revive": "Revive.png",
    "enemyAbility_shield": "DemonShield.png",
    "enemyAbility_deathSurge": "DeathSurge.png",
    "enemyAbility_toxic": "BCPoison.png",
    "enemyAbility_productionDelay": "CD_time_plus.png",
    "enemyTrait_colossus": "ja/Baron.png",
    "enemyTrait_behemoth": "ja/Beast.png",
    "enemyTrait_sage": "ja/wiser.png",
    "enemyTrait_kaijin": "ja/superman.png",
}

def fetch(path):
    for attempt in range(3):
        try:
            with open_source(BASE + path, timeout=45) as response:
                return response.read()
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")

def image(item):
    name, source = item
    folder = ASSETS / f"{name}.imageset"
    target = folder / "image.png"
    if not target.exists() or __import__("os").environ.get("JDB_SOURCE"):
        data = fetch(source)
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"Not a PNG: {source}")
        folder.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    write_json(folder / "Contents.json", {
        "images": [{"filename": "image.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })
    return {"asset": name, "source": BASE + source,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, help="Previously downloaded search_data1_e_ja.js")
    parser.add_argument("--fetch-images", action="store_true")
    args = parser.parse_args()
    source_path = "static/js/t_unit/search_data1_e_ja.js"
    raw = args.source.read_bytes() if args.source else fetch(source_path)
    text = raw.decode("utf-8")
    records = json.JSONDecoder().raw_decode(text[text.index("=") + 1:].lstrip())[0]
    enemies = [{"id": e["id"], "name": e["name"], "data": e["data"], "freq": e["freq"]}
               for e in records if e["valid"] and e["name"].strip()
               and e["name"] != "ダミー" and len(e["data"]) >= 14]
    enemies.sort(key=lambda e: e["id"])
    assert len({e["id"] for e in enemies}) == len(enemies)
    write_json(RESOURCES / "enemy-catalog.json", {
        "version": REVISION[:12], "revision": REVISION,
        "source": "https://jarjarblink.github.io/JDB/tunit_search.html?cc=ja",
        "sourceData": BASE + source_path,
        "sourceSHA256": hashlib.sha256(raw).hexdigest(), "enemies": enemies,
    })
    print(f"Imported {len(enemies)} enemies; excluded invalid records and named dummy placeholders.", flush=True)
    if args.fetch_images:
        items = [(f"enemy{e['id']:03}", f"static/img/enemy_icon/enemy_icon_{e['id']:03}.png") for e in enemies]
        items += [(name, f"static/img/ability_icon/{file}") for name, file in ICONS.items()]
        manifest = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            for result in pool.map(image, items):
                manifest.append(result)
                if len(manifest) % 100 == 0:
                    print(f"Cached {len(manifest)}/{len(items)} assets", flush=True)
        write_json(RESOURCES / "enemy-icon-sources.json", {"revision": REVISION, "images": manifest})
        print(f"Cached all {len(manifest)} assets", flush=True)

if __name__ == "__main__":
    main()
