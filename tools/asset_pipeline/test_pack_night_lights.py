"""Synthetic asset checks; no original data required. Run beside pack_night_lights.py."""
import unittest
import numpy as np
from pack_night_lights import windows,city_glow,road_lights,window_shapes,facade_masks,material_map

class NightFields(unittest.TestCase):
    def test_roof_material_and_missing_tiles(self):
        atlas=np.zeros((1,4,4),np.uint8);atlas[0,:,3]=[224,225,201,200]
        index=np.zeros((1,5,4),np.uint8);index[0,:4,0]=[1,2,3,4]
        result=windows({'size':1,'perRow':4,'atlasH':1,'atlasW':4},
            {'atlas':atlas.tobytes(),'index':index.tobytes()},5,1,{'fine':1,'roofFrom':224,'lamp':201})
        self.assertEqual(result.tolist(),[[False,False,True,False,False]])

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
        atlas=np.zeros((14,14,4),np.uint8)
        atlas[2:8,2:9,3]=227
        atlas[4:6,4:6,3]=228 # Former roof-light material remains dark too.
        atlas[0,12,3]=201
        index=np.zeros((1,4,4),np.uint8);index[0,:,0]=[1,0,0,1]
        return {'size':14,'perRow':1,'atlasH':14,'atlasW':14},{'atlas':atlas.tobytes(),'index':index.tobytes()}

    def test_windows_occupy_side_faces_and_roof_interior_is_never_lit(self):
        head,parts=self.city()
        look={'fine':3,'roofFrom':224,'lamp':201}
        codes=material_map(head,parts,4,1)
        core,face,roof=facade_masks(codes,look)
        self.assertTrue(core[9,7]);self.assertTrue(core[2,10]);self.assertTrue(core[0,12])
        self.assertEqual(core[roof].sum(),0);self.assertEqual(face[roof].sum(),0)
        data,sheet,coverage=window_shapes(head,parts,4,1,look)
        reconstructed=np.zeros(codes.shape,np.uint8)
        for point in data['points']:
            px,py,_,_,pattern=point[:5]
            x0=(pattern%data['perRow'])*data['slot'];y0=(pattern//data['perRow'])*data['slot']
            mask=sheet[y0:y0+data['slot'],x0:x0+data['slot'],3]
            for y,x in zip(*np.where(mask>=240)):
                reconstructed[py+y,px+x]=1
        np.testing.assert_array_equal(reconstructed,core)

    def test_window_atlas_shares_shapes_and_has_bright_core_with_soft_transparent_halo(self):
        head,parts=self.city()
        data,sheet,_=window_shapes(head,parts,4,1,{'fine':3,'roofFrom':224,'lamp':201})
        by_position={(p[0],p[1]):p for p in data['points']}
        for p in data['points']:
            if p[0]<14:self.assertEqual(p[4:6],by_position[(p[0]+42,p[1])][4:6])
        point=next(p for p in data['points'] if p[6] and p[5]>=0)
        x,y=(point[4]%data['perRow'])*12,(point[4]//data['perRow'])*12
        a=sheet[y:y+12,x:x+12,3]
        self.assertGreater(a.max(),245);self.assertTrue(((a>0)&(a<180)).any())

    def test_every_window_halo_is_clipped_off_adjacent_roofs(self):
        head,parts=self.city();look={'fine':3,'roofFrom':224,'lamp':201}
        codes=material_map(head,parts,4,1);roof=codes>=224
        data,sheet,_=window_shapes(head,parts,4,1,look)
        for p in data['points']:
            for index in (p[4],p[5]):
                if index<0:continue
                x0,y0=(index%data['perRow'])*12,(index//data['perRow'])*12
                for dy,dx in zip(*np.where(sheet[y0:y0+12,x0:x0+12,3]>0)):
                    x,y=p[0]+dx,p[1]+dy
                    if 0<=x<codes.shape[1] and 0<=y<codes.shape[0]:self.assertFalse(roof[y,x])

    def test_tile_seams_do_not_create_walls_through_one_continuous_building(self):
        atlas=np.zeros((14,14,4),np.uint8);atlas[2:8,:,3]=227
        index=np.zeros((1,2,4),np.uint8);index[:,:,0]=1
        codes=material_map({'size':14,'perRow':1,'atlasH':14,'atlasW':14},{'atlas':atlas.tobytes(),'index':index.tobytes()},2,1)
        _,face,_=facade_masks(codes,{'roofFrom':224,'lamp':201})
        self.assertEqual(face[2:8,13:16].sum(),0)

    def test_flat_roof_terraces_and_map_edges_do_not_create_wrapped_faces(self):
        codes=np.zeros((8,8),np.uint8);codes[2:5,2:5]=225;codes[-1,-1]=229
        core,face,_=facade_masks(codes,{'roofFrom':224,'lamp':201})
        self.assertEqual(face.sum(),0);self.assertEqual(core.sum(),0)

if __name__=='__main__':unittest.main()
