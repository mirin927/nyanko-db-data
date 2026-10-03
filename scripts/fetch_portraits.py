#!/usr/bin/env python3
"""Fetch the reference catalog's small portraits for offline, private use."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import concurrent.futures
import json
import pathlib
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
catalog = json.loads((root / 'NyankoDB/Resources/catalog.json').read_text())
assets = root / 'NyankoDB/Assets.xcassets'

def fetch(pair):
    uid, form = pair
    name = f'egg{uid:03}' if form == 'm' else f'unit{uid:03}_{form}'
    directory = assets / f'{name}.imageset'
    directory.mkdir(exist_ok=True)
    path = directory / 'portrait.png'
    if not path.exists() or __import__("os").environ.get("JDB_SOURCE"):
        url = SOURCE_BASE + f'static/img/unit_icon/uni{uid:03}_{form}00.png'
        with open_source(url, timeout=20) as response:
            data = response.read()
        if not data.startswith(b'\x89PNG'):
            raise ValueError(f'Invalid PNG: {name}')
        path.write_bytes(data)
    (directory / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': 'portrait.png', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}
    }))
    return name

pairs = [(u['id'], f['form']) for u in catalog['units'] for f in u['forms'] if f['form'] not in u.get('eggPortraits', {})]
pairs += sorted({(egg, 'm') for u in catalog['units'] for egg in u.get('eggPortraits', {}).values()})
failures = []
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
    futures = {executor.submit(fetch, pair): pair for pair in pairs}
    for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
        try:
            future.result()
        except Exception as error:
            failures.append((futures[future], str(error)))
        if index % 300 == 0:
            print(f'{index}/{len(pairs)} portraits processed', flush=True)
print(f'Finished: {len(pairs) - len(failures)} portraits; {len(failures)} unavailable', flush=True)
for pair, error in failures[:20]:
    print(pair, error)

if failures:
    raise RuntimeError("Missing portraits; refusing to publish incomplete data")
