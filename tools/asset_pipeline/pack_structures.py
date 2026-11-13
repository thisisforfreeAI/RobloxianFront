"""Pack locally extracted player-building art, without baking team colours.

python pack_structures.py <private.json> <buildings-top.png> <ignored-output.luau>
Original sprite coordinates/configuration stay in generated, ignored modules.
"""
import base64,copy,io,json,pathlib,sys,zlib
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

def shadow_source(sheet,meta,bands):
    """Only the original height masks enter projected shadows, never body/paint/ground art."""
    if 'reach' not in meta:return None
    f=meta['frame'];x=meta['x'];y=meta['y']
    if len(meta['reach'])!=len(bands):raise ValueError('Shadow band/reach mismatch')
    raw=b''.join(sheet.crop((x+(i+2)*f,y,x+(i+3)*f,y+f)).getchannel('A').tobytes() for i in range(len(bands)))
    return {'frame':f,'bands':bands,'reach':meta['reach'],'size':len(raw),'deflate':packed(raw)}

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

def factory_layout(config,positions,cells,frame,republic,fps):
    result=copy.deepcopy(config);door=positions['door'];x=(door['x']-.5)*cells;y=(door['y']-.5)*cells;thickness=.34
    result['doors']=[[x+side*door['w']*cells/4,y-thickness/2,door['w']*cells/2,thickness] for side in (-1,1)]
    result['crane'].update(x=(positions['crane']['x']-.5)*cells,y=(positions['crane']['y']-.5)*cells,run=positions['crane']['run']*cells)
    weld=positions['weld'];result['weld'].update(x0=(weld['x']-.5)*cells,y0=(weld['y']-.5)*cells,x1=(weld['x']+weld['w']-.5)*cells,y1=(weld['y']+weld['h']-.5)*cells)
    result.update(craneOff=republic,cells=cells,frame=frame,fps=fps)
    return result

def pack_tiles(tiles,width=1024,compact=False):
    # Two transparent guard pixels prevent neighbouring bleed. Never rotate/resample art.
    ordered=sorted(enumerate(tiles,1),key=lambda item:-max(item[1][0].size))
    heights=[0]*width;placements={};candidates=[]
    for index,(image,box) in ordered:
        w,h=image.size
        if w+4>width:break
        y,x=min((max(heights[x:x+w+4]),x) for x in range(width-w-3))
        if y+h+4>1024:break
        placements[index]=(x,y);heights[x:x+w+4]=[y+h+4]*(w+4)
    else:candidates.append((max(heights),placements))
    if compact:
        # Offline maximal free rectangles reclaim holes the skyline cannot use. Try stable
        # orderings and retain the shortest valid layout, including the old skyline candidate.
        for key in (lambda v:-max(v[1][0].size),lambda v:-v[1][0].width*v[1][0].height,lambda v:-v[1][0].height):
            free=[(0,0,width,1024)];placements={};height=0
            for index,(image,box) in sorted(enumerate(tiles,1),key=key):
                w,h=image.width+4,image.height+4
                fits=[(min(fw-w,fh-h),max(fw-w,fh-h),fy,fx) for fx,fy,fw,fh in free if fw>=w and fh>=h]
                if not fits:break
                _,_,y,x=min(fits);placements[index]=(x,y);height=max(height,y+h);split=[]
                for fx,fy,fw,fh in free:
                    if x>=fx+fw or x+w<=fx or y>=fy+fh or y+h<=fy:split.append((fx,fy,fw,fh));continue
                    if x>fx:split.append((fx,fy,x-fx,fh))
                    if x+w<fx+fw:split.append((x+w,fy,fx+fw-x-w,fh))
                    if y>fy:split.append((fx,fy,fw,y-fy))
                    if y+h<fy+fh:split.append((fx,y+h,fw,fy+fh-y-h))
                split=list(dict.fromkeys(split));free=[]
                for i,(fx,fy,fw,fh) in enumerate(split):
                    if not any(i!=j and fx>=ax and fy>=ay and fx+fw<=ax+aw and fy+fh<=ay+ah for j,(ax,ay,aw,ah) in enumerate(split)):free.append((fx,fy,fw,fh))
            else:candidates.append((height,placements))
    if not candidates:raise ValueError('Sprite atlas exceeds one image')
    height,placements=min(candidates,key=lambda candidate:candidate[0]);rects={};canvas=Image.new('RGBA',(width,height))
    for index,(image,box) in enumerate(tiles,1):
        x,y=placements[index];w,h=image.size;canvas.paste(image,(x+2,y+2));rects[index]=[x+2,y+2,w,h,box[0],box[1]]
    return {'width':width,'height':height,'deflate':packed(canvas.tobytes()),'rects':rects}

def weapon_parts(data,sheet,names=None,width=512):
    tiles=[];parts={}
    for name in names or [data['gun'][kind]['part'] for kind in ('atgun','bunker')]:
        actual=name+'@2' if name+'@2' in data['atlas']['parts'] else name
        m=data['atlas']['parts'][actual];f=m['frame'];frames=[]
        for heading in range(m['headings']):
            frame={}
            for layer in range(2):
                x=m['x']+heading*f;y=m['y']+layer*f;image=sheet.crop((x,y,x+f,y+f));box=image.getbbox()
                if box:tiles.append((image.crop(box),box));frame['base' if layer==0 else 'paint']=len(tiles)
            frames.append(frame)
        parts[name]={'frames':frames,'frame':f,'cells':m['cells'],'tall':m['tall'],'sourceName':actual}
    result=pack_tiles(tiles,width);result['parts']=parts
    print('Shared weapon parts',len(tiles),'tiles',result['width'],result['height'],'RGBA bytes',result['width']*result['height']*4)
    return result

def pack_badges(data):
    if not data:return None
    tiles=[];dedup={};icons={}
    for name,source in data['images'].items():
        icon={'frame':source['frame']}
        for layer in ('back','ink','fill','face','ghost'):
            if layer not in source:continue
            key=(source['frame'],source[layer])
            if key not in dedup:
                image=Image.open(io.BytesIO(base64.b64decode(source[layer]))).convert('RGBA')
                if image.size!=(source['frame'],source['frame']):raise ValueError('Bad building token dimensions')
                box=image.getbbox()
                if not box:raise ValueError('Empty building token layer')
                tiles.append((image.crop(box),box));dedup[key]=len(tiles)
            icon[layer]=dedup[key]
        icons[name]=icon
    status={}
    for name,source in data.get('status',{}).items():
        image=Image.open(io.BytesIO(base64.b64decode(source['image']))).convert('RGBA')
        if image.size!=(source['frame'],source['frame']):raise ValueError('Bad status icon dimensions')
        box=image.getbbox()
        if not box:raise ValueError('Empty status icon')
        tiles.append((image.crop(box),box));status[name]={'frame':source['frame'],'tile':len(tiles)}
    result=pack_tiles(tiles,512,compact=True);result['looks']={kind:icons[data['mapping'][kind]] for kind in KINDS};result['status']=status
    print('Shared building tokens',len(tiles),'tiles',result['width'],result['height'],'RGBA bytes',result['width']*result['height']*4)
    return result

def pack(data,sheet,normal=None):
    atlas=data['atlas'];output={};tokens=pack_badges(data.get('badges'))
    def latest(name,group):return name+'@2' if name+'@2' in group else name
    for army in ('coalition','republic'):
        tiles=[];looks={}
        def tile(image,trim=True):
            box=image.getbbox() if trim else (0,0,image.width,image.height)
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
            moving=bool(data.get('gunMotion')) and (kind in ('atgun','bunker') or kind=='sam' and bool(data['gunMotion'].get('sam')))
            if kind in data['gun'] and not moving:
                gun=data['gun'][kind]['part']
                if name.startswith('rep_') and kind=='sam':gun='rep_'+gun
                if kind=='sam':gun+='2'
                point=pos.get('launcher',pos.get('gun'));paste_part(b,p,gun,(point['x']-.5,point['y']-.5),cells)
                if m.get('cap'):
                    cap=x+f*(3+len(atlas['bands']))
                    b.alpha_composite(sheet.crop((cap,y,cap+f,y+f)));p.alpha_composite(sheet.crop((cap+f,y,cap+2*f,y+f)))
            if kind=='artybase' and not data['artillery'].get('motion'):
                cfg=data['artillery']
                for key in ('gun','pod'):
                    partname=cfg['parts'][key][0];meta=atlas['parts'][latest(partname,atlas['parts'])]
                    heading=round((cfg['rest']%(2*3.141592653589793))/(2*3.141592653589793)*meta['headings'])%meta['headings']
                    paste_part(b,p,partname,tuple(v/cells for v in cfg[key]),cells,heading)
            if kind=='factory' and not data.get('factory'):
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
            if data.get('site'):
                # APPROX: half-resolution alpha, shared in the existing core image; body art is unchanged.
                alpha=sheet.crop((x,y,x+f,y+f)).getchannel('A').resize((f//2,f//2),Image.Resampling.BOX)
                mask=Image.new('RGBA',alpha.size,(255,255,255,0));mask.putalpha(alpha)
                look['siteMask']={'tile':tile(mask),'frame':mask.width}
            shadow=caster_mask(sheet,m,atlas['bands'])
            look['shadow']={'tile':tile(shadow),'frame':shadow.width,'source':shadow_source(sheet,m,atlas['bands'])}
            look['defence']=kind in ('bunker','atgun','radar','sam','nightops')
            if normal is not None:look['effects']=effect_source(sheet,normal,m,data['construction'])
            if moving:
                cfg=copy.deepcopy(data['gun'][kind]);cfg.update(data['gunMotion'])
                point=pos.get('launcher',pos.get('gun'));cfg.update(x=(point['x']-.5)*cells,y=(point['y']-.5)*cells,kind=kind,shadowScale=data['shadow']['shadowPerHeight'],shadowInk=data['shadow']['ink'])
                fallback=cfg['part']
                if kind=='sam':
                    prefix='rep_' if name.startswith('rep_') else ''
                    cfg['parts']=[prefix+cfg['part']+str(stage) for stage in range(3)]
                    cfg['bank']='$sam:'+army;fallback=cfg['parts'][2]
                gb,gp,gm=part(fallback);cfg['fallback']={'base':tile(gb),'paint':tile(gp)}
                cfg['frame']=gm['frame'];cfg['cells']=gm['cells'];cfg['tall']=gm['tall'];cfg['footprint']=cells
                if m.get('cap'):
                    cap=x+f*(3+len(atlas['bands']))
                    cfg['cap']={'base':tile(sheet.crop((cap,y,cap+f,y+f))),'paint':tile(sheet.crop((cap+f,y,cap+2*f,y+f)))}
                look['gun']=cfg
            if kind=='artybase' and data['artillery'].get('motion'):
                cfg=copy.deepcopy(data['artillery']);cfg.update(cells=cells,slots=[])
                for key in ('gun','pod'):
                    partname=cfg['parts'][key][0];gm=atlas['parts'][latest(partname,atlas['parts'])]
                    heading=round((cfg['rest']%(2*3.141592653589793))/(2*3.141592653589793)*gm['headings'])%gm['headings']
                    gb,gp,_=part(partname,heading)
                    cfg['slots'].append({'kind':'artillery','part':partname,'x':cfg[key][0],'y':cfg[key][1],
                        'frame':gm['frame'],'cells':gm['cells'],'tall':gm['tall'],'footprint':cells,'initialStep':0,
                        'shadowScale':data['shadow']['shadowPerHeight'],'shadowInk':data['shadow']['ink'],
                        'fallback':{'base':tile(gb),'paint':tile(gp)}})
                look['artillery']=cfg
            if kind=='factory' and data.get('factory'):
                factory=factory_layout(data['factory'],pos,cells,f,name.startswith('rep_'),data['factoryFps'])
                db,dp,dm=part('factory-door');factory['door']={'base':tile(db,False),'paint':tile(dp,False),'frame':dm['frame'],'cells':dm['cells']}
                if not factory['craneOff']:
                    cb,cp,cm=part('factory-crane');factory['craneArt']={'base':tile(cb,False),'paint':tile(cp,False),'frame':cm['frame'],'cells':cm['cells']}
                look['factory']=factory
            if kind in data['dish'] and not (name.startswith('rep_') and kind=='sam'):
                cfg=data['dish'][kind];partname=('rep_' if name.startswith('rep_') else '')+cfg['part'];meta=atlas['parts'][latest(partname,atlas['parts'])]
                point=pos['dish'];frames=[]
                for heading in range(meta['headings']):
                    db,dp,_=part(partname,heading);frames.append({'base':tile(db),'paint':tile(dp)})
                look['dish']={'frames':frames,'frame':meta['frame'],'cells':meta['cells'],'x':(point['x']-.5)*cells,'y':(point['y']-.5)*cells,'speed':cfg['turnsPerSec']}
            looks[kind]=look
            if tokens:look['badge']=tokens['looks'][kind]
        output[army]=pack_tiles(tiles,compact=True)
        output[army]['looks']=looks
        print(army,len(tiles),'tiles',output[army]['width'],output[army]['height'],'RGBA bytes',output[army]['width']*output[army]['height']*4)
    launchers=None
    if data.get('gunMotion',{}).get('sam'):
        launchers={army:weapon_parts(data,sheet,[('rep_' if army=='republic' else '')+data['gun']['sam']['part']+str(stage) for stage in range(3)]) for army in ('coalition','republic')}
    artillery=weapon_parts(data,sheet,[name for names in data['artillery']['parts'].values() for name in names],1024) if data['artillery'].get('motion') else None
    return {'shadowProjection':data.get('shadow'),'badges':tokens,'armies':output,'nightAlpha':data['nightAlpha'],'construction':data.get('construction'),'damage':data.get('damage'),'weapons':weapon_parts(data,sheet) if data.get('gunMotion') else None,'launchers':launchers,'artillery':artillery,'site':data.get('site')}

if __name__=='__main__':
    data=json.loads(pathlib.Path(sys.argv[1]).read_text());sheet=Image.open(sys.argv[2]).convert('RGBA')
    normal=Image.open(pathlib.Path(sys.argv[2]).with_name('buildings-normal.png')).convert('RGBA')
    result=pack(data,sheet,normal);out=pathlib.Path(sys.argv[3]);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text('--!strict\n-- GENERATED local-only original structure pixels and metadata.\nreturn '+lua(result)+'\n')
