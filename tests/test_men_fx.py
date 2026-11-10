"""Synthetic pixel tests for the cropped soldier-mask packer. No original art is needed."""
import base64
import importlib.util
from pathlib import Path
import struct
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pack_men_fx", ROOT / "tools/asset_pipeline/pack_men_fx.py")
packer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packer)


class Masks(unittest.TestCase):
    def test_rim_expands_and_keeps_tint(self):
        cell = Image.new("RGBA", (48, 48))
        cell.putpixel((24, 24), (255, 255, 255, 255))
        out = packer.rim(cell, 1.5, (6, 8, 11))
        self.assertEqual(out.getpixel((24, 24)), (6, 8, 11, 255))
        x0, y0, x1, y1 = out.getbbox()
        self.assertLess(x0, 24)
        self.assertLess(y0, 24)
        self.assertGreater(x1, 25)
        self.assertGreater(y1, 25)

    def test_cropped_shapes_reconstruct_all_facings_including_transparent_and_edge_pixels(self):
        root = Path("synthetic-input")
        strip = Image.new("RGBA", (48 * 16, 48))
        for facing in range(15):
            # Deliberately vary the pivot and include pixels at opposite cell edges.
            strip.putpixel((facing * 48 + facing, 10 + facing), (10, 20, 30, 255))
            strip.putpixel((facing * 48 + 47, 47), (30, 20, 10, 90))
        cfg = {"frame": 48, "facings": 16, "rim": {"px": 1.5, "halfPx": 3, "colour": "#06080b"}}
        with patch.object(packer.Image, "open", side_effect=lambda _: strip.copy()):
            meta = packer.pack("Synthetic", {"strips": [["stand_colour", "stand_colour.png"]]}, cfg, root)
        encoded = base64.b64decode(meta["rle"])
        raw = bytearray()
        for offset in range(0, len(encoded), 6):
            count = struct.unpack_from("<H", encoded, offset)[0]
            raw.extend(encoded[offset+2:offset+6] * count)
        page = Image.frombytes("RGBA", (meta["width"], meta["height"]), bytes(raw))
        self.assertLessEqual(meta["height"], 1024)
        for facing in range(16):
            original = strip.crop((facing * 48, 0, (facing + 1) * 48, 48))
            for key in ("shade", "shadeHalf"):
                x, y, w, h, ox, oy, frame = meta["poses"]["stand"][key][facing]
                restored = Image.new("RGBA", (frame, frame))
                if w and h:
                    restored.paste(page.crop((x, y, x+w, y+h)), (ox, oy))
                expected = original if key == "shade" else original.resize((24, 24), Image.Resampling.BOX)
                self.assertEqual(restored.tobytes(), expected.tobytes(), (key, facing))


if __name__ == "__main__":
    unittest.main()
