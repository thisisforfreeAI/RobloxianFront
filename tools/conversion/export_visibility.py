"""Export local-only settlement sight blockers from the original designed .city file."""
import base64,json,pathlib,struct,sys,zlib
city=pathlib.Path(sys.argv[1]);root=pathlib.Path(sys.argv[2]) if len(sys.argv)>2 else pathlib.Path(__file__).resolve().parents[2]
b=city.read_bytes();assert b[:4]==b'WFCT'
n=struct.unpack_from('<I',b,4)[0];head=json.loads(b[8:8+n]);at=8+n;parts={}
for p in head['parts']:
    parts[p['name']]=zlib.decompress(b[at:at+p['packed']],-15);at+=p['packed']
w,h=map(int,head['key'].split(':')[1].split('x'))
mask=parts['townCells'];assert len(mask)==w*h and set(mask)<={0,1}
c=zlib.compressobj(9,zlib.DEFLATED,-15);data=base64.b64encode(c.compress(mask)+c.flush()).decode()
out=root/'src/shared/GameData'/('Visibility_'+head['id']+'.luau');out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(f'--!strict\n-- GENERATED local-only original town building footprints.\nreturn {{width={w},height={h},deflate="{data}"}}\n')
print('Exported',sum(mask),'building sight-blocker cells')
