"""Synthetic package/ID/upload regressions. No source artwork, network or credentials required."""
import base64,hashlib,json,sys,tempfile,unittest
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/asset_pipeline'))
import private_images as pixels
import pack_men_fx_lods as masks
import static_image_package as package
import static_image_upload as uploader

class Images(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.source=self.root/'DevAssets';self.source.mkdir();self.output=self.root/'upload'
    def tearDown(self):self.tmp.cleanup()
    def source_image(self,name='OrigTank',color=(80,120,200,255)):
        image=np.zeros((8,8,4),dtype=np.uint8);image[1:7,2:6]=color
        meta={'width':8,'height':8,'frame':4,'columns':2,'strips':{'hull_colour':0},'rle':pixels.encode(image)}
        (self.source/(name+'.luau')).write_text('-- generated\nreturn '+pixels.lua(meta),encoding='utf-8');return meta,image
    def ids(self,values):
        path=self.output/'image_ids.json';path.write_text(json.dumps(values),encoding='utf-8');return path
    def test_literal_reader_rejects_executable_source(self):
        for text in ['return require("file")','return {width=1}; print("bad")','return {x=function() end}']:
            with self.assertRaises(ValueError):pixels.parse(text)
        self.assertEqual(pixels.parse('return {x={1,2},ok=true,name="hello"}'),{'x':[1,2],'ok':True,'name':'hello'})
    def test_decoder_rejects_invalid_run_length(self):
        with self.assertRaises(ValueError):pixels.decode({'width':2,'height':2,'rle':base64.b64encode(b'\x01\x00\x00\x00\x00\x00').decode()})
    def test_cropped_derivatives_keep_odd_crops_empty_frames_and_transparent_gutters(self):
        image=np.zeros((20,512,4),dtype=np.uint8);image[2:7,3:6]=(255,0,0,255)
        meta={'width':512,'height':20,'rle':pixels.encode(image),'poses':{'stand':{'rim':[[3,2,3,5,6,9,48],[0,0,0,0,0,0,48]]}}}
        before=json.dumps(meta,sort_keys=True)
        for stride in [2,4]:
            result=masks.derivative(meta,stride);actual=pixels.decode(result);rect=result['rects']['stand:rim:1'];x,y,w,h=rect
            self.assertEqual((w,h),((3+stride-1)//stride,(5+stride-1)//stride));self.assertTrue(np.all(actual[y:y+h,x:x+w]==(255,0,0,255)))
            self.assertEqual(int(actual[y-1,x,3]),0);self.assertEqual(result['rects']['stand:rim:2'],[0,0,0,0]);self.assertEqual(result['sourceHash'],pixels.signature(meta))
        self.assertEqual(json.dumps(meta,sort_keys=True),before)
    def test_png_export_roundtrips_and_deduplicates_identical_art(self):
        meta,image=self.source_image();self.source_image('OrigTruck');manifest=package.export(self.source,self.output)
        self.assertEqual(len(manifest['entries']),2);self.assertEqual(len(list(self.output.glob('*.png'))),1)
        entry=manifest['entries'][0];self.assertEqual(Image.open(self.output/entry['file']).convert('RGBA').tobytes(),image.tobytes());self.assertEqual(entry['sourceHash'],pixels.signature(meta))
    def test_import_preserves_large_image_ids_as_strings(self):
        self.source_image();package.export(self.source,self.output);ids=self.ids({'OrigTank':'1234567890123456789'});target=self.root/'GameData/StaticImageIds.luau'
        result=package.import_ids(self.output,ids,target);self.assertEqual(result['OrigTank']['id'],'1234567890123456789');self.assertEqual(pixels.load(target),result)
    def test_changed_png_cannot_be_imported(self):
        self.source_image();m=package.export(self.source,self.output);ids=self.ids({'OrigTank':'123'});(self.output/m['entries'][0]['file']).write_bytes(b'changed')
        with self.assertRaises(ValueError):package.import_ids(self.output,ids,self.root/'ids.luau')
    def test_id_reuse_requires_identical_pixels_on_reexport(self):
        self.source_image();package.export(self.source,self.output);self.ids({'OrigTank':'123'});package.export(self.source,self.output)
        self.assertEqual(json.loads((self.output/'image_ids.json').read_text())['OrigTank'],'123')
        self.source_image(color=(255,0,0,255));package.export(self.source,self.output);self.assertEqual(json.loads((self.output/'image_ids.json').read_text())['OrigTank'],'')
    def test_invalid_or_empty_ids_do_not_write_runtime_module(self):
        self.source_image();package.export(self.source,self.output)
        for value in ['','0','rbxassetid://123','1.25','-1']:
            with self.assertRaises(ValueError):package.import_ids(self.output,self.ids({'OrigTank':value}),self.root/'ids.luau')
        self.assertFalse((self.root/'ids.luau').exists())
    def test_one_id_cannot_map_to_different_pngs(self):
        self.source_image();self.source_image('OrigTruck',(255,0,0,255));package.export(self.source,self.output)
        with self.assertRaises(ValueError):package.import_ids(self.output,self.ids({'OrigTank':'123','OrigTruck':'123'}),self.root/'ids.luau')
    def test_import_rejects_paths_outside_the_package(self):
        self.source_image();m=package.export(self.source,self.output);m['entries'][0]['file']='../outside.png';(self.output/'manifest.json').write_text(json.dumps(m))
        with self.assertRaises(ValueError):package.import_ids(self.output,self.ids({'OrigTank':'123'}),self.root/'ids.luau')
    def test_original_install_output_guard(self):
        install=self.root/'install';(install/'resources').mkdir(parents=True);(install/'resources/app.asar').write_bytes(b'fixture')
        with self.assertRaises(ValueError):package.safe_output(install/'assets/output')
    def test_upload_posts_an_image_and_saves_operation_before_polling(self):
        png=self.root/'atlas.png';Image.new('RGBA',(4,4)).save(png);calls=[];saved=[]
        def send(url,key,data=None,content_type=None):
            calls.append((url,key,data,content_type))
            if data:
                self.assertIn(b'"assetType": "Image"',data);self.assertNotIn(b'fake-secret',data);return {'path':'operations/test-1'}
            self.assertEqual(saved,['operations/test-1']);return {'done':True,'response':{'assetId':'123','assetType':'ASSET_TYPE_IMAGE'}}
        self.assertEqual(uploader.upload(png,{'userId':'1'},'fake-secret',send=send,sleep=lambda _:None,on_operation=saved.append),'123');self.assertEqual(len(calls),2)
    def test_upload_resume_does_not_create_a_duplicate_asset(self):
        png=self.root/'atlas.png';Image.new('RGBA',(4,4)).save(png)
        def send(url,key,data=None,content_type=None):
            self.assertIsNone(data);self.assertTrue(url.endswith('operations/existing'));return {'done':True,'response':{'assetId':'456','assetType':'ASSET_TYPE_IMAGE'}}
        self.assertEqual(uploader.upload(png,{'groupId':'1'},'fake',send=send,operation='operations/existing'),'456')
    def test_bad_operation_and_decal_ids_are_not_imported(self):
        png=self.root/'atlas.png';Image.new('RGBA',(4,4)).save(png)
        with self.assertRaises(ValueError):uploader.upload(png,{'userId':'1'},'fake',send=lambda *args:{'path':'https://untrusted.example/'})
        with self.assertRaises(ValueError):uploader.upload(png,{'userId':'1'},'fake',operation='operations/test',send=lambda *args:{'done':True,'response':{'assetId':'123','assetType':'ASSET_TYPE_DECAL'}})
    def test_processing_timeout_retains_the_resumable_operation(self):
        png=self.root/'atlas.png';Image.new('RGBA',(4,4)).save(png);saved=[]
        def send(url,key,data=None,content_type=None):return {'path':'operations/pending'}if data else {'done':False}
        with self.assertRaises(TimeoutError):uploader.upload(png,{'userId':'1'},'fake',send=send,sleep=lambda _:None,on_operation=saved.append)
        self.assertEqual(saved,['operations/pending'])
if __name__=='__main__':unittest.main()
