#!/usr/bin/env python3
"""Convert one JDB commit in a temporary workspace, verify it, then advance the feed.
Requires macOS (Japanese reading generation), Python + Pillow, Git and Swift.
Never edits the shipped app resources, and does not publish to any server.
"""
import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM = 'https://github.com/JarJarBlink/JDB.git'
SPARSE = ['static/data/DataLocal', 'static/data/resLocal_ja', 'static/data/ImageDataLocal',
          'static/js/unit', 'static/js/t_unit', 'static/img/unit_icon', 'static/img/enemy_icon',
          'static/img/game', 'static/img/ability_icon']

def run(args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--source', type=pathlib.Path, help='Existing JDB checkout; no upstream fetch')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--minimum-app-build', type=int, default=1)
    args = parser.parse_args()
    if args.source:
        revision = subprocess.check_output(['git','-C',str(args.source),'rev-parse','HEAD'], text=True).strip()
    else:
        revision = subprocess.check_output(['git','ls-remote',UPSTREAM,'refs/heads/main'], text=True).split()[0]
    if not re.fullmatch('[a-f0-9]{40}', revision): raise ValueError('Invalid upstream revision')
    previous_path = args.output/'manifest.json'
    previous = json.loads(previous_path.read_bytes()) if previous_path.exists() else None
    if previous and previous['sourceRevision'] == revision and not args.force:
        print('Upstream is unchanged; no conversion or image downloads needed.')
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'],'a') as output: output.write('changed=false\n')
        return
    with tempfile.TemporaryDirectory(prefix='nyanko-feed-') as temporary:
        work = pathlib.Path(temporary)
        source = args.source.resolve() if args.source else work/'JDB'
        if not args.source:
            run(['git','clone','--filter=blob:none','--sparse','--no-checkout',UPSTREAM,source])
            run(['git','-C',source,'sparse-checkout','set',*SPARSE])
            run(['git','-C',source,'checkout','--detach',revision])
        actual = subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'], text=True).strip()
        if actual != revision: raise ValueError('Source changed during conversion')
        project = work/'NyankoDB'
        shutil.copytree(ROOT/'scripts', project/'scripts', ignore=shutil.ignore_patterns('__pycache__'))
        for part in ['Models','Resources','Assets.xcassets']:
            shutil.copytree(ROOT/'NyankoDB'/part, project/'NyankoDB'/part)
        environment = dict(os.environ, JDB_SOURCE=str(source), JDB_REVISION=revision)
        scripts = project/'scripts'
        for name in ['import_catalog','fetch_portraits','fetch_feature_icons','import_talent_support',
                     'import_evolution_support','import_orb_support','import_combo_catalog','import_enemy_catalog']:
            extra = ['--fetch-images'] if name == 'import_enemy_catalog' else []
            run(['python3',scripts/(name+'.py'),*extra],env=environment)
        run(['python3',scripts/'import_stage_catalog.py','--source',source],env=environment)
        for mode in [[],['--enemies'],['--stages'],['--combos']]:
            run(['bash',scripts/'generate_search_index.sh',*mode],env=environment)
        staged_feed = work/'feed'
        sequence = max(int(time.time()), (previous['sequence'] + 1) if previous else 1)
        run(['python3',scripts/'publish_data_release.py','--output',staged_feed,'--sequence',sequence,
             '--version',time.strftime('%Y.%m.%d')+'-'+revision[:7], '--minimum-app-build',args.minimum_app_build])
        run(['bash',scripts/'validate_data_release.sh',staged_feed])
        # Release files first; advancing the manifest is the last local operation.
        manifest = json.loads((staged_feed/'manifest.json').read_bytes())
        args.output.mkdir(parents=True,exist_ok=True)
        shutil.copytree(staged_feed/manifest['id'],args.output/manifest['id'])
        temporary_manifest = args.output/'manifest.next.json'
        shutil.copyfile(staged_feed/'manifest.json',temporary_manifest)
        temporary_manifest.replace(previous_path)
        (args.output/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>にゃんこDB データ配信</title><p>にゃんこDB の更新データ配信先です。</p>')
        (args.output/'.nojekyll').touch()
        # Preserve the previous feed and at least a week of immutable releases.
        for folder in args.output.glob('release-*'):
            if folder.name in [manifest['id'], previous['id'] if previous else '']: continue
            old = json.loads((folder/'manifest.json').read_bytes())
            if old['sequence'] < sequence - 7*86400: shutil.rmtree(folder)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'],'a') as output: output.write('changed=true\n')
        print('Verified feed ready:', args.output)

if __name__ == '__main__': main()
