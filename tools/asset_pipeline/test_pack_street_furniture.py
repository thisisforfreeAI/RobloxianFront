"""Synthetic checks for pack_street_furniture.py; no original data needed. Run beside it:
python -m unittest test_pack_street_furniture
"""
import math
import os
import tempfile
import unittest

import numpy as np

from pack_street_furniture import LAMP, STREET, lamp_spots, world_rgba, write


def street(h=20, w=20):
    codes = np.zeros((h, w), np.uint8)
    codes[8:13, :] = STREET  # a street running east-west, rows 8..12
    return codes


class LampSpots(unittest.TestCase):
    def test_lamp_on_north_edge_faces_south_into_the_street(self):
        codes = street()
        codes[8, 10] = LAMP
        (tx, ty, a), = lamp_spots(codes)
        self.assertEqual((tx, ty), (10, 8))
        self.assertAlmostEqual(a, math.pi / 2, places=6)

    def test_lamp_on_south_edge_faces_north(self):
        codes = street()
        codes[12, 10] = LAMP
        (_, _, a), = lamp_spots(codes)
        self.assertAlmostEqual(a, -math.pi / 2, places=6)

    def test_vertical_street_lamps_face_across(self):
        codes = np.zeros((30, 20), np.uint8)
        codes[:, 7:12] = STREET
        codes[8, 11] = LAMP
        codes[18, 7] = LAMP
        spots = lamp_spots(codes)
        self.assertEqual([(s[0], s[1]) for s in spots], [(11, 8), (7, 18)])
        self.assertAlmostEqual(abs(spots[0][2]), math.pi, places=6)
        self.assertAlmostEqual(spots[1][2], 0, places=6)

    def test_colour_keeps_the_way_into_the_asphalt_not_the_paving(self):
        # asphalt rows 8..12, then a wide pale paved square (also street-coded) north of it
        codes = street()
        codes[0:8, :] = STREET
        codes[8, 10] = LAMP
        rgb = np.zeros((20, 20, 3), np.uint8)
        rgb[8:13, :] = (112, 119, 122)
        rgb[0:8, :] = (160, 160, 152)
        (_, _, by_code), = lamp_spots(codes)
        (_, _, by_colour), = lamp_spots(codes, rgb)
        self.assertLess(by_code, 0)  # the paving pulls it north without colours
        self.assertAlmostEqual(by_colour, math.pi / 2, places=6)

    def test_world_rgba_places_tiles_by_index(self):
        atlas = np.zeros((1, 4, 4), np.uint8)
        atlas[0, :, 3] = [200, 201, 150, 224]
        atlas[0, :, 0] = [1, 2, 3, 4]
        index = np.zeros((1, 3, 4), np.uint8)
        index[0, :, 0] = [2, 0, 4]
        out = world_rgba({"size": 1, "perRow": 4, "atlasH": 1, "atlasW": 4},
                         {"atlas": atlas.tobytes(), "index": index.tobytes()}, 3, 1)
        self.assertEqual(out[0, :, 3].tolist(), [201, 0, 224])
        self.assertEqual(out[0, :, 0].tolist(), [2, 0, 4])

    def test_lone_lamp_falls_back_to_north(self):
        codes = np.zeros((9, 9), np.uint8)
        codes[4, 4] = LAMP
        (_, _, a), = lamp_spots(codes)
        self.assertAlmostEqual(a, -math.pi / 2)

    def test_no_lamps_no_spots(self):
        self.assertEqual(lamp_spots(street()), [])

    def test_written_module_lists_cells(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "out.luau")
            write(path, "x", 14, [(13, 27, 1.5)])
            text = open(path).read()
        self.assertIn('id = "x", cellPx = 14', text)
        self.assertIn("0.9643, 1.9643, 1.500,", text)


if __name__ == "__main__":
    unittest.main()
