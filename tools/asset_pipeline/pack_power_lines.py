"""Pack local source-generated pole pixels and neutral plant art into one ignored atlas.
python pack_power_lines.py <private power-art.json> <buildings-top.png> <output.luau>
"""
import base64,json,pathlib,sys,zlib
from PIL import Image
data=json.loads(pathlib.Path(sys.argv[1]).read_text());source=Image.open(sys.argv[2]).convert('RGBA')
meta=data.pop('plant');nodes=Image.frombytes('RGBA',(data['width'],data['height']),base64.b64decode(data.pop('rgba')))
size=meta['frame'];x,y=meta['x'],meta['y'];top=data['height']
atlas=Image.new('RGBA',(data['width'],top+size));atlas.paste(nodes,(0,0))
body=source.crop((x,y,x+size,y+size));paint=source.crop((x+size,y,x+2*size,y+size))
neutral=data['config']['look']['plant']['neutral'];tint=Image.new('RGBA',paint.size,neutral);tint.putalpha(paint.getchannel('A'))
body=Image.alpha_composite(body,tint);atlas.paste(body,(0,top))
shape=source.crop((x+2*size,y,x+3*size,y+size));shadow=Image.new('RGBA',shape.size,'white');shadow.putalpha(shape.getchannel('A'));atlas.paste(shadow,(size,top))
data['height']=atlas.height;data['plantRect']=[0,top,size,size];data['plantShadow']=[size,top,size,size]
def packed(im):
    c=zlib.compressobj(9,zlib.DEFLATED,-15);return base64.b64encode(c.compress(im.tobytes())+c.flush()).decode()
data['deflate']=packed(atlas)
half=atlas.resize((atlas.width//2,atlas.height//2),Image.Resampling.BOX)
data['half']={'width':half.width,'height':half.height,'deflate':packed(half)}
def lua(v):
    if isinstance(v,dict):return '{'+','.join('['+json.dumps(str(k))+']='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
    if isinstance(v,bool):return 'true' if v else 'false'
    return json.dumps(v)
out=pathlib.Path(sys.argv[3]);out.parent.mkdir(parents=True,exist_ok=True);out.write_text('-- GENERATED local-only original power layout/art.\nreturn '+lua(data)+'\n')
atlas.save(out.parent/'power-preview.png') if '--preview' in sys.argv else None
print('Packed power atlas:',atlas.width,atlas.height,'with',len(data['nodes'])-data['plantCount'],'nodes and',data['plantCount'],'neutral plants')
