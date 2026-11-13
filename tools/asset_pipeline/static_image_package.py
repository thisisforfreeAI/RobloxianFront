"""Export unchanged local atlases as PNGs, then import Roblox Image IDs with source checks.
export --source src/client/DevAssets --output build/static-images
import --package build/static-images --ids build/static-images/image_ids.json --output src/shared/GameData/StaticImageIds.luau
Generated PNGs, manifests and IDs contain private source material and belong in ignored folders.
"""
import argparse,hashlib,json,re,io
from pathlib import Path
from PIL import Image
from private_images import load,lua,decode,signature

def safe_output(path):
    path=Path(path).resolve()
    if any((parent/'resources/app.asar').exists()for parent in (path,*path.parents)):
        raise ValueError('output must stay outside the original game install')
    return path
def images(path):
    meta=load(path)
    if path.stem=='OrigStructures':
        for army,atlas in meta.get('armies',{}).items():yield 'OrigStructures:'+army,atlas
        for field,key in [('badges','$badges'),('weapons','$weapons'),('artillery','$artillery')]:
            if field in meta:yield 'OrigStructures:'+key,meta[field]
        for army,atlas in meta.get('launchers',{}).items():yield 'OrigStructures:$sam:'+army,atlas
    elif ('rle'in meta or 'deflate'in meta)and 'width'in meta and 'height'in meta:
        yield path.stem,meta
def export(source,output,overlay=None):
    source=Path(source).resolve();output=safe_output(output)
    if output==source or source in output.parents:raise ValueError('put the upload package outside DevAssets')
    output.mkdir(parents=True,exist_ok=True);entries=[];canonical={};ids={}
    previous_manifest=json.loads((output/'manifest.json').read_text(encoding='utf-8')) if (output/'manifest.json').exists() else {'entries':[]}
    previous_entries={entry['key']:entry for entry in previous_manifest['entries']}
    previous_ids=json.loads((output/'image_ids.json').read_text(encoding='utf-8')) if (output/'image_ids.json').exists() else {}
    sources={path.name:path for path in source.glob('Orig*.luau')}
    if overlay:sources.update({path.name:path for path in Path(overlay).glob('Orig*.luau')})
    for path in sorted(sources.values(),key=lambda path:path.name):
        if not re.match(r'^Orig(?:Tank|Truck|Scout|Artillery|Infantry|Ifv|Rocket|Engineer|Demo|Command|Men|DeathFx|Structures)',path.stem):continue
        for key,meta in images(path):
            pixels=decode(meta);image=Image.fromarray(pixels)
            filename=re.sub(r'[^A-Za-z0-9_-]','_',key)+'.png';dest=output/filename;stream=io.BytesIO();image.save(stream,format='PNG',optimize=True);png=stream.getvalue()
            digest=hashlib.sha256(png).hexdigest();first=canonical.get(digest)
            if first:filename=first['file']
            else:dest.write_bytes(png)
            entry={'key':key,'file':filename,'width':meta['width'],'height':meta['height'],'sourceHash':signature(meta),'sha256':digest,'rgbaBytes':meta['width']*meta['height']*4}
            if first:entry['aliasOf']=first['key']
            else:canonical[digest]=entry;ids[key]=''
            entries.append(entry)
    if not entries:raise ValueError('no supported static images found')
    manifest={'version':1,'assetType':'Image','entries':entries}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    ids_path=output/'image_ids.json'
    # A fresh export does not discard previously entered/uploaded IDs for unchanged PNGs.
    for key in ids:
        before=previous_entries.get(key);current=next(entry for entry in entries if entry['key']==key)
        if before and before['sha256']==current['sha256'] and key in previous_ids:ids[key]=previous_ids[key]
    ids_path.write_text(json.dumps(ids,indent=2)+'\n',encoding='utf-8')
    (output/'README.txt').write_text('Upload the canonical PNG files listed in manifest.json as Roblox Image assets owned by your experience creator.\nUse Studio Asset Manager or static_image_upload.py (dry-run by default).\nFill image_ids.json with the actual Image IDs, then run static_image_package.py import.\nDo not substitute decal/container IDs. Runtime validates source signatures and waits for a successful asset load before replacing local art.\nOnly unchanged atlases are included. Dynamic fog, terrain damage and lighting canvases remain EditableImages.\n',encoding='utf-8')
    return manifest
def import_ids(package,ids_path,output):
    package=Path(package).resolve();output=safe_output(output)
    manifest=json.loads((package/'manifest.json').read_text(encoding='utf-8'));ids=json.loads(Path(ids_path).read_text(encoding='utf-8'))
    if manifest.get('version')!=1 or manifest.get('assetType')!='Image':raise ValueError('unsupported package')
    result={};by_id={}
    for entry in manifest['entries']:
        path=(package/entry['file']).resolve()
        if package not in path.parents:raise ValueError('image path escapes package')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:raise ValueError('PNG changed: '+entry['key'])
        raw=ids.get(entry['key'])or ids.get(entry.get('aliasOf',''))
        if raw in (None,''):continue
        value=str(raw)
        if not re.fullmatch(r'[1-9]\d{0,19}',value):raise ValueError('invalid Image ID for '+entry['key'])
        if value in by_id and by_id[value]!=entry['sha256']:raise ValueError('one Image ID maps to different PNGs')
        by_id[value]=entry['sha256']
        result[entry['key']]={'id':value,'width':entry['width'],'height':entry['height'],'sourceHash':entry['sourceHash']}
    if not result:raise ValueError('no uploaded Image IDs supplied; local image fallback stays active')
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text('-- Generated private Roblox Image IDs; git-ignored.\nreturn '+lua(result)+'\n',encoding='utf-8',newline='\n');return result
def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    e=sub.add_parser('export');e.add_argument('--source',type=Path,required=True);e.add_argument('--output',type=Path,required=True);e.add_argument('--overlay',type=Path)
    i=sub.add_parser('import');i.add_argument('--package',type=Path,required=True);i.add_argument('--ids',type=Path,required=True);i.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    if a.command=='export':
        m=export(a.source,a.output,a.overlay);print(f"Exported {len(m['entries'])} atlas bindings / {sum('aliasOf'not in e for e in m['entries'])} canonical PNGs to {a.output}")
    else:print(f'Imported {len(import_ids(a.package,a.ids,a.output))} static bindings')
if __name__=='__main__':main()
