import base64
import json
import os
from pathlib import Path
import re
import struct
import tempfile
import unittest
import zlib

from PIL import Image
from dynamic_forest import export_forest


class DynamicForestTests(unittest.TestCase):
    def fixture(self, root):
        root = Path(root)
        atlas = Image.new("RGBA", (8, 2))
        for x in range(8):
            for y in range(2):
                atlas.putpixel((x, y), (x*20, 30, 40, 255))
        atlas.save(root / "tree-damage.png")
        frames = {kind: {"synthetic": [i*2, 0, 2, 2]} for i, kind in
                  enumerate(("standing", "fallen", "stump", "burnt"))}
        data = {"scale": .1, "keyStride": 1024, "shadow": {"dx": .1, "dy": .2, "alpha": .3},
                "frames": frames, "tiles": {"synthetic": {"w": 2, "h": 2}},
                "fallenAnchor": .2, "charColors": [0x888888], "refs": []}
        damage = root / "tree-damage.json"
        damage.write_text(json.dumps(data))
        td = {"count": 2, "x": [.4, .75], "y": [.6, .6], "tile": ["synthetic"]*2,
              "scale": [1, 1], "tiles": {"synthetic": [0, 0, 2, 2]}}

        class Trees:
            def sprite(self, tile, scale):
                return Image.new("RGBA", (2, 2), (10, 50, 20, 255)), None

        return td, Trees(), damage

    def test_retained_trees_keep_source_keys_and_geometry_and_output_is_deterministic(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("ROBLOXIANFRONT_TEST_TMP")) as root:
            td, trees, damage = self.fixture(root)
            output = Path(root) / "data"
            export_forest("test", 4, 4, 10, td, [1], trees, damage, output)
            text = (output / "Forest_test.luau").read_text()
            raw = zlib.decompress(base64.b64decode(re.search(r'\["trees"\]="([^"]+)"', text)[1]), -15)
            key, x, y, size, cell, sprite, dx, dy = struct.unpack("<ddddIH2xii", raw)
            self.assertEqual(key, 6*1024+8)
            self.assertAlmostEqual(x, .8)
            self.assertAlmostEqual(y, .6)
            self.assertAlmostEqual(size, .2)
            self.assertEqual((cell, sprite, dx, dy), (0, 1, 6, 5))
            before = {p.name: p.read_bytes() for p in output.iterdir()}
            export_forest("test", 4, 4, 10, td, [1], trees, damage, output)
            self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})

    def test_source_standing_pixels_and_generated_damage_frames_share_one_cpu_page(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("ROBLOXIANFRONT_TEST_TMP")) as root:
            td, trees, damage = self.fixture(root)
            output = Path(root) / "data"
            export_forest("test", 4, 4, 10, td, [0, 1], trees, damage, output)
            text = (output / "Forest_test_Pixels1.luau").read_text()
            raw = zlib.decompress(base64.b64decode(re.search(r'\["deflate"\]="([^"]+)"', text)[1]), -15)
            self.assertEqual(len(raw), 64)
            self.assertEqual(raw[:16], bytes((10, 50, 20, 255))*4)
            self.assertNotEqual(raw[16:32], raw[32:48])
            self.assertNotEqual(raw[32:48], raw[48:64])

    def test_duplicate_source_keys_and_out_of_map_trees_fail_before_writing_runtime_data(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("ROBLOXIANFRONT_TEST_TMP")) as root:
            td, trees, damage = self.fixture(root)
            output = Path(root) / "data"
            td["x"][1] = td["x"][0]
            with self.assertRaisesRegex(ValueError, "duplicate"):
                export_forest("test", 4, 4, 10, td, [0, 1], trees, damage, output)
            self.assertFalse(output.exists())
            td["x"][1] = 5
            with self.assertRaisesRegex(ValueError, "outside"):
                export_forest("test", 4, 4, 10, td, [1], trees, damage, output)


if __name__ == "__main__":
    unittest.main()
