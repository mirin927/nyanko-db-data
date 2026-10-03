#!/usr/bin/env python3
"""Bundle NP tables and animation timing without replacing the character catalog."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import argparse, concurrent.futures, csv, hashlib, io, json, pathlib, urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--reference-directory', type=pathlib.Path)
args = parser.parse_args()
# Keep related JDB tables/icons on one revision. Advance deliberately on data updates.
jdb_revision = SOURCE_REVISION
jdb = f'https://raw.githubusercontent.com/JarJarBlink/JDB/{jdb_revision}/'
sources = {
 'SkillLevel.csv': jdb + 'static/data/DataLocal/SkillLevel.csv',
 'SkillDescriptions.csv': jdb + 'static/data/resLocal_ja/SkillDescriptions.csv',
 'catstat.tsv': 'https://raw.githubusercontent.com/battlecatsinfo/battlecatsinfo.github.io/master/data/catstat.tsv',
}
def read(item):
 name, url = item
 local = args.reference_directory / name if args.reference_directory else None
 data = local.read_bytes() if local and local.exists() else open_source(url, timeout=30).read()
 return name, data
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
 raw = dict(pool.map(read, sources.items()))
rows = list(csv.reader(io.StringIO(raw['SkillLevel.csv'].decode('utf-8-sig'))))
costs = {r[0]: [int(v) for v in r[1:] if v.strip()] for r in rows[1:] if r and r[0].isdigit()}
descriptions = {r[0]: r[1].replace('<br>', '\n') for r in csv.reader(io.StringIO(raw['SkillDescriptions.csv'].decode('utf-8-sig'))) if len(r)>1 and r[0].isdigit()}
catstats = {(int(r['id']),r['name_jp']): r for r in csv.DictReader(io.StringIO(raw['catstat.tsv'].decode('utf-8-sig')), delimiter='\t')}
catalog = json.loads((root/'NyankoDB/Resources/catalog.json').read_text())
timings = {}
for unit in catalog['units']:
 for form in unit['forms']:
  if not any(form['talentData'][i] == 61 for i in range(1,len(form['talentData']),14)): continue
  r = catstats.get((unit['id'],form['name']))
  if not r or int(r['attack_frequency']) != form['freq']: raise ValueError(f"Animation mismatch: {unit['id']}-{form['form']}")
  expected = [form['data'][13], *(form['data'][61:63] if len(form['data'])>62 else [0,0])]
  if [int(r[f'preswing_{i}']) for i in range(1,4)] != expected or int(r['time_between_attacks']) != form['data'][4]*2: raise ValueError('Animation does not match snapshot')
  timings[f"{unit['id']}-{form['form']}"] = {'interval': int(r['time_between_attacks']), 'backswing': int(r['backswing'])}
output = {'version':1, 'catalogVersion':catalog['version'], 'jdbRevision':jdb_revision,
 'superUnlockLevel':60, 'costs':costs,'descriptions':descriptions,'timings':timings,
 'sources': {name:{'url':sources[name],'sha256':hashlib.sha256(data).hexdigest()} for name,data in raw.items()}}
(root/'NyankoDB/Resources/talent-support.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print(f'Bundled {len(costs)} NP tables and {len(timings)} validated attack animations')
