#!/usr/bin/env python3
"""Build offline stages from a sparse checkout of the same pinned JDB revision.
Usage: python3 scripts/import_stage_catalog.py --source /tmp/nyanko-stage-jdb
No runtime downloads. Source CSV IDs include two reserved enemies; app IDs subtract 2.
"""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import argparse, csv, hashlib, json, pathlib, re, subprocess
REV = SOURCE_REVISION
GROUPS = {
 'RN': (0, 'レジェンド'), 'RS': (1000, 'イベント'), 'RC': (2000, 'コラボ'),
 'EX': (4000, 'EX'), 'RT': (6000, '修行'), 'RV': (7000, 'にゃんこ塔'),
 'RR': (11000, 'ランキング'), 'RM': (12000, 'チャレンジ'), 'RNA': (13000, '真レジェンド'),
 'RB': (14000, 'にゃんこ別塔・マタタビ'), 'RA': (24000, '強襲'), 'RH': (25000, '地図'),
 'RCA': (27000, 'コラボ強襲'), 'DM': (30000, '魔界編'), 'RQ': (31000, '超獣討伐'),
 'L': (33000, 'グランドアビス'), 'RND': (34000, 'ゼロレジェンド'),
 'RSR': (36000, '異次元コロシアム'), 'G': (37000, 'にゃんこ道検定'), 'RPR': (39000, 'こねこライブ')}

def number_rows(path):
    result = []
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.split('//', 1)[0].strip()
        if not re.match(r'^-?\d', line): continue
        row = []
        for item in line.split(','):
            if not re.fullmatch(r'-?\d+', item.strip()): break
            row.append(int(item.strip()))
        if row: result.append(row)
    return result

def valid_name(name):
    return bool(name.strip()) and name.strip() not in ('＠', '@', '予備', 'ダミー')

def main():
    args = argparse.ArgumentParser(); args.add_argument('--source', required=True); opts = args.parse_args()
    source = pathlib.Path(opts.source)
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != REV: raise ValueError('Source revision must match the enemy catalog: ' + REV)
    local, lang = source/'static/data/DataLocal', source/'static/data/resLocal_ja'
    resources = pathlib.Path(__file__).resolve().parents[1]/'NyankoDB/Resources'
    provenance = {}
    def used(path):
        provenance[str(path.relative_to(source))] = hashlib.sha256(path.read_bytes()).hexdigest()
        return path
    def nums(file): return number_rows(used(local/file))
    def names(file): return list(csv.reader(used(lang/file).open(encoding='utf-8-sig')))
    map_names = {int(r[0]): r[1].strip() for r in names('Map_Name.csv') if r and r[0].isdigit() and len(r)>1}
    options = {r[0]: r for r in nums('Map_option.csv')}
    limits = nums('Stage_option.csv')
    fallback = used(lang/'Enemyname.tsv').read_text().splitlines()
    stages = []
    def add(file, map_id, index, name, category, metadata, stars=None, chapter_mag=100, has_castle=True):
        rows = nums(file)
        castle = rows[0] if has_castle else []
        header = rows[1 if has_castle else 0]
        enemies = []
        for row in rows[2 if has_castle else 1:]:
            if row[0] == 0: break
            if len(row)<9: continue
            row = row + [0] * max(0, 14-len(row))
            # EoC omits magnifications. All other rows default missing HP to 100.
            hp = row[9] or 100
            if header[7] == 0 and row[5] > 100 and hp == 100:
                hp, row[5] = row[5], 100
            row[9] = hp * chapter_mag / 100
            row[11] = (row[11] or hp) * chapter_mag / 100
            if len(header)>6 and header[6]>=2 and row[0]==header[6]: row[5]=0
            enemies.append(row[:14])
        op = options.get(map_id, [])
        star_values = stars or ([v for v in op[3:3+min(4,max(1,op[1]))] if v>0] if op else [100]) or [100]
        stage = dict(id=f'{map_id}-{index}', mapID=map_id, number=index, name=name.strip(),
            mapName=map_names[map_id], category=category, energy=metadata[0] if metadata else 0,
            baseXP=metadata[1] if len(metadata)>1 else 0, width=header[0], castleHP=header[1],
            maxEnemies=min(50,header[5]), timeLimit=header[7] if len(header)>7 else 0,
            bossGuard=bool(has_castle and len(header)>8 and header[8]==1),
            baseEnemyID=header[6]-2 if len(header)>6 and header[6]>=2 else None,
            noContinue=bool(castle and len(castle)>1 and castle[1]==1), stars=star_values,
            spawns=enemies, limits=[r[:9] for r in limits if len(r)>=9 and r[0]==map_id and r[2] in (-1,index)])
        stages.append(stage)
    for prefix,(offset,category) in GROUPS.items():
        name_file = 'StageName_RE_ja.csv' if prefix=='EX' else f'StageName_{prefix}_ja.csv'
        stage_names = names(name_file)
        map_prefix = 'RE' if prefix=='EX' else prefix[1:] if prefix.startswith('R') else prefix
        for file in sorted(local.glob(f'stage{prefix}*.csv')):
            match = re.fullmatch(r'stage'+prefix+r'(\d+)_(\d+)\.csv',file.name)
            if not match: continue
            map_number,index = map(int,match.groups()); map_id=offset+map_number
            if map_id not in map_names or map_number>=len(stage_names) or index>=len(stage_names[map_number]):continue
            name=stage_names[map_number][index]
            if not valid_name(name) or not valid_name(map_names[map_id]): continue
            meta_file=f'MapStageData{map_prefix}_{map_number:03d}.csv'
            if not (local/meta_file).exists(): continue
            meta=nums(meta_file)[2:]
            if index>=len(meta):continue
            add(file.name,map_id,index,name,category,meta[index])
    for family in range(3):
        raw = [r[0].strip() for r in names(f'StageName{family}_ja.csv')][:48]
        ordered = list(reversed(raw[:46])) + raw[46:48]
        for chapter in range(3):
            map_id=3000+family*3+chapter
            meta=nums('stageNormal0.csv' if family==0 else f'stageNormal{family}_{chapter}.csv')[2:]
            for index,name in enumerate(ordered):
                file=f'stage{index:02d}.csv' if family==0 else f'stageW{chapter+4:02d}_{index:02d}.csv' if family==1 else f'stageSpace{chapter+7:02d}_{index:02d}.csv'
                if not (local/file).exists() or index>=len(meta):continue
                add(file,map_id,index,name,['日本編','未来編','宇宙編'][family],meta[index],stars=[100],chapter_mag=[100,150,400][chapter] if family==0 else 100,has_castle=False)
            zombie_map=20000+family*1000+chapter
            zmeta=nums(f'stageNormal{family}_{chapter}_Z.csv')[2:]
            for index,name in enumerate(ordered):
                file=f'stageZ{chapter if family==0 else chapter+4 if family==1 else chapter+7:02d}_{index:02d}.csv'
                if not (local/file).exists() or index>=len(zmeta):continue
                add(file,zombie_map,index,name,'ゾンビ襲来',zmeta[index])
    for map_id,suffix in [(23000,''),(38000,'_Z')]:
        file=f'stageSpace09_Invasion{suffix}_00.csv'
        if (local/file).exists():add(file,map_id,0,'フィリバスター襲来','宇宙編',nums(f'stageNormal2_2_Invasion{suffix}.csv')[2],has_castle=True)
    stages.sort(key=lambda x:(x['mapID'],x['number']))
    assert len({s['id'] for s in stages})==len(stages)
    payload=dict(version=REV[:12],revision=REV,source='https://jarjarblink.github.io/JDB/map_search.html?cc=ja',stages=stages,
        enemyNames={str(i):s for i,s in enumerate(fallback) if valid_name(s)})
    (resources/'stage-catalog.json').write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':'))+'\n')
    (resources/'stage-sources.json').write_text(json.dumps(dict(revision=REV,files=provenance),indent=2,ensure_ascii=False)+'\n')
    print(f'{len(stages)} stages, {len(set(s["mapID"] for s in stages))} maps, {len(provenance)} source files')
if __name__=='__main__':main()
