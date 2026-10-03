#!/usr/bin/env python3
"""Produce a static HTTPS feed. Uploading is deliberately separate from building.
--bundle also writes the bundled baseline metadata; use after refreshing app assets.
"""
import argparse,base64,hashlib,json,pathlib,time,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
DATA=['catalog','search-index','enemy-catalog','enemy-search-index','stage-catalog','stage-search-index','combo-catalog','combo-search-index','talent-support','evolution-support','orb-support']
def digest(b):return hashlib.sha256(b).hexdigest()
def encoded(x):return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()+b'\n'
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--sequence',type=int);p.add_argument('--version',default=time.strftime('%Y.%m.%d'));p.add_argument('--minimum-app-build',type=int,default=1);p.add_argument('--bundle',action='store_true');a=p.parse_args()
 sequence=a.sequence if a.sequence is not None else int(time.time())
 if sequence<0 or a.minimum_app_build<1:raise ValueError('Invalid release sequence/build')
 resources=ROOT/'NyankoDB/Resources';assets=ROOT/'NyankoDB/Assets.xcassets'
 cat=json.loads((resources/'catalog.json').read_bytes());enemy=json.loads((resources/'enemy-catalog.json').read_bytes());stage=json.loads((resources/'stage-catalog.json').read_bytes())
 revisions={enemy['revision'],stage['revision']}
 for name in ['talent-support','evolution-support','combo-catalog']:
  obj=json.loads((resources/(name+'.json')).read_bytes())
  assert obj['catalogVersion']==cat['version'] and obj['jdbRevision'] in revisions
 assert len(revisions)==1,'All databases must come from the same source revision'
 payload={f'data/{name}.json':(resources/(name+'.json')).read_bytes() for name in DATA}
 images={};packs={}
 for folder in sorted(assets.glob('*.imageset')):
  content=json.loads((folder/'Contents.json').read_bytes());files={i['filename'] for i in content['images'] if i.get('filename')}
  if len(files)!=1:raise ValueError(f'Expected one PNG per image: {folder.name}')
  b=(folder/next(iter(files))).read_bytes()
  if not b.startswith(b'\x89PNG\r\n\x1a\n'):raise ValueError('Only PNG assets supported')
  name=folder.stem;key='packs/'+digest(name.encode())[:2]+'.json'
  images[name]={'sha256':digest(b),'bytes':len(b),'pack':key}
  packs.setdefault(key,{})[name]=base64.b64encode(b).decode()
 for key,value in packs.items():payload[key]=encoded(value)
 files=[{'path':key,'sha256':digest(value),'bytes':len(value)} for key,value in sorted(payload.items())]
 release_id=f'release-{sequence}-'+digest(encoded({'files':files,'version':a.version,'images':images}))[:12]
 manifest={'formatVersion':1,'minimumAppBuild':a.minimum_app_build,'sequence':sequence,'id':release_id,'version':a.version,'publishedAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'sourceRevision':next(iter(revisions)),'files':files,'images':images}
 target=a.output/release_id;target.mkdir(parents=True,exist_ok=True)
 for key,value in payload.items():
  dest=target/key;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(value)
 (target/'manifest.json').write_bytes(encoded(manifest));a.output.mkdir(parents=True,exist_ok=True)
 temp=a.output/'manifest.next.json';temp.write_bytes(encoded(manifest));temp.replace(a.output/'manifest.json')
 if a.bundle:(resources/'data-baseline.json').write_bytes(encoded(manifest))
 print(f'{release_id}: {len(files)} files, {len(images)} images, {sum(map(len,payload.values()))/1e6:.1f} MB')
 print('Publish this whole directory on HTTPS; publish manifest.json last. Keep prior release folders.')
if __name__=='__main__':main()
