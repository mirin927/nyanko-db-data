#!/usr/bin/env python3
"""Regenerate the private offline catalog from JDB's public data snapshot."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import concurrent.futures
import csv
import datetime
import io
import json
import pathlib
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
base = SOURCE_BASE
paths = ['static/js/unit/search_data1_ja.js', 'static/data/DataLocal/unitlevel.csv', 'static/data/DataLocal/unitbuy.csv']

def read(path):
    with open_source(base + path, timeout=30) as response:
        return response.read().decode('utf-8-sig')

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
    js, levels, prices = list(executor.map(read, paths))
units = json.JSONDecoder().raw_decode(js[js.index('=') + 1:].lstrip())[0]
growth = list(csv.reader(io.StringIO(levels)))
buy = list(csv.reader(io.StringIO(prices)))
catalog = []
for unit in units:
    forms = [f for f in unit['forms'] if f['valid'] and f['name'].strip() and len(f['data']) >= 14]
    if not forms or unit['rarity'] is None:
        continue
    uid = unit['id']
    unit['forms'] = forms
    unit['growth'] = [int(v) for v in growth[uid]]
    unit['maxBase'] = max(1, int(buy[uid][50]))
    unit['maxPlus'] = max(0, int(buy[uid][51]))
    unit['eggPortraits'] = {}
    for code, column in [('f', 61), ('c', 62)]:
        egg = int(buy[uid][column])
        if egg >= 0 and any(f['form'] == code and 'タマゴ' in f['name'] for f in forms):
            unit['eggPortraits'][code] = egg
    catalog.append(unit)

stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).date().isoformat()
output = {'version': 'JDB-' + stamp, 'source': 'https://jarjarblink.github.io/JDB/unit_search.html?cc=ja', 'units': catalog}
path = root / 'NyankoDB/Resources/catalog.json'
temp = path.with_suffix('.json.tmp')
temp.write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':')))
temp.replace(path)
print(f'Imported {len(catalog)} units and {sum(len(u["forms"]) for u in catalog)} forms')
print('Run sh scripts/generate_search_index.sh and fetch_portraits.py afterwards, then review updated data and run tests before redistribution.')
