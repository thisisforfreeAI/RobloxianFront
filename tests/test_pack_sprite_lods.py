import importlib.util, os, sys, tempfile, unittest, zlib
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[1]
temp_root=Path(os.environ.get('SPRITE_LOD_TEST_TMP',tempfile.gettempdir())).resolve();temp_root.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('sprite_lods',root/'tools/asset_pipeline/pack_sprite_lods.py');lod=importlib.util.module_from_spec(spec);spec.loader.exec_module(lod)
class SpriteLodTests(unittest.TestCase):
 def test_alpha_weighting_prevents_black_fringe(self):
  p=np.zeros((2,2,4),dtype=np.uint8);p[0,0]=[240,120,60,255];small=lod.half(p);self.assertEqual(small[0,0].tolist(),[240,120,60,64])
 def test_integer_reduction_matches_rgba_reference(self):
  rng=np.random.default_rng(71);p=rng.integers(0,256,(16,24,4),dtype=np.uint8);actual=lod.half(p)
  for y in range(8):
   for x in range(12):
    block=p[y*2:y*2+2,x*2:x*2+2].astype(np.uint32);a=int(block[:,:,3].sum());expected=[int(np.floor((block[:,:,c]*block[:,:,3]).sum()/a+.5)) if a else 0 for c in range(3)]+[int(np.floor(a/4+.5))];self.assertEqual(actual[y,x].tolist(),expected)
 def test_runs_roundtrip_and_split_uint16_limit(self):
  p=np.full((256,512,4),[70,100,130,255],dtype=np.uint8);text=lod.encode(p);meta={'rle':text,'width':512,'height':256};np.testing.assert_array_equal(lod.decode(meta),p)
 def test_aligned_facing_cells_never_bleed_into_neighbours(self):
  p=np.zeros((8,16,4),dtype=np.uint8);p[:,:8]=[255,0,0,255];p[:,8:]=[0,0,255,255];small=lod.half(lod.half(p));self.assertTrue(np.all(small[:,:2]==[255,0,0,255]));self.assertTrue(np.all(small[:,2:]==[0,0,255,255]))
 def test_generated_modules_preserve_source_and_logical_grid(self):
  with tempfile.TemporaryDirectory(dir=temp_root) as tmp:
   assert Path(tmp).resolve().is_relative_to(temp_root)
   root=Path(tmp);pixels=np.full((8,8,4),[20,40,60,255],dtype=np.uint8);raw=lod.encode(pixels);text=f'return {{frame=4, columns=2, width=8,height=8,strips={{["body_colour"]=0,["body_paint"]=4}},rle="{raw}"}}';source=root/'OrigTank.luau';source.write_text(text);generated=lod.generate(source,root/'out');self.assertEqual(len(generated),2);self.assertEqual(source.read_text(),text)
   for stride,file in zip((2,4),generated):
    meta=lod.parse(file.read_text());self.assertEqual(meta['frame'],4//stride);self.assertEqual(meta['strips']['body_paint'],4//stride);self.assertIn(f'sourceHash = {zlib.adler32(raw.encode())}',file.read_text());self.assertEqual(lod.decode(meta).shape,(8//stride,8//stride,4))
 def test_non_sprite_and_derivative_modules_are_not_regenerated(self):
  with tempfile.TemporaryDirectory(dir=temp_root) as tmp:
   assert Path(tmp).resolve().is_relative_to(temp_root)
   root=Path(tmp)
   for name in ('OrigStructures.luau','OrigMenRifleFx.luau','OrigTank_Mip2.luau'):
    source=root/name;source.write_text('return {}');self.assertEqual(lod.generate(source,root/'out'),[])
 def test_corrupt_runs_refuse_without_output(self):
  with self.assertRaises(ValueError):lod.decode({'rle':'AQABAgME','width':2,'height':2})
if __name__=='__main__':unittest.main()
