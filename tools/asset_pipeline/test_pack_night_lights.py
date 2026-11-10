"""Synthetic asset checks; no original data required. Run beside pack_night_lights.py."""
import unittest
import numpy as np
from pack_night_lights import windows,city_glow,road_lights,window_shapes

class NightFields(unittest.TestCase):
    def test_roof_material_and_missing_tiles(self):
        atlas=np.zeros((1,4,4),np.uint8);atlas[0,:,3]=[224,225,201,200]
        index=np.zeros((1,5,4),np.uint8);index[0,:4,0]=[1,2,3,4]
        result=windows({'size':1,'perRow':4,'atlasH':1,'atlasW':4},
            {'atlas':atlas.tobytes(),'index':index.tobytes()},5,1,{'fine':1,'roofFrom':224,'lamp':201})
        self.assertEqual(result.tolist(),[[True,False,True,False,False]])

    def test_glow_does_not_light_empty_land_or_dim_uniform_cities(self):
        look={'fine':3,'glowRadius':2,'glowGain':1.8}
        self.assertTrue(np.all(city_glow(np.zeros((8,8)),look)==0))
        self.assertTrue(np.all(city_glow(np.ones((8,8)),look)==1))

    def test_glow_has_finite_halo_around_city(self):
        urban=np.zeros((24,24));urban[10:14,10:14]=1
        out=city_glow(urban,{'fine':3,'glowRadius':2,'glowGain':1.8})
        self.assertGreater(out[36,36],out[24,24]);self.assertGreater(out[24:30,24:30].max(),0)
        self.assertEqual(out[:12,:12].max(),0)

    @staticmethod
    def look():
        return {'fine':4,'reach':1,'widths':{'major':{'half':.7}},
            'lamps':{'every':1.4,'halo':.7,'haloStrength':.3},'lampHalo':.65,
            'streetLamps':{'every':1.1,'halo':.55,'strength':.22}}

    def test_minor_pools_require_urban_ground_and_stay_near_road(self):
        m={'width':12,'height':8,'roads':[{'rank':1,'pts':[1,4,11,4]}]}
        _,rural=road_lights(m,np.zeros((8,12)),self.look())
        _,urban=road_lights(m,np.ones((8,12)),self.look())
        self.assertEqual(rural.max(),0);self.assertGreater(urban.max(),0)
        self.assertEqual(urban[:12,:].max(),0);self.assertEqual(urban[20:,:].max(),0)

    def test_highways_light_outside_towns_and_tracks_have_no_lamps(self):
        m={'width':12,'height':8,'roads':[{'rank':2,'pts':[1,4,11,4]}]}
        body,pool=road_lights(m,np.zeros((8,12)),self.look())
        self.assertGreater(body.max(),0);self.assertGreater(pool.max(),0)
        m['roads']=[{'rank':1,'track':True,'pts':[1,4,11,4]}]
        body,pool=road_lights(m,np.ones((8,12)),self.look())
        self.assertEqual(body.max(),0);self.assertEqual(pool.max(),0)

    @staticmethod
    def city():
        atlas=np.zeros((14,28,4),np.uint8)
        # Tiny windows deliberately away from the old coarse sample centres (2,7,11).
        atlas[1,1,3]=224;atlas[1,15,3]=224
        atlas[8,8,3]=225 # Ordinary dark roof must not become a light.
        index=np.zeros((1,3,4),np.uint8);index[0,:,0]=[1,2,0]
        return {'size':14,'perRow':2,'atlasH':14,'atlasW':28},{'atlas':atlas.tobytes(),'index':index.tobytes()}

    def test_real_window_pixels_survive_and_do_not_fill_the_fine_cell(self):
        head,parts=self.city()
        data,sheet,coverage=window_shapes(head,parts,3,1,{'fine':3,'roofFrom':224,'lamp':201})
        self.assertEqual(len(data['points']),2)
        self.assertGreater(coverage[0,0],0);self.assertLess(coverage[0,0],255)
        self.assertEqual(coverage[0,6:].max(),0)
        reconstructed=np.zeros((14,42),np.uint8)
        for px,py,_,_,pattern in data['points']:
            x0=(pattern%data['perRow'])*data['slot'];y0=(pattern//data['perRow'])*data['slot']
            mask=sheet[y0:y0+data['slot'],x0:x0+data['slot'],3]
            for y,x in zip(*np.where(mask>=240)):
                reconstructed[py+y,px+x]=1
        expected=np.zeros_like(reconstructed);expected[1,1]=1;expected[1,15]=1
        np.testing.assert_array_equal(reconstructed,expected)

    def test_window_atlas_shares_shapes_and_has_bright_core_with_soft_transparent_halo(self):
        head,parts=self.city()
        data,sheet,_=window_shapes(head,parts,3,1,{'fine':3,'roofFrom':224,'lamp':201})
        self.assertEqual(data['points'][0][4],data['points'][1][4])
        a=sheet[:12,:12,3]
        self.assertGreater(a[4,4],240)
        self.assertGreater(a[4,3],a[4,2]);self.assertGreater(a[4,2],0)
        self.assertEqual(a[0,0],0)

if __name__=='__main__':unittest.main()
