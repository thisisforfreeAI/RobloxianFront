import struct
import unittest
import numpy as np
from pack_city import shade, xor_patch


class CityLightingTests(unittest.TestCase):
    def test_sparse_patch_reconstructs_and_reverses_rgba(self):
        base=np.zeros((4,8,4),np.uint8)
        lit=base.copy();lit[1,2:5]=[7,40,80,127];lit[3,7]=[255,254,253,252]
        patch=xor_patch(base,lit)
        result=base.view('<u4').reshape(-1).copy()
        for expected in (lit,base):
            at=0
            while at<len(patch):
                offset,count=struct.unpack_from('<II',patch,at);at+=8
                result[offset:offset+count]^=np.frombuffer(patch[at:at+count*4],'<u4');at+=count*4
            self.assertTrue(np.array_equal(result.view(np.uint8).reshape(base.shape),expected))
        self.assertEqual(xor_patch(base,base),b'')

    def test_roof_shadow_crosses_sides_and_noon_stays_south(self):
        img=np.zeros((50,70,4),np.uint8);aux=np.zeros_like(img)
        img[16:24,31:39]=[100,120,140,224];aux[16:24,31:39,0]=24
        tile=np.ones(img.shape[:2],bool)
        centers=[]
        for phase in (0.04,0.31,0.58):
            lit=shade(img,aux,tile,phase)
            weights=lit[:,:,3].astype(float);weights[16:24,31:39]=0
            yy,xx=np.indices(weights.shape)
            centers.append(((xx*weights).sum()/weights.sum(),(yy*weights).sum()/weights.sum()))
        self.assertLess(centers[0][0],34.5)
        self.assertGreater(centers[2][0],34.5)
        self.assertAlmostEqual(centers[1][0],34.5)
        self.assertGreater(centers[1][1],23)


if __name__=='__main__':unittest.main()
