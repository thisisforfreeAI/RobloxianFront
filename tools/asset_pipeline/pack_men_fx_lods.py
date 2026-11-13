"""Repack private cropped soldier masks at half/quarter resolution, retaining logical crop pivots.
python tools/asset_pipeline/pack_men_fx_lods.py <DevAssets> [--output <directory>]
"""
import argparse,math
from pathlib import Path
import numpy as np
from PIL import Image
from private_images import load,lua,decode,encode,signature

def key(pose,layer,index):return f'{pose}:{layer}:{index}'
def derivative(meta,stride):
    source=Image.fromarray(decode(meta));items=[];rects={}
    for pose,layers in meta['poses'].items():
        for layer,frames in layers.items():
            for index,rect in enumerate(frames,1):
                x,y,w,h,*_=rect;name=key(pose,layer,index)
                if w==0 or h==0:rects[name]=[0,0,0,0];continue
                crop=source.crop((x,y,x+w,y+h)).convert('RGBa').resize((max(1,math.ceil(w/stride)),max(1,math.ceil(h/stride))),Image.Resampling.BOX).convert('RGBA')
                items.append((name,crop))
    width=max(128,meta['width']//stride);x=y=1;row=0;placements=[]
    for name,crop in sorted(items,key=lambda item:(-item[1].height,item[0])):
        if x+crop.width+1>width:x=1;y+=row+2;row=0
        if y+crop.height+1>1024:raise ValueError('mask derivative exceeds one image')
        rects[name]=[x,y,crop.width,crop.height];placements.append((crop,x,y));x+=crop.width+2;row=max(row,crop.height)
    height=y+row+1;page=Image.new('RGBA',(width,height))
    for crop,x,y in placements:page.paste(crop,(x,y))
    return {'lod':stride,'sourceHash':signature(meta),'width':width,'height':height,'frame':48//stride,'rects':rects,'rle':encode(np.asarray(page))}
def generate(source,output):
    source,output=Path(source),Path(output);meta=load(source)
    if 'poses'not in meta or 'rle'not in meta:return []
    output.mkdir(parents=True,exist_ok=True);written=[]
    for stride in (2,4):
        result=derivative(meta,stride);dest=output/(source.stem+f'_Mip{stride}.luau')
        dest.write_text('-- Generated private cropped mask LOD. Logical pivots remain in the source.\nreturn '+lua(result)+'\n',encoding='utf-8',newline='\n');written.append(dest)
    return written
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path);parser.add_argument('--output',type=Path);args=parser.parse_args();total=0
    for source in sorted(args.source.glob('OrigMen*Fx.luau')):total+=len(generate(source,args.output or args.source))
    print(f'Generated {total} private cropped-mask derivatives')
if __name__=='__main__':main()
