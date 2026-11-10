"""Pack local original city/road night-light fields (original-derived output stays ignored).
python pack_night_lights.py <city> <worker-map.json> <private/night-look.json> <output.luau>
Fields: R eligible window/lamp; G highway body; B near street/highway pool; A dithered city glow.
APPROX: source shader geometry is sampled at fine-texel centres; road IDs/urban interpolation and
capsule endpoints replace its full junction/road-list shader. Runtime keeps source window flicker.
"""
import base64,json,math,pathlib,struct,sys,zlib
import numpy as np
from PIL import Image,ImageFilter

def window_shapes(head,parts,w,h,look):
    """Retain original pixel silhouettes; share repeated fine-cell fragments in a small atlas.
    APPROX: padded soft halo/core opacity are the owner's brighter-glow rendering adaptation.
    """
    size=head['size'];fine=look['fine'];pad=3;slot=12
    assert size==14 and fine==3,'window atlas requires repacking policy for another tile size'
    index=np.frombuffer(parts['index'],np.uint8).reshape(h,w,4).astype(np.int64)
    ids=index[:,:,0]+(index[:,:,1]<<8)+(index[:,:,2]<<16)
    atlas=np.frombuffer(parts['atlas'],np.uint8).reshape(head['atlasH'],head['atlasW'],4)
    codes=atlas[:,:,3];eligible=((codes>=look['roofFrom']) & (codes%2==0)) | (codes==look['lamp'])
    cuts=[0]+[math.ceil(i*size/fine-.5) for i in range(1,fine)]+[size]
    patterns=[];lookup={};points=[];coverage=np.zeros((h*fine,w*fine),np.uint8)
    for y,x in zip(*np.where(ids>0)):
        tile=int(ids[y,x]-1);tx=(tile%head['perRow'])*size;ty=(tile//head['perRow'])*size
        tile_mask=eligible[ty:ty+size,tx:tx+size]
        if not tile_mask.any():continue
        for fy in range(fine):
            for fx in range(fine):
                patch=tile_mask[cuts[fy]:cuts[fy+1],cuts[fx]:cuts[fx+1]]
                if not patch.any():continue
                coverage[y*fine+fy,x*fine+fx]=round(float(patch.mean())*255)
                mask=np.zeros((slot,slot),np.uint8)
                mask[pad:pad+patch.shape[0],pad:pad+patch.shape[1]]=patch*255
                key=mask.tobytes()
                if key not in lookup:
                    lookup[key]=len(patterns)
                    halo=np.asarray(Image.fromarray(mask).filter(ImageFilter.GaussianBlur(1.1)))
                    alpha=np.maximum(np.round(mask*.96),np.round(halo*.8)).astype(np.uint8)
                    rgba=np.full((slot,slot,4),255,np.uint8);rgba[:,:,3]=alpha
                    patterns.append(rgba)
                points.append([int(x*size+cuts[fx]-pad),int(y*size+cuts[fy]-pad),int(x*fine+fx),int(y*fine+fy),lookup[key]])
    per=32;rows=max(1,math.ceil(len(patterns)/per));assert rows*slot<=1024
    sheet=np.zeros((rows*slot,per*slot,4),np.uint8)
    for i,pattern in enumerate(patterns):sheet[(i//per)*slot:(i//per+1)*slot,(i%per)*slot:(i%per+1)*slot]=pattern
    return {'width':sheet.shape[1],'height':sheet.shape[0],'slot':slot,'perRow':per,'pixelsPerCell':size,'points':points},sheet,coverage

def read_city(path):
    b=pathlib.Path(path).read_bytes();assert b[:4]==b'WFCT'
    size=struct.unpack_from('<I',b,4)[0];head=json.loads(b[8:8+size]);at=8+size;parts={}
    for p in head['parts']:
        raw=zlib.decompress(b[at:at+p['packed']],-15);at+=p['packed'];assert len(raw)==p['raw'];parts[p['name']]=raw
    return head,parts

def plain(value):
    return value['data'] if isinstance(value,dict) else value

def windows(head,parts,w,h,look):
    scale=look['fine'];tile_size=head['size'];per=head['perRow']
    index=np.frombuffer(parts['index'],np.uint8).reshape(h,w,4).astype(np.int64)
    ids=index[:,:,0]+(index[:,:,1]<<8)+(index[:,:,2]<<16)
    atlas=np.frombuffer(parts['atlas'],np.uint8).reshape(head['atlasH'],head['atlasW'],4)
    x,y=np.arange(w*scale)[None,:],np.arange(h*scale)[:,None]
    tile=ids[y//scale,x//scale];safe=np.maximum(tile-1,0)
    sx=np.floor(((x+.5)/scale%1)*tile_size).astype(int)
    sy=np.floor(((y+.5)/scale%1)*tile_size).astype(int)
    code=np.where(tile>0,atlas[(safe//per)*tile_size+sy,(safe%per)*tile_size+sx,3],0)
    return ((code>=look['roofFrom']) & (code%2==0)) | (code==look['lamp'])

def sample_cells(values,scale):
    h,w=values.shape
    x=(np.arange(w*scale)[None,:]+.5)/scale-.5;y=(np.arange(h*scale)[:,None]+.5)/scale-.5
    ix,iy=np.floor(x).astype(int),np.floor(y).astype(int);fx,fy=x-ix,y-iy
    def at(dx,dy):return values[np.clip(iy+dy,0,h-1),np.clip(ix+dx,0,w-1)]
    return ((at(0,0)*(1-fx)+at(1,0)*fx)*(1-fy)+(at(0,1)*(1-fx)+at(1,1)*fx)*fy)

def city_glow(urban,look):
    values=urban.astype(np.float64);radius=look['glowRadius']
    for _ in range(2):
        pad=np.pad(values,((0,0),(radius,radius)),mode='edge')
        values=sum(pad[:,i:i+urban.shape[1]] for i in range(radius*2+1))/(radius*2+1)
        pad=np.pad(values,((radius,radius),(0,0)),mode='edge')
        values=sum(pad[i:i+urban.shape[0],:] for i in range(radius*2+1))/(radius*2+1)
    values=np.round(np.clip(values*look['glowGain'],0,1)*255)/255
    soft=sample_cells(values,look['fine'])
    y,x=np.indices(soft.shape)
    def b2(x,y):return 2*x+3*y-4*x*y
    dither=(4*b2(x%2,y%2)+b2((x//2)%2,(y//2)%2)+.5)/16
    return np.clip(np.floor(soft*4+.2+.6*dither)/4,0,1)

def road_lights(m,urban,look):
    scale=look['fine'];w,h=m['width']*scale,m['height']*scale
    fields={k:{'d':np.full((h,w),np.inf),'along':np.zeros((h,w)),'seed':np.zeros((h,w))} for k in ('major','minor')}
    for road_id,road in enumerate(m['roads']):
        cls='major' if road.get('rank',0)>=2 else 'track' if road.get('track') else 'minor'
        if cls=='track':continue
        p=plain(road['pts']);run=0;field=fields[cls]
        reach=look['reach'] if cls=='major' else look['streetLamps']['halo']
        for i in range(2,len(p)-1,2):
            ax,ay,bx,by=p[i-2:i+2];dx,dy=bx-ax,by-ay;length=math.hypot(dx,dy)
            if not length:continue
            x0,x1=max(0,math.floor((min(ax,bx)-reach)*scale)),min(w,math.ceil((max(ax,bx)+reach)*scale))
            y0,y1=max(0,math.floor((min(ay,by)-reach)*scale)),min(h,math.ceil((max(ay,by)+reach)*scale))
            if x0>=x1 or y0>=y1:run+=length;continue
            x=(np.arange(x0,x1)[None,:]+.5)/scale;y=(np.arange(y0,y1)[:,None]+.5)/scale
            t=np.clip(((x-ax)*dx+(y-ay)*dy)/(length*length),0,1)
            distance=np.hypot(x-ax-t*dx,y-ay-t*dy);area=np.s_[y0:y1,x0:x1];near=distance<field['d'][area]
            field['d'][area][near]=distance[near];field['along'][area][near]=(run+t*length)[near]
            field['seed'][area][near]=((road_id*2654435761)&0xffffffff)/4294967296
            run+=length
    major,minor=fields['major'],fields['minor']
    coverage=np.clip((look['widths']['major']['half']+.5/scale-major['d'])*scale,0,1)
    def pool(field,period,radius,phase=0):
        along=((field['along']/period+phase)%1-.5)*period
        t=np.clip(np.hypot(along,field['d'])/radius,0,1)
        return (1-t*t*(3-2*t))**2
    halo=pool(major,look['lamps']['every'],look['lamps']['halo'],major['seed'])*look['lamps']['haloStrength']*look['lampHalo']
    town=sample_cells(urban.astype(float),scale)
    street=pool(minor,look['streetLamps']['every'],look['streetLamps']['halo'])*look['streetLamps']['strength']*town
    pools=np.where(major['d']<look['reach'],halo,street)
    return coverage,np.clip(pools,0,1)

def generate(city,map_path,settings,out):
    head,parts=read_city(city);m=json.loads(pathlib.Path(map_path).read_text());look=json.loads(pathlib.Path(settings).read_text())
    w,h=m['width'],m['height'];scale=look['fine']
    assert head['key'].split(':')[1]==f'{w}x{h}'
    urban=np.array(plain(m['urban'])).reshape(h,w)
    fields=np.zeros((h*scale,w*scale,4),np.uint8)
    detail,sheet,coverage=window_shapes(head,parts,w,h,look)
    fields[:,:,0]=coverage
    coverage,pools=road_lights(m,urban,look)
    fields[:,:,1]=np.round(coverage*255).astype(np.uint8);fields[:,:,2]=np.round(pools*255).astype(np.uint8)
    fields[:,:,3]=np.round(city_glow(urban,look)*255).astype(np.uint8)
    compressor=zlib.compressobj(9,zlib.DEFLATED,-15);packed=base64.b64encode(compressor.compress(fields.tobytes())+compressor.flush()).decode()
    target=pathlib.Path(out);target.parent.mkdir(parents=True,exist_ok=True)
    compressor=zlib.compressobj(9,zlib.DEFLATED,-15)
    detail['deflate']=base64.b64encode(compressor.compress(sheet.tobytes())+compressor.flush()).decode()
    def lua(v):
        if isinstance(v,dict):return '{'+','.join('['+json.dumps(k)+']='+lua(x) for k,x in v.items())+'}'
        if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
        return json.dumps(v)
    target.write_text('--!strict\n-- GENERATED local-only original night-light fields and pixel-aligned window shapes.\nreturn {'+f'width={w*scale},height={h*scale},mapWidth={w},mapHeight={h},scale={scale},deflate="{packed}",windows='+lua(detail)+'}\n')
    print('Night fields:',w*scale,h*scale,'window candidates',int((fields[:,:,0]>0).sum()),'road/pool texels',int(((fields[:,:,1]>0)|(fields[:,:,2]>0)).sum()))
    print('Window atlas:',sheet.shape[1],sheet.shape[0],'patterns',len(set(p[4] for p in detail['points'])),'fragments',len(detail['points']))
    return fields

if __name__=='__main__':generate(*sys.argv[1:])
