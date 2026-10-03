#!/usr/bin/env python3
"""Bundle active Japanese combos against the existing pinned character snapshot."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import argparse, csv, hashlib, io, json, pathlib, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
REVISION = SOURCE_REVISION
BASE = f'https://raw.githubusercontent.com/JarJarBlink/JDB/{REVISION}/'
FILES = {
    'NyancomboData.csv': 'static/data/DataLocal/',
    'NyancomboParam.tsv': 'static/data/DataLocal/',
    'Nyancombo_ja.csv': 'static/data/resLocal_ja/',
    'Nyancombo1_ja.csv': 'static/data/resLocal_ja/',
    'Nyancombo2_ja.csv': 'static/data/resLocal_ja/',
}
parser = argparse.ArgumentParser()
parser.add_argument('--reference-directory', type=pathlib.Path)
args = parser.parse_args()
raw = {}
for name, directory in FILES.items():
    local = args.reference_directory / name if args.reference_directory else None
    raw[name] = local.read_bytes() if local and local.exists() else open_source(BASE + directory + name, timeout=30).read()

def rows(name, delimiter=','):
    return list(csv.reader(io.StringIO(raw[name].decode('utf-8-sig')), delimiter=delimiter))

def names(name):
    return [r[0].strip() for r in rows(name)]

catalog = json.loads((ROOT / 'NyankoDB/Resources/catalog.json').read_text())
units = {u['id']: u for u in catalog['units']}
data = rows('NyancomboData.csv')
combo_names = names('Nyancombo_ja.csv')
effect_names = names('Nyancombo1_ja.csv')
tiers = [s.replace('【', '').replace('】', '') for s in names('Nyancombo2_ja.csv')]
params = [[int(v) for v in r] for r in rows('NyancomboParam.tsv', '\t')]
assert len(data) == len(combo_names) and len(params) == len(effect_names) == 29
unlocks = {1: '日本編 第1章クリア', 4: '未来編 第1章クリア', 5: '未来編 第2章クリア', 6: '未来編 第3章クリア',
           10001: 'ユーザーランク2700の報酬', 10002: 'ユーザーランク1450の報酬', 10003: 'ユーザーランク2150の報酬'}
# Values/units checked against battlecats-db.com/unit/index_combo.html.
# Do not extrapolate a research duration for the Ranger-only ultimate combo:
# the reference lists no verified duration for that entry.
def display(effect, tier, value):
    note = ''
    if effect == 4:
        return f'初期レベル +{value}', 'ネコボン使用時はネコボンの効果が優先されます。'
    if effect == 5:
        return f'初期所持金 +{value}円', note
    if effect == 7:
        frames = {0: 150, 1: 300, 2: 450}[tier]
        return f'チャージ {frames // 30}秒短縮', note
    if effect == 11:
        frames = {0: 26, 1: 52, 2: 79}.get(tier)
        text = f'再生産 {frames / 30:.2f}秒短縮' if frames is not None else '再生産時間を短縮'
        return text, '適用後も再生産時間は2秒未満にはなりません。'
    if effect == 22:
        return '与ダメージ25倍・被ダメージ0.02倍', '魔女キラーを持つキャラに適用されます。'
    if effect == 23:
        return '与ダメージ25倍・被ダメージ0.04倍', '使徒キラーを持つキャラに適用されます。'
    if effect == 25:
        return '怪人特効を付与', '対怪人：与ダメージ25倍・被ダメージ1/25。'
    if effect in (26, 28):
        return '効果を付与', note
    if effect == 27:
        return f'生産コスト {value}%割引', note
    if effect == 24:
        return f'発動率 +{value}ポイント', 'クリティカルを持つキャラの発動率に加算されます。'
    if 14 <= effect <= 21:
        note = '該当する特性を持つキャラに適用されます。'
    return f'+{value}%', note

combos = []
for row_index, raw_row in enumerate(data):
    r = list(map(int, raw_row))
    assert len(r) == 16
    # JDB's combo parser rejects rows whose enable/unlock column is -1.
    if r[1] == -1:
        continue
    assert r[1] in unlocks and r[2] in (-1, 10) and r[15] == -1
    effect, tier = r[13:15]
    assert 0 <= effect < len(effect_names) and 0 <= tier < len(tiers)
    value = params[effect][tier]
    members = []
    for j in range(3, 13, 2):
        unit_id, form_index = r[j:j + 2]
        if unit_id == -1:
            assert form_index == -1
            continue
        assert unit_id in units and 0 <= form_index <= 3
        code = ['f', 'c', 's', 'u'][form_index]
        assert any(f['form'] == code for f in units[unit_id]['forms'])
        members.append({'unitID': unit_id, 'minimumForm': form_index + 1})
    assert 1 <= len(members) <= 5 and len({m['unitID'] for m in members}) == len(members)
    text, note = display(effect, tier, value)
    combos.append({'id': r[0], 'sourceRow': row_index, 'name': combo_names[row_index], 'effectID': effect,
                   'tierID': tier, 'effectValue': value, 'amount': text, 'note': note, 'unlock': unlocks[r[1]],
                   'scope': 'にゃんこレンジャーのみ' if r[2] == 10 else '', 'members': members})
assert len({c['id'] for c in combos}) == len(combos) and all(c['name'] for c in combos)
active_effects = sorted({c['effectID'] for c in combos})
output = {'version': 1, 'catalogVersion': catalog['version'], 'jdbRevision': REVISION, 'region': 'ja',
          'effects': [{'id': i, 'name': effect_names[i]} for i in active_effects],
          'tiers': [{'id': i, 'name': t} for i, t in enumerate(tiers) if any(c['tierID'] == i for c in combos)],
          'combos': combos, 'sources': {n: {'url': BASE + d + n, 'sha256': hashlib.sha256(raw[n]).hexdigest()} for n, d in FILES.items()},
          'displayReference': 'https://battlecats-db.com/unit/index_combo.html',
          'rulesReference': 'https://ponos.s3.amazonaws.com/information/appli/battlecats/combo/index.html'}
(ROOT / 'NyankoDB/Resources/combo-catalog.json').write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
print(f'Bundled {len(combos)} active Japanese combos, {len(active_effects)} effect types.')
