#!/usr/bin/env python3
"""Bundle per-form evolution materials without replacing the character catalog."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import argparse
import concurrent.futures
import csv
import hashlib
import io
import json
import pathlib
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--reference-directory', type=pathlib.Path)
parser.add_argument('--skip-icons', action='store_true')
args = parser.parse_args()
revision = SOURCE_REVISION
base = f'https://raw.githubusercontent.com/JarJarBlink/JDB/{revision}/'
sources = {name: base + 'static/data/DataLocal/' + name for name in ['unitbuy.csv', 'Gatyaitembuy.csv', 'Matatabi.tsv']}

def download(name, url):
    local = args.reference_directory / name if args.reference_directory else None
    if local and local.exists():
        return local.read_bytes()
    return open_source(url, timeout=30).read()

raw = {name: download(name, url) for name, url in sources.items()}
buy = list(csv.reader(io.StringIO(raw['unitbuy.csv'].decode('utf-8-sig'))))
items = {int(r['stageDropItemID']): r['comment'] for r in csv.DictReader(io.StringIO(raw['Gatyaitembuy.csv'].decode('utf-8-sig')))}
# Group 9 contains behemoth stones/crystals, which share this game's material table.
fruit_ids = {int(r['gatyaID']) for r in csv.DictReader(io.StringIO(raw['Matatabi.tsv'].decode('utf-8-sig')), delimiter='\t') if int(r['group']) != 9}
catalog = json.loads((root / 'NyankoDB/Resources/catalog.json').read_text())
requirements = {}
used_items = set()
for unit in catalog['units']:
    row = [int(v) for v in buy[unit['id']]]
    if len(row) < 52 or row[50] != unit['maxBase'] or row[51] != unit['maxPlus']:
        raise ValueError(f"Catalog snapshot mismatch: {unit['id']}")
    for form in unit['forms']:
        if form['form'] not in ['s', 'u']:
            continue
        # Five item/count pairs for each destination form; never combine both recipes.
        start = 28 if form['form'] == 's' else 39
        ingredients = []
        for i in range(start, start + 10, 2):
            item_id, count = row[i:i + 2]
            if count < 0 or (count > 0 and item_id not in items):
                raise ValueError(f"Invalid ingredient: {unit['id']}-{form['form']}")
            if count > 0:
                ingredients.append({'itemID': item_id, 'count': count})
        if not any(i['itemID'] in fruit_ids for i in ingredients):
            continue
        if len({i['itemID'] for i in ingredients}) != len(ingredients):
            raise ValueError('Duplicate evolution ingredient')
        requirements[f"{unit['id']}-{form['form']}"] = {'items': ingredients}
        used_items.update(i['itemID'] for i in ingredients)

materials = {str(i): {'name': items[i], 'isCatfruit': i in fruit_ids, 'iconName': f'evolution_{i}',
                     'iconSource': base + f'static/img/ability_icon/gatyaitemD_{i:02}_f.png'} for i in sorted(used_items)}

def import_icon(item):
    key, material = item
    data = download(f'item-{key}.png', material['iconSource'])
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError(f'Invalid icon: {key}')
    destination = root / 'NyankoDB/Assets.xcassets' / (material['iconName'] + '.imageset')
    destination.mkdir(exist_ok=True)
    (destination / 'icon.png').write_bytes(data)
    (destination / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'icon.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}) + '\n')

if not args.skip_icons:
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(import_icon, materials.items()))
output = {'version': 1, 'catalogVersion': catalog['version'], 'jdbRevision': revision,
          'materials': materials, 'requirements': requirements,
          'sources': {name: {'url': sources[name], 'sha256': hashlib.sha256(data).hexdigest()} for name, data in raw.items()}}
path = root / 'NyankoDB/Resources/evolution-support.json'
temporary = path.with_suffix('.json.tmp')
temporary.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
temporary.replace(path)
print(f'Bundled {len(requirements)} per-form recipes and {len(materials)} materials')
