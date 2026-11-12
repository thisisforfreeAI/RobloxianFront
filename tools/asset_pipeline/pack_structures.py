"""Pack locally extracted player-building art, without baking team colours.

python pack_structures.py <private.json> <buildings-top.png> <ignored-output.luau>
Original sprite coordinates/configuration stay in generated, ignored modules.
"""
import base64,json,pathlib,sys,zlib
from PIL import Image,ImageChops,ImageFilter

KINDS=('hq','barracks','factory','bunker','atgun','radar','sam','artybase','nightops')

def caster_mask(sheet,meta,bands):
    """Only source height masks cast shadows; ground in the colour sprite never does."""
    f=meta['frame'];x=meta['x'];y=meta['y'];alpha=Image.new('L',(f,f))
    for i,_ in enumerate(bands):
        mask=sheet.crop((x+(i+2)*f,y,x+(i+3)*f,y+f)).getchannel('A')
        alpha=ImageChops.lighter(alpha,mask)
    # APPROX: half-resolution coverage keeps the optional shadow small and retains thin fences.
    size=(max(1,f//2),max(1,f//2));alpha=alpha.resize(size,Image.Resampling.BOX)
    image=Image.new('RGBA',size,(255,255,255,0));image.putalpha(alpha)
    return image

def lua(value):
    if isinstance(value,dict):return '{'+','.join('['+json.dumps(str(k))+']='+lua(v) for k,v in value.items())+'}'
    if isinstance(value,(list,tuple)):return '{'+','.join(map(lua,value))+'}'
    if value is None:return 'nil'
    if isinstance(value,bool):return 'true' if value else 'false'
    return json.dumps(value)

def packed(raw):
    compress=zlib.compressobj(9,zlib.DEFLATED,-15)
    return base64.b64encode(compress.compress(raw)+compress.flush()).decode()

def effect_source(sheet,normal,meta,config):
    f=meta['frame'];x=meta['x'];y=meta['y'];n=max(1,round(f*config['scale']))
    crop=normal.crop((round(x*config['scale']),round(y*config['scale']),round(x*config['scale'])+n,round(y*config['scale'])+n))
    present=crop.getchannel('A').point(lambda a:1 if a>=64 else 0)
    # The source reads its height texture through an 8-bit premultiplied Canvas2D surface.
    # Preserve that round trip at translucent fences, where a one-level shift changes scaffolding.
    height=Image.frombytes('L',(n,n),bytes(
        min(255,(((b*a+127)//255)*255*2+a)//(2*a)) if a>=64 else 0
        for b,a in zip(crop.getchannel('B').tobytes(),crop.getchannel('A').tobytes())))
    radius=config['wallReach'];low=height.filter(ImageFilter.MinFilter(radius*2+1))
    raw=(sheet.crop((x,y,x+f,y+f)).tobytes()+sheet.crop((x+f,y,x+2*f,y+f)).tobytes()+
         height.tobytes()+low.tobytes()+present.tobytes()+
         sheet.crop((x+2*f,y,x+3*f,y+f)).getchannel('A').tobytes()+
         sheet.crop((x+3*f,y,x+4*f,y+f)).getchannel('A').tobytes())
    return {'n':n,'top':height.getextrema()[1],'size':len(raw),'deflate':packed(raw)}

def pack(data,sheet,normal=None):
    atlas=data['atlas'];output={}
    def latest(name,group):return name+'@2' if name+'@2' in group else name
    for army in ('coalition','republic'):
        tiles=[];looks={}
        def tile(image):
            box=image.getbbox()
            if not box:return None
            key=len(tiles)+1;tiles.append((image.crop(box),box));return key
        def part(name,heading=0):
            name=latest(name,atlas['parts']);m=atlas['parts'][name];f=m['frame'];x=m['x']+heading*f;y=m['y']
            return (sheet.crop((x,y,x+f,y+f)),sheet.crop((x,y+f,x+f,y+2*f)),m)
        def paste_part(body,paint,name,where,cells,heading=0):
            b,p,m=part(name,heading);size=round(m['cells']*body.width/cells)
            pos=(round((where[0]+.5)*body.width-size/2),round((where[1]+.5)*body.width-size/2))
            for dest,src in ((body,b),(paint,p)):dest.alpha_composite(src.resize((size,size),Image.Resampling.NEAREST),pos)
        for kind in KINDS:
            name='rep_'+kind if army=='republic' and 'rep_'+kind in atlas['buildings'] else kind
            actual=latest(name,atlas['buildings']);m=atlas['buildings'][actual];f=m['frame'];x=m['x'];y=m['y'];cells=m['cells']
            b=sheet.crop((x,y,x+f,y+f));p=sheet.crop((x+f,y,x+2*f,y+f))
            pos=data['positions']['republic' if name.startswith('rep_') else 'coalition'][kind]
            if kind in data['gun']:
                gun=data['gun'][kind]['part']
                if name.startswith('rep_') and kind=='sam':gun='rep_'+gun
                if kind=='sam':gun+='2'
                point=pos.get('launcher',pos.get('gun'));paste_part(b,p,gun,(point['x']-.5,point['y']-.5),cells)
                if m.get('cap'):
                    cap=x+f*(3+len(atlas['bands']))
                    b.alpha_composite(sheet.crop((cap,y,cap+f,y+f)));p.alpha_composite(sheet.crop((cap+f,y,cap+2*f,y+f)))
            if kind=='artybase':
                cfg=data['artillery']
                for key in ('gun','pod'):
                    partname=cfg['parts'][key][0];meta=atlas['parts'][latest(partname,atlas['parts'])]
                    heading=round((cfg['rest']%(2*3.141592653589793))/(2*3.141592653589793)*meta['headings'])%meta['headings']
                    paste_part(b,p,partname,tuple(v/cells for v in cfg[key]),cells,heading)
            if kind=='factory':
                door=pos['door'];db,dp,dm=part('factory-door');ratio=f/cells
                # Source door art occupies a centred subrect; closed doors are the resting pose.
                crop=(round((dm['frame']-.72*dm['frame']/dm['cells'])/2),round((dm['frame']-.32*dm['frame']/dm['cells'])/2))
                size=(round(door['w']*f/2),round(.34*ratio));target=(round((door['x']-door['w']/2)*f),round(door['y']*f-.34*ratio))
                for dest,src in ((b,db),(p,dp)):
                    cut=src.crop((*crop,round(crop[0]+.72*dm['frame']/dm['cells']),round(crop[1]+.32*dm['frame']/dm['cells'])))
                    cut=cut.resize(size,Image.Resampling.NEAREST)
                    dest.alpha_composite(cut,target);dest.alpha_composite(cut,(target[0]+size[0],target[1]))
                if not name.startswith('rep_'):
                    crane=pos['crane'];paste_part(b,p,'factory-crane',(crane['x']-.5,crane['y']-.5),cells)
            look={'cells':cells,'frame':f,'base':tile(b),'paint':tile(p),'night':tile(sheet.crop((x+f*(2+len(atlas['bands'])),y,x+f*(3+len(atlas['bands'])),y+f))),'sourceName':actual}
            shadow=caster_mask(sheet,m,atlas['bands'])
            look['shadow']={'tile':tile(shadow),'frame':shadow.width}
            look['defence']=kind in ('bunker','atgun','radar','sam','nightops')
            if normal is not None:look['effects']=effect_source(sheet,normal,m,data['construction'])
            if kind in data['dish'] and not (name.startswith('rep_') and kind=='sam'):
                cfg=data['dish'][kind];partname=('rep_' if name.startswith('rep_') else '')+cfg['part'];meta=atlas['parts'][latest(partname,atlas['parts'])]
                point=pos['dish'];frames=[]
                for heading in range(meta['headings']):
                    db,dp,_=part(partname,heading);frames.append({'base':tile(db),'paint':tile(dp)})
                look['dish']={'frames':frames,'frame':meta['frame'],'cells':meta['cells'],'x':(point['x']-.5)*cells,'y':(point['y']-.5)*cells,'speed':cfg['turnsPerSec']}
            looks[kind]=look
        # Skyline packing of cropped pixels. Two transparent guard pixels prevent neighbouring bleed.
        width=1024;heights=[0]*width;rects={};canvas=Image.new('RGBA',(width,1024))
        for index,(image,box) in sorted(enumerate(tiles,1),key=lambda item:-max(item[1][0].size)):
            w,h=image.size;best=min((max(heights[x:x+w+4]),x) for x in range(width-w-3));y,x=best
            if y+h+4>1024:raise ValueError('Structure atlas exceeds one image: '+army)
            canvas.paste(image,(x+2,y+2));heights[x:x+w+4]=[y+h+4]*(w+4)
            rects[index]=[x+2,y+2,w,h,box[0],box[1]]
        height=max(heights);canvas=canvas.crop((0,0,width,height));compress=zlib.compressobj(9,zlib.DEFLATED,-15)
        encoded=base64.b64encode(compress.compress(canvas.tobytes())+compress.flush()).decode()
        output[army]={'width':width,'height':height,'deflate':encoded,'rects':rects,'looks':looks}
        print(army,len(tiles),'tiles',width,height,'RGBA bytes',width*height*4)
    return {'armies':output,'nightAlpha':data['nightAlpha'],'construction':data.get('construction'),'damage':data.get('damage')}

if __name__=='__main__':
    data=json.loads(pathlib.Path(sys.argv[1]).read_text());sheet=Image.open(sys.argv[2]).convert('RGBA')
    normal=Image.open(pathlib.Path(sys.argv[2]).with_name('buildings-normal.png')).convert('RGBA')
    result=pack(data,sheet,normal);out=pathlib.Path(sys.argv[3]);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text('--!strict\n-- GENERATED local-only original structure pixels and metadata.\nreturn '+lua(result)+'\n')
