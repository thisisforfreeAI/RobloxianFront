import json,pathlib,unittest
import numpy as np
from PIL import Image
from road_layer import road_layer,composite,canopy_on_road,points
from pack_city import road_cells,shade

CONFIG=pathlib.Path(__file__).resolve().parents[2]/'docs/private/road-look.json'

class RoadLayerTests(unittest.TestCase):
    def test_typed_worker_points_clear_the_same_cells_as_plain_points(self):
        a={'width':10,'height':10,'roads':[{'rank':1,'pts':[0,5,9,5]}]}
        b={'width':10,'height':10,'roads':[{'rank':1,'pts':{'data':[0,5,9,5]}}]}
        self.assertTrue(np.array_equal(road_cells(a),road_cells(b)))
        self.assertTrue(road_cells(b)[5].all())

    def test_canopy_clearance_checks_real_alpha_and_includes_map_edges(self):
        tree=Image.new('RGBA',(5,5));tree.putpixel((2,2),(0,100,0,255))
        pavement=np.zeros((10,10),bool);pavement[4,4]=True
        self.assertTrue(canopy_on_road(tree,2,2,pavement))
        self.assertFalse(canopy_on_road(tree,4,4,pavement))
        self.assertFalse(canopy_on_road(tree,-10,-10,pavement))

    def test_roads_cover_yards_but_preserve_roofs_and_fractional_alpha(self):
        raw=np.zeros((3,3,4),np.uint8);raw[0,0]=[10,20,30,224];raw[1,1]=[0,90,0,150]
        road=np.full_like(raw,[100,100,100,255]);road[2,2,3]=128
        out,opacity=composite(raw,road)
        self.assertTrue(np.array_equal(out[0,0],raw[0,0]))
        self.assertEqual(out[1,1,0],100);self.assertEqual(opacity[2,2],128)
        lit=shade(out,np.zeros_like(out),np.zeros((3,3),bool),.31,opacity)
        self.assertEqual(lit[2,2,3],128)

    @unittest.skipUnless(CONFIG.exists(),'generate local road look JSON')
    def test_join_has_no_gap_and_chunk_edges_match(self):
        config=json.loads(CONFIG.read_text())
        m={'roads':[{'rank':1,'pts':[0,5,10,5]},{'rank':1,'pts':[5,5,5,10]}]}
        whole,mask=road_layer(m,config,0,0,140,140,14)
        left,_=road_layer(m,config,0,0,70,140,14);right,_=road_layer(m,config,5,0,70,140,14)
        self.assertTrue(np.array_equal(whole,np.concatenate((left,right),axis=1)))
        self.assertTrue(mask[70,:].all());self.assertTrue(mask[70:,70].all())

if __name__=='__main__':unittest.main()
