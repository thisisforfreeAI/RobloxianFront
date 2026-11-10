"""Pack local original fort sprites and source-generated layouts into an ignored module.
python pack_forts.py <private-forts.json> <buildings-top.png> <output module>
"""
import base64,json,math,pathlib,sys,zlib
from PIL import Image
data=json.loads(pathlib.Path(sys.argv[1]).read_text());sheet=Image.open(sys.argv[2]).convert('RGBA')
names=sorted(data['sprites']);w,h=8*48,math.ceil(len(names)/8)*48
body,paint=Image.new('RGBA',(w,h)),Image.new('RGBA',(w,h));rects={}
for i,name in enumerate(names):
    meta=data['sprites'][name];assert meta['frame']==48
    x,y=meta['x'],meta['y'];to=(i%8*48,i//8*48)
    body.paste(sheet.crop((x,y,x+48,y+48)),to);paint.paste(sheet.crop((x+48,y,x+96,y+48)),to)
    rects[name]=list(to)+[48,48]
def packed(im):
    c=zlib.compressobj(9,zlib.DEFLATED,-15)
    return base64.b64encode(c.compress(im.tobytes())+c.flush()).decode()
def lua(v):
    if isinstance(v,dict):return '{'+','.join('['+json.dumps(str(k))+']='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
    return json.dumps(v)
out=pathlib.Path(sys.argv[3]);out.parent.mkdir(parents=True,exist_ok=True)
out.write_text('--!strict\n-- GENERATED local-only original fort art and layout.\nreturn '+lua({'width':w,'height':h,'deflate':packed(body),'paint':packed(paint),'rects':rects,'layouts':data['layouts'],'config':data['config']})+'\n')
print('Packed',len(names),'source fort sprites',w,h)
