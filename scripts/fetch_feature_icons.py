#!/usr/bin/env python3
"""Bundle the game-specific feature icons used by the private JDB catalog."""
from jdb_source import REVISION as SOURCE_REVISION, BASE as SOURCE_BASE, open_source
import concurrent.futures
import io
import json
import pathlib
import urllib.request
from PIL import Image

root = pathlib.Path(__file__).resolve().parents[1]
# Use the same dedicated icons as JDB's Ability, Immunity and Effect sections.
numbered = {
    'strong': 9, 'resistant': 10, 'massive': 12, 'insaneDamage': 31, 'tough': 30,
    'freeze': 3, 'slow': 4, 'weaken': 1, 'knockback': 13, 'curse': 36,
    'attacksOnly': 8, 'dodge': 33, 'wave': 14, 'miniWave': 38,
    'surge': 34, 'miniSurge': 43, 'explosion': 48, 'critical': 7,
    'savage': 32, 'metalKiller': 47, 'strengthen': 2, 'survive': 5,
    'zombieKiller': 25, 'barrier': 26, 'shield': 39, 'waveBlock': 24,
    'counterSurge': 44, 'soul': 41, 'baseDestroyer': 6, 'metal': 15,
    'extraMoney': 11, 'summon': 45, 'colossus': 40, 'behemoth': 42, 'sage': 46,
    'waveImmune': 16, 'surgeImmune': 37, 'curseImmune': 29,
    'freezeImmune': 22, 'slowImmune': 23, 'weakenImmune': 20,
    'knockbackImmune': 19, 'warpImmune': 27, 'toxicImmune': 35,
    'explosionImmune': 49, 'drainImmune': 50
}
abilities = {name: f'zukan_icon{number:02}' for name, number in numbered.items()}
abilities.update({'warp': 'warp', 'suicide': 'Suicide', 'witchKiller': 'witch_killer',
                  'evaKiller': 'eva_killer', 'shockwaveImmune': 'BossWaveX'})
attacks = {'single': 'ja/zukan_icon21', 'area': 'ja/zukan_icon17',
           'longDistance': 'ja/zukan_icon18', 'omni': 'ja/zukan_icon28'}
traits = {'red': 1, 'floating': 2, 'black': 3, 'angel': 4, 'alien': 5,
          'metal': 6, 'zombie': 7, 'relic': 8, 'aku': 9, 'traitless': 10}
manifest = {}
for category, items in [('ability', abilities), ('attack', attacks)]:
    for name, source in items.items():
        manifest[f'{category}_{name}'] = f'static/img/ability_icon/{source}.png'
for name, number in traits.items():
    manifest[f'trait_{name}'] = f'static/img/ability_icon/ja/zukan_target{number:02}.png'

manifest['trait_witch'] = 'static/img/ability_icon/witch.png'
manifest['trait_eva'] = 'static/img/ability_icon/Eva.png'

for name, source in {
    'weakenResist': 'drop_atk_endurance', 'freezeResist': 'freeze_endurance',
    'slowResist': 'slow_t', 'knockbackResist': 'kb_endurance', 'waveResist': 'wave_t',
    'warpResist': 'warp_endurance', 'curseResist': 'curse_endurance',
    'toxicResist': 'toxic_endurance', 'surgeResist': 'surge_endurance'
}.items():
    manifest[f'ability_{name}'] = f'static/img/ability_icon/{source}.png'
for name, source in {'hp': 'hp_up', 'attack': 'atk_up', 'speed': 'speed_up',
                     'cost': 'money', 'cooldown': 'time', 'interval': 'tba',
                     'knockbacks': 'kb_count', 'unknown': 'no_image'}.items():
    manifest[f'talent_{name}'] = f'static/img/ability_icon/{source}.png'


def fetch(item):
    name, source = item
    destination = root / f'NyankoDB/Assets.xcassets/{name}.imageset'
    url = SOURCE_BASE + source
    with open_source(url, timeout=30) as response:
        data = response.read()
    icon = Image.open(io.BytesIO(data))
    icon.load()
    destination.mkdir(exist_ok=True)
    icon.convert('RGBA').save(destination / 'icon.png')
    (destination / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': 'icon.png', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}
    }))

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
    list(executor.map(fetch, manifest.items()))
(root / 'NyankoDB/Resources/icon-sources.json').write_text(json.dumps(manifest, indent=2))
print(f'Bundled {len(manifest)} dedicated feature icons')
