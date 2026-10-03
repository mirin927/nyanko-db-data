#!/usr/bin/env python3
"""Import talent-orb definitions, slot eligibility and original icons from the pinned JDB."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import argparse, concurrent.futures, csv, hashlib, io, json, pathlib, urllib.request
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
REVISION = SOURCE_REVISION
BASE = f'https://raw.githubusercontent.com/JarJarBlink/JDB/{REVISION}/'
parser = argparse.ArgumentParser()
parser.add_argument('--reference-directory', type=pathlib.Path)
args = parser.parse_args()
paths = {n: 'static/data/DataLocal/' + n for n in ['equipmentlist.json', 'equipmentslot.csv', 'equipment_option.csv', 'equipment_attribute.csv', 'equipmentgrade.csv']}
paths['equipment_explonation.tsv'] = 'static/data/resLocal_ja/equipment_explonation.tsv'
for part in ['effect', 'attribute']:
    paths[f'equipment_{part}.imgcut'] = f'static/data/ImageDataLocal/equipment_{part}.imgcut'
    paths[f'equipment_{part}.png'] = f'static/img/game/equipment_{part}.png'
raw = {}
for name, path in paths.items():
    cached = args.reference_directory / name if args.reference_directory else None
    raw[name] = cached.read_bytes() if cached and cached.exists() else open_source(BASE + path, timeout=30).read()
def rows(name, sep=','):
    return [r for r in csv.reader(io.StringIO(raw[name].decode('utf-8-sig')), delimiter=sep) if r and not r[0].startswith('//')]
catalog = json.loads((ROOT/'NyankoDB/Resources/catalog.json').read_text())
units = {u['id']: u for u in catalog['units']}
names = rows('equipment_explonation.tsv', '\t')
grades = [r[3] for r in rows('equipmentgrade.csv')]
traits = ['赤', '浮き', '黒', 'メタル', '天使', 'エイリアン', 'ゾンビ', '古代種', '無属性', '魔女', '使徒', '悪魔']
options = {int(r[0]): [int(x) for x in r[1:]] for r in rows('equipment_option.csv')}
assert len(names) == 26 and grades == ['D','C','B','A','S']
slots = {}
for r in rows('equipmentslot.csv'):
    uid, count = int(r[0]), int(r[1])
    assert uid in units and count in (1,2) and uid not in slots
    codes = list(map(int,r[2:])) if len(r)>2 else [0]
    assert codes == ([0] if count==1 else [0,1])
    assert any(f['form'] in ('s','u') and f['talentData'] for f in units[uid]['forms'])
    slots[str(uid)] = [0] if count==1 else [0,60]
orbs=[]
for d in json.loads(raw['equipmentlist.json'])['ID']:
    effect, grade = d['content'], d['gradeID']
    attr = d.get('attribute')
    assert 0<=effect<26 and 0<=grade<5 and d['value'] and all(v>=0 for v in d['value'])
    assert (effect<5 and attr in [0,1,2,3,4,5,6,7,11]) or (effect>=5 and attr is None)
    name = names[effect][0].replace('%@','').replace('【】','')
    icon = f'orb_{attr if attr is not None else 12:02d}{effect:02d}'
    orbs.append({'id':f'{effect}-{attr if attr is not None else 12}-{grade}', 'effect':effect,
        'grade':grades[grade], 'trait':traits[attr] if attr is not None else None,
        'name':name, 'description':names[effect][1].replace('%@',traits[attr] if attr is not None else '').replace('<br>',''),
        'values':d['value'], 'repeatable':True if effect<5 else bool(options[effect][1]), 'iconName':icon})
assert len({o['id'] for o in orbs})==len(orbs)==310
out = {'version':1,'catalogVersion':catalog['version'],'slots':slots,'orbs':orbs,
       'sources':{n:{'url':BASE+paths[n], 'sha256':hashlib.sha256(v).hexdigest()} for n,v in raw.items()}}
assets=ROOT/'NyankoDB/Assets.xcassets'
def icon(o):
    asset=assets/(o['iconName']+'.imageset');asset.mkdir(exist_ok=True)
    # Some pre-split filenames in JDB contain the wrong glyph (notably
    # production-cost reduction and surge resistance). Compose every icon from
    # the game's labeled atlas rectangles instead of trusting those filenames.
    def cut(part, index):
        lines = raw[f'equipment_{part}.imgcut'].decode().splitlines()
        assert lines[0] == '[imgcut]' and 0 <= index < int(lines[3])
        x,y,w,h = map(int, lines[4+index].split(',')[:4])
        atlas = Image.open(io.BytesIO(raw[f'equipment_{part}.png'])).convert('RGBA')
        assert x >= 0 and y >= 0 and x+w <= atlas.width and y+h <= atlas.height
        return atlas.crop((x,y,x+w,y+h))
    im = cut('attribute', int(o['iconName'][4:6]))
    effect = cut('effect', o['effect'])
    assert effect.size == im.size
    im.alpha_composite(effect)
    buf = io.BytesIO(); im.save(buf,format='PNG'); data = buf.getvalue()
    assert data.startswith(b'\x89PNG')
    (asset/'icon.png').write_bytes(data)
    (asset/'Contents.json').write_text(json.dumps({'images':[{'filename':'icon.png','idiom':'universal'}],'info':{'author':'xcode','version':1}}))
unique={o['iconName']:o for o in orbs}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:list(pool.map(icon, unique.values()))
(ROOT/'NyankoDB/Resources/orb-support.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(f'Bundled {len(orbs)} orbs, {len(unique)} icons, {len(slots)} units ({sum(len(s)==2 for s in slots.values())} with 2 slots)')
