"""Build private alpha-weighted sprite mip sheets from existing packed original modules.

python tools/asset_pipeline/pack_sprite_lods.py <DevAssets> [--output <directory>]
Only SpriteBank families are considered. Source modules are read-only; generated _Mip2/_Mip4
modules remain under ignored DevAssets. No original game install is modified.
"""
import argparse, base64, re, struct, zlib
from pathlib import Path
import numpy as np

FAMILY=re.compile(r'^Orig(?:Tank|Truck|Scout|Artillery|Infantry|Ifv|Rocket|Engineer|Demo|Command|Men(?:Rifle|Leader|Para|Gunner|Loader|Mortarman|Bearer|Tube|Crew|Engineer|Sapper))(?:_|Rim|Shade|Wreck|$)')
def parse(text):
    def number(key):
        found=re.search(r'\b'+key+r'\s*=\s*(\d+)',text)
        if not found: raise ValueError('missing '+key)
        return int(found[1])
    raw=re.search(r'\brle\s*=\s*"([A-Za-z0-9+/=]*)"',text)
    strips=re.search(r'\bstrips\s*=\s*\{([^}]*)\}',text)
    if not raw or not strips: raise ValueError('not a strip sprite sheet')
    meta={k:number(k) for k in ('width','height','frame','columns')}
    meta['strips']={k:int(v) for k,v in re.findall(r'\["([^"]+)"\]\s*=\s*(\d+)',strips[1])}
    meta['rle']=raw[1]
    return meta

def decode(meta):
    packed=base64.b64decode(meta['rle'],validate=True)
    if len(packed)%6: raise ValueError('truncated RGBA run')
    runs=np.frombuffer(packed,dtype=np.dtype([('count','<u2'),('rgba','u1',(4,))]))
    if np.any(runs['count']==0) or int(runs['count'].astype(np.uint64).sum())!=meta['width']*meta['height']: raise ValueError('RGBA run size mismatch')
    return np.repeat(runs['rgba'],runs['count'].astype(np.int64),axis=0).reshape(meta['height'],meta['width'],4)

def half(pixels):
    h,w,_=pixels.shape
    if h%2 or w%2: raise ValueError('odd sprite dimensions')
    blocks=pixels.astype(np.uint32).reshape(h//2,2,w//2,2,4)
    alpha=blocks[:,:,:,:,3].sum(axis=(1,3));rgb=(blocks[:,:,:,:,:3]*blocks[:,:,:,:,3,None]).sum(axis=(1,3))
    out=np.zeros((h//2,w//2,4),dtype=np.uint8)
    divisor=np.maximum(alpha,1)[:,:,None]
    out[:,:,:3]=np.floor(rgb/divisor+.5).astype(np.uint8);out[:,:,3]=np.floor(alpha/4+.5).astype(np.uint8)
    return out

def encode(pixels):
    flat=np.ascontiguousarray(pixels).reshape(-1,4).copy();flat[flat[:,3]==0]=0
    words=flat.view('<u4').reshape(-1);edges=np.r_[0,np.flatnonzero(words[1:]!=words[:-1])+1,len(words)];data=bytearray()
    for start,end in zip(edges[:-1],edges[1:]):
        count=int(end-start)
        while count: n=min(65535,count);data+=struct.pack('<HI',n,int(words[start]));count-=n
    return base64.b64encode(data).decode('ascii')

def generate(source,output):
    source,output=Path(source),Path(output)
    if '_Mip' in source.stem or not FAMILY.match(source.stem): return []
    try: meta=parse(source.read_text(encoding='utf-8-sig'))
    except ValueError: return []
    if any(meta[k]%4 for k in ('width','height','frame')) or not meta['strips'] or any(v%4 for v in meta['strips'].values()): raise ValueError('sprite grid is not divisible by four')
    pixels=decode(meta);signature=zlib.adler32(meta['rle'].encode('ascii'));written=[]
    for stride in (2,4):
        pixels=half(pixels);name=source.stem+'_Mip'+str(stride);strips=', '.join(f'["{key}"] = {value//stride}' for key,value in meta['strips'].items())
        text='--!strict\n-- GENERATED private sprite LOD; original logical geometry stays in the source module.\nreturn {\n'+f' name = "{name}", lod = {stride}, sourceHash = {signature}, frame = {meta["frame"]//stride}, columns = {meta["columns"]}, directions = 16, width = {meta["width"]//stride}, height = {meta["height"]//stride},\n strips = {{ {strips} }},\n rle = "{encode(pixels)}",\n}}\n'
        output.mkdir(parents=True,exist_ok=True);dest=output/(name+'.luau');dest.write_text(text,encoding='utf-8',newline='\n');written.append(dest)
    return written

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path);parser.add_argument('--output',type=Path);args=parser.parse_args()
    written=[]
    for source in sorted(args.source.glob('Orig*.luau')): written.extend(generate(source,args.output or args.source))
    print(f'Generated {len(written)} private sprite LOD modules')
if __name__=='__main__': main()
