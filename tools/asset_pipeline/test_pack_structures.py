"""Synthetic regression coverage: ground must never enter a building's caster mask."""
import unittest,base64,zlib
from PIL import Image
from pack_structures import caster_mask,effect_source,factory_layout,weapon_parts,pack,KINDS

class CasterTests(unittest.TestCase):
    def test_dirt_and_paint_are_not_casters(self):
        sheet=Image.new('RGBA',(40,8),(0,0,0,0))
        sheet.paste((120,90,50,255),(0,0,8,8));sheet.paste((255,255,255,255),(8,0,16,8))
        mask=caster_mask(sheet,{'x':0,'y':0,'frame':8},[1,2,3])
        self.assertIsNone(mask.getbbox())

    def test_raised_roofs_and_thin_fences_survive_without_filling_ground(self):
        sheet=Image.new('RGBA',(40,8),(0,0,0,0));sheet.paste((120,90,50,255),(0,0,8,8))
        sheet.paste((255,255,255,255),(18,2,22,6))
        sheet.paste((255,255,255,255),(24,0,25,8))
        mask=caster_mask(sheet,{'x':0,'y':0,'frame':8},[1,2,3]);alpha=mask.getchannel('A')
        self.assertEqual(mask.size,(4,4));self.assertEqual(alpha.getpixel((3,3)),0)
        self.assertEqual(alpha.getpixel((1,1)),255);self.assertGreater(alpha.getpixel((0,3)),0)
        self.assertLess(alpha.getpixel((0,3)),255)

    def test_metadata_offset_and_union_do_not_stack_opacity(self):
        sheet=Image.new('RGBA',(44,12),(0,0,0,0))
        for x in (20,28):sheet.paste((255,255,255,128),(x,4,x+2,6))
        mask=caster_mask(sheet,{'x':4,'y':4,'frame':8},[1,2,3])
        self.assertEqual(mask.getchannel('A').getpixel((0,0)),128)
        self.assertEqual(mask.getchannel('A').getpixel((3,3)),0)

    def test_height_pixels_match_canvas_premultiplication_and_ignore_transparent_normal_pixels(self):
        sheet=Image.new('RGBA',(16,4),(22,33,44,255));normal=Image.new('RGBA',(8,2),(0,0,0,0))
        normal.putpixel((0,0),(0,0,6,64));normal.putpixel((1,0),(0,0,255,63))
        normal.putpixel((0,1),(0,0,3,255));normal.putpixel((1,1),(0,0,9,255))
        result=effect_source(sheet,normal,{'x':0,'y':0,'frame':4},{'scale':.5,'wallReach':1})
        raw=zlib.decompress(base64.b64decode(result['deflate']),-15)
        self.assertEqual(result['n'],2);self.assertEqual(result['top'],9);self.assertEqual(len(raw),172)
        self.assertEqual(raw[128:132],bytes((8,0,3,9)))
        self.assertEqual(raw[132:136],bytes(4));self.assertEqual(raw[136:140],bytes((1,0,1,1)))
        self.assertEqual(raw[:64],sheet.crop((0,0,4,4)).tobytes())
        self.assertEqual(raw[64:128],sheet.crop((4,0,8,4)).tobytes())

    def test_factory_source_layout_uses_faction_positions_without_mutating_shared_settings(self):
        config={'crane':{'sec':6},'weld':{'count':2}}
        positions={'door':{'x':.5,'y':.75,'w':.4},'crane':{'x':.8,'y':.5,'run':.2},'weld':{'x':.2,'y':.6,'w':.3,'h':.1}}
        layout=factory_layout(config,positions,3,144,True,12)
        self.assertTrue(layout['craneOff']);self.assertAlmostEqual(layout['doors'][0][0],-.3)
        self.assertAlmostEqual(layout['doors'][1][0],.3);self.assertAlmostEqual(layout['doors'][0][2],.6)
        self.assertAlmostEqual(layout['crane']['run'],.6);self.assertEqual(layout['fps'],12)
        self.assertEqual(config,{'crane':{'sec':6},'weld':{'count':2}})

    def test_shared_weapon_frames_keep_pose_crop_offsets_and_transparent_guards(self):
        sheet=Image.new('RGBA',(16,16),(0,0,0,0))
        sheet.putpixel((1,2),(100,120,140,255));sheet.putpixel((9,3),(90,110,130,255))
        part={'x':0,'y':0,'frame':8,'cells':2,'headings':2,'tall':4}
        data={'gun':{'atgun':{'part':'cannon'},'bunker':{'part':'machine'}},'atlas':{'parts':{'cannon':part,'machine':part}}}
        result=weapon_parts(data,sheet);raw=zlib.decompress(base64.b64decode(result['deflate']),-15)
        for part in result['parts'].values():
            self.assertEqual(len(part['frames']),2)
            for frame,offset in zip(part['frames'],((1,2),(1,3))):
                rect=result['rects'][frame['base']];self.assertEqual(tuple(rect[4:]),offset)
                self.assertEqual(raw[((rect[1]-1)*result['width']+rect[0])*4+3],0)
                self.assertEqual(raw[(rect[1]*result['width']+rect[0])*4+3],255)

    def test_separate_launcher_pages_keep_faction_frame_counts_and_stage_heights(self):
        sheet=Image.new('RGBA',(16,32),(0,0,0,0))
        parts={}
        for i,name in enumerate(('up','half','down')):
            parts[name]={'x':0,'y':i*8,'frame':4,'cells':2,'headings':1,'tall':(3-i)*8}
            sheet.putpixel((i, i*8+1),(20,40,60,255))
        data={'atlas':{'parts':parts}}
        result=weapon_parts(data,sheet,['up','half','down'])
        self.assertEqual(set(result['parts']),set(parts))
        for name,part in result['parts'].items():
            self.assertEqual(len(part['frames']),1);self.assertEqual(part['tall'],parts[name]['tall'])
            self.assertIn(part['frames'][0]['base'],result['rects'])

    def test_packed_runtime_pages_retain_every_building_look_for_the_live_renderer(self):
        sheet=Image.new('RGBA',(24,8),(0,0,0,0));sheet.paste((60,80,70,255),(0,0,4,4))
        body={'x':0,'y':0,'frame':4,'cells':1};part={'x':0,'y':0,'frame':4,'cells':1,'headings':1}
        positions={kind:{} for kind in KINDS};positions['factory']={'door':{'x':.5,'y':.5,'w':.5},'crane':{'x':.5,'y':.5}}
        data={'atlas':{'buildings':{kind:body for kind in KINDS},'parts':{'factory-door':part,'factory-crane':part,'arty':part},'bands':[1,2,3]},
              'positions':{'coalition':positions,'republic':positions},'gun':{},'dish':{},'nightAlpha':1,
              'artillery':{'parts':{'gun':['arty'],'pod':['arty']},'gun':[0,0],'pod':[0,0],'rest':0}}
        result=pack(data,sheet)
        for page in result['armies'].values():
            self.assertEqual(set(page['looks']),set(KINDS))
            for look in page['looks'].values():self.assertIn(look['base'],page['rects'])

if __name__=='__main__':unittest.main()
