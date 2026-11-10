"""Connected road raster for the local town packer; no original data is embedded here.

Source look tables are supplied by export_roads.cjs. APPROX: capsule unions replace the original
GPU junction distance fields/fillets; traffic lights, bridges, roundabouts and damage are pending.
"""
import numpy as np


def points(road):
    p = road['pts']
    return p['data'] if isinstance(p, dict) else p


def kind(road):
    return 'major' if road.get('rank', 0) >= 2 else 'track' if road.get('track') else 'minor'


def color(hex_value):
    return np.array([int(hex_value[i:i+2], 16) for i in (1, 3, 5)], np.float32)


def hash21(x, y):
    a, b, c = (x*.1031) % 1, (y*.1030) % 1, (x*.0973) % 1
    mix = a*(b+33.33) + b*(c+33.33) + c*(a+33.33)
    return ((a+b+2*mix)*(c+mix)) % 1


def road_layer(m, config, cx, cy, width, height, scale):
    """RGBA + pavement mask for any map rectangle. Geometry is sampled in global cell coordinates."""
    settings, look, roads = config['widths'], config['look'], config['roads']
    aa = .5/scale
    x = cx + (np.arange(width, dtype=np.float32)[None, :]+.5)/scale
    y = cy + (np.arange(height, dtype=np.float32)[:, None]+.5)/scale
    segments = []
    for road in m['roads']:
        cls = kind(road)
        reach = sum(settings[cls].values()) + look['mouth'] + aa
        p, run = points(road), 0
        for i in range(2, len(p)-1, 2):
            ax, ay, bx, by = p[i-2:i+2]
            length = float(np.hypot(bx-ax, by-ay))
            if not length:
                continue
            if (max(ax,bx)+reach >= cx and min(ax,bx)-reach <= cx+width/scale and
                    max(ay,by)+reach >= cy and min(ay,by)-reach <= cy+height/scale):
                segments.append((cls, ax, ay, (bx-ax)/length, (by-ay)/length, length, run))
            run += length

    def geometry(s):
        _, ax, ay, dx, dy, length, run = s
        along = (x-ax)*dx+(y-ay)*dy
        t = np.clip(along, 0, length)
        distance = np.hypot(x-ax-t*dx, y-ay-t*dy)
        return distance, along+run, (along >= 0) & (along <= length)

    fields = {}
    score = np.full((height,width), np.inf, np.float32)
    direction_x, direction_y = np.zeros_like(score), np.zeros_like(score)
    for cls in ('track','minor','major'):
        dist = np.full_like(score, np.inf)
        along, dx_field, dy_field = np.zeros_like(score), np.zeros_like(score), np.zeros_like(score)
        inside = np.zeros(score.shape, bool)
        for s in segments:
            if s[0] != cls:
                continue
            d, run, on_segment = geometry(s)
            nearer = d < dist
            dist[nearer], along[nearer] = d[nearer], run[nearer]
            dx_field[nearer], dy_field[nearer] = s[3], s[4]
            inside[nearer] = on_segment[nearer]
        nearer = dist-settings[cls]['half'] < score
        score[nearer] = dist[nearer]-settings[cls]['half']
        direction_x[nearer], direction_y[nearer] = dx_field[nearer], dy_field[nearer]
        fields[cls] = (dist, along, inside)
    junction = np.zeros(score.shape, bool)
    for s in segments:
        d, _, _ = geometry(s)
        crosses = np.abs(direction_x*s[3]+direction_y*s[4]) < look['parallel']
        junction |= crosses & (d <= settings[s[0]]['half']+look['mouth']+aa) & (score <= look['mouth']+aa)

    rgb = np.zeros((height,width,3), np.float32)  # premultiplied until the final conversion
    alpha = np.zeros((height,width), np.float32)
    pavement = np.zeros(score.shape, bool)
    def over(tint, coverage):
        nonlocal rgb, alpha
        coverage = np.clip(coverage, 0, 1)
        rgb = np.asarray(tint)*coverage[:,:,None]+rgb*(1-coverage[:,:,None])
        alpha = coverage+alpha*(1-coverage)
    def band(distance, half):
        return np.clip((half+aa-distance)/(2*aa), 0, 1)
    grain = 1+(hash21(np.floor(x*roads['grain']['perCell']), np.floor(y*roads['grain']['perCell']))-.5)*2*roads['grain']['amount']
    for cls in ('track','minor','major'):
        dist, along, inside = fields[cls]
        half = settings[cls]['half']
        shoulder, verge = settings[cls]['shoulder'], settings[cls]['verge']
        body = band(dist, half)
        pavement |= dist <= half
        over(color(roads['colours']['verge']), band(dist,half+shoulder+verge)*roads['vergeAlpha'][cls])
        over(color(roads['detail']['gravel']), band(dist,half+shoulder)*roads['detail']['shoulderAlpha'])
        gain = grain.copy()
        if cls == 'track':
            gain = gain*(1-band(np.abs(dist-look['track']['ruts']),look['track']['rutHalf'])*roads['ruts']['dark'])
        base = color(roads['colours']['asphalt' if cls == 'major' else 'road' if cls == 'minor' else 'dust'])
        over(base*gain[:,:,None], body)
        if cls == 'track':
            continue
        # No transverse end-cap lines and no lane/kerb/barrier line blocking a crossing's mouth.
        open_marks = inside & ~junction
        if cls == 'major':
            over(color(look['barrier']), band(dist,look['major']['barrier'])*open_marks)
            mark = np.maximum(band(np.abs(dist-look['major']['edge']),look['line']),
                              band(np.abs(dist-look['major']['centre']),look['line']))
            dash = (along/look['major']['dash']['period']) % 1 < look['major']['dash']['on']
            mark = np.maximum(mark,band(np.abs(dist-look['major']['lane']),look['dashHalf'])*dash)
        else:
            mark = band(np.abs(dist-(half-look['minor']['edgeInset'])),look['line'])*look['minor']['edgeStrength']
            dash = (along/look['minor']['dash']['period']) % 1 < look['minor']['dash']['on']
            mark = np.maximum(mark,band(dist,look['dashHalf'])*dash)
        over(color(roads['detail']['white']),mark*open_marks*roads['detail']['strength'])
    out = np.zeros((height,width,4), np.uint8)
    np.divide(rgb, alpha[:,:,None], out=rgb, where=alpha[:,:,None]>0)
    out[:,:,:3] = np.clip(np.round(rgb),0,255).astype(np.uint8)
    out[:,:,3] = np.round(alpha*255).astype(np.uint8)
    return out, pavement


def composite(raw, layer):
    """Put roads above garden/street tiles but below roof art; return source codes + true opacity."""
    overlay = layer[:,:,3].astype(np.float32)/255
    overlay = np.where(raw[:,:,3] >= 224, 0, overlay)
    base = (raw[:,:,3] > 0).astype(np.float32)
    alpha = overlay+base*(1-overlay)
    rgb = layer[:,:,:3]*overlay[:,:,None]+raw[:,:,:3]*base[:,:,None]*(1-overlay[:,:,None])
    np.divide(rgb,alpha[:,:,None],out=rgb,where=alpha[:,:,None]>0)
    out = raw.copy()
    out[:,:,:3] = np.clip(np.round(rgb),0,255).astype(np.uint8)
    out[:,:,3] = np.where(overlay>0,200,raw[:,:,3])
    return out, np.round(alpha*255).astype(np.uint8)


def canopy_on_road(tree, left, top, pavement):
    h, w = pavement.shape
    x0,y0,x1,y1 = max(0,left),max(0,top),min(w,left+tree.width),min(h,top+tree.height)
    if x0>=x1 or y0>=y1:
        return False
    alpha = np.asarray(tree.getchannel('A'))[y0-top:y1-top,x0-left:x1-left]
    return bool(np.any((alpha>0) & pavement[y0:y1,x0:x1]))
