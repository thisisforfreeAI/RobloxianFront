import importlib.util
import struct
import unittest
from pathlib import Path

import numpy as np

spec = importlib.util.spec_from_file_location("lods", Path(__file__).resolve().parents[1] / "tools/asset_pipeline/pack_town_lods.py")
lods = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lods)


class TownLodsTests(unittest.TestCase):
    def test_odd_dimensions_and_every_alpha_match_scalar_reference(self):
        source = np.random.default_rng(913).integers(0, 256, (17, 19, 4), dtype=np.uint8)
        source.reshape(-1, 4)[:256, 3] = np.arange(256)
        result = lods.half(source)
        expected = np.zeros_like(result)
        for y in range(result.shape[0]):
            for x in range(result.shape[1]):
                points = source[y * 2:y * 2 + 2, x * 2:x * 2 + 2].reshape(-1, 4).astype(np.uint64)
                alpha = int(points[:, 3].sum())
                if alpha:
                    for channel in range(3):
                        expected[y, x, channel] = int((points[:, channel] * points[:, 3]).sum() / alpha + .5)
                    expected[y, x, 3] = int(alpha / len(points) + .5)
        np.testing.assert_array_equal(result, expected)

    def test_transparent_rgb_cannot_bleed_into_visible_edges(self):
        source = np.full((2, 2, 4), 255, dtype=np.uint8)
        source[:, :, 3] = 0
        source[0, 0] = [200, 30, 10, 255]
        np.testing.assert_array_equal(lods.half(source)[0, 0], [200, 30, 10, 64])

    def test_sparse_lighting_is_reversible_and_never_mutates_base(self):
        source = np.arange(16, dtype=np.uint8).reshape(2, 2, 4)
        patch = struct.pack("<III", 1, 1, 0xffffffff)
        changed = lods.apply_patch(source, patch)
        self.assertFalse(np.array_equal(changed, source))
        np.testing.assert_array_equal(lods.apply_patch(changed, patch), source)
        np.testing.assert_array_equal(source.reshape(-1), np.arange(16, dtype=np.uint8))

    def test_bad_runs_fail_before_source_changes(self):
        source = np.zeros((2, 2, 4), dtype=np.uint8)
        for patch in [b"bad", struct.pack("<III", 4, 1, 0), struct.pack("<II", 0, 1)]:
            with self.assertRaises(ValueError):
                lods.apply_patch(source, patch)
        self.assertFalse(source.any())

    def test_sparse_lod_differences_reconstruct_disjoint_and_adjacent_changes(self):
        base = np.zeros((4, 5, 4), dtype=np.uint8)
        current = base.copy()
        current[0, 1:3] = [1, 2, 3, 255]
        current[3, 4] = [4, 5, 6, 70]
        delta = lods.sparse_difference(base, current)
        np.testing.assert_array_equal(lods.apply_patch(base, delta), current)
        self.assertEqual(lods.sparse_difference(base, base), b"")


if __name__ == "__main__":
    unittest.main()
