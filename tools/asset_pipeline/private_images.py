"""Read generated literal-only Luau image modules without executing source code."""
import base64,json,re,struct,zlib
from pathlib import Path
import numpy as np

TOKEN=re.compile(r'\s+|--[^\n]*|"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[A-Za-z_]\w*|[{}\[\]=,;]')
def parse(text):
    tokens=[];at=0
    while at<len(text):
        m=TOKEN.match(text,at)
        if not m: raise ValueError(f'nonliteral Luau at byte {at}')
        token=m[0];at=m.end()
        if not token.isspace() and not token.startswith('--'): tokens.append(token)
    i=0
    def take(expected=None):
        nonlocal i
        if i>=len(tokens): raise ValueError('truncated literal')
        value=tokens[i];i+=1
        if expected is not None and value!=expected: raise ValueError('expected '+expected)
        return value
    def value():
        nonlocal i
        token=take()
        if token=='{':
            result={};index=1;array=True
            while tokens[i]!='}':
                if tokens[i]=='[':
                    take('[');key=value();take(']');take('=');array=False
                elif i+1<len(tokens) and tokens[i+1]=='=':
                    key=take();take('=');array=False
                else: key=index;index+=1
                if key in result: raise ValueError('duplicate literal key')
                result[key]=value()
                if tokens[i] in (',',';'):take()
                elif tokens[i]!='}':raise ValueError('missing field separator')
            take('}')
            return list(result.values()) if array and result else result
        if token.startswith('"'): return json.loads(token)
        if token in ('true','false','nil'): return {'true':True,'false':False,'nil':None}[token]
        if re.fullmatch(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?',token): return float(token) if any(c in token for c in '.eE') else int(token)
        raise ValueError('not a literal: '+token)
    if tokens and tokens[0]=='return':take()
    result=value()
    if i!=len(tokens):raise ValueError('trailing source code')
    return result

def load(path): return parse(Path(path).read_text(encoding='utf-8-sig'))
def lua(v):
    if v is None:return 'nil'
    if isinstance(v,bool):return 'true' if v else 'false'
    if isinstance(v,(str,int,float)):return json.dumps(v,separators=(',',':'))
    if isinstance(v,list):return '{'+','.join(lua(x)for x in v)+'}'
    return '{'+','.join('['+json.dumps(str(k))+']='+lua(x)for k,x in v.items())+'}'
def signature(meta): return zlib.adler32((meta.get('rle')or meta.get('deflate')or '').encode('ascii'))
def decode(meta):
    w,h=meta['width'],meta['height']
    if not isinstance(w,int)or not isinstance(h,int)or not(0<w<=1024 and 0<h<=1024):raise ValueError('invalid image dimensions')
    if 'deflate'in meta:
        raw=zlib.decompress(base64.b64decode(meta['deflate'],validate=True),-15)
        if len(raw)!=w*h*4:raise ValueError('inflated image length mismatch')
        return np.frombuffer(raw,dtype=np.uint8).reshape(h,w,4).copy()
    packed=base64.b64decode(meta['rle'],validate=True)
    if len(packed)%6:raise ValueError('truncated RGBA runs')
    runs=np.frombuffer(packed,dtype=np.dtype([('count','<u2'),('rgba','u1',(4,))]))
    if np.any(runs['count']==0)or int(runs['count'].astype(np.uint64).sum())!=w*h:raise ValueError('RGBA run size mismatch')
    return np.repeat(runs['rgba'],runs['count'].astype(np.int64),axis=0).reshape(h,w,4)
def encode(pixels):
    flat=np.ascontiguousarray(pixels).reshape(-1,4).copy();flat[flat[:,3]==0]=0
    words=flat.view('<u4').reshape(-1);edges=np.r_[0,np.flatnonzero(words[1:]!=words[:-1])+1,len(words)];data=bytearray()
    for start,end in zip(edges[:-1],edges[1:]):
        count=int(end-start)
        while count:n=min(65535,count);data+=struct.pack('<HI',n,int(words[start]));count-=n
    return base64.b64encode(data).decode('ascii')
