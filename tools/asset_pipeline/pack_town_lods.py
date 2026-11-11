"""Optional local town LODs, byte-identical to ImagePixels.half and sparse TownPatch lighting.

python tools/asset_pipeline/pack_town_lods.py <DevAssets source> <output directory> --map saddle
Reads only existing converted local modules. Output embeds original art and MUST stay git-ignored.
"""
import argparse
import base64
import re
import struct
import zlib
from pathlib import Path

import numpy as np


def number(text, name):
    match = re.search(r"\b" + re.escape(name) + r"\s*=\s*(\d+)", text)
    if not match:
        raise ValueError(f"missing {name}")
    return int(match[1])


def encoded(text):
    match = re.search(r'\bdeflate\s*=\s*"([A-Za-z0-9+/=]*)"', text)
    return match[1] if match else ""


def half(source):
    """Integer premultiplied sums, Lua floor(x + .5) rounding, correct odd-edge counts."""
    h, w, _ = source.shape
    hh, ww = (h + 1) // 2, (w + 1) // 2
    alpha = np.zeros((hh * 2, ww * 2), dtype=np.uint64)
    alpha[:h, :w] = source[:, :, 3]
    weighted = np.zeros((hh * 2, ww * 2, 3), dtype=np.uint64)
    weighted[:h, :w] = source[:, :, :3].astype(np.uint64) * source[:, :, 3:4]
    count = np.zeros_like(alpha)
    count[:h, :w] = 1
    sums = weighted.reshape(hh, 2, ww, 2, 3).sum(axis=(1, 3))
    a = alpha.reshape(hh, 2, ww, 2).sum(axis=(1, 3))
    n = count.reshape(hh, 2, ww, 2).sum(axis=(1, 3))
    result = np.zeros((hh, ww, 4), dtype=np.uint8)
    present = a > 0
    result[present, :3] = np.floor(sums[present] / a[present, None] + .5).astype(np.uint8)
    result[present, 3] = np.floor(a[present] / n[present] + .5).astype(np.uint8)
    return result


def apply_patch(source, patch):
    rows, at, last = [], 0, 0
    while at < len(patch):
        if at + 8 > len(patch):
            raise ValueError("truncated patch header")
        offset, count = struct.unpack_from("<II", patch, at)
        at += 8
        if count == 0 or offset < last or offset + count > source.size // 4 or at + count * 4 > len(patch):
            raise ValueError("invalid patch run")
        rows.append((offset, count, at))
        at += count * 4
        last = offset + count
    out = source.copy()
    words = out.reshape(-1).view("<u4")
    for offset, count, at in rows:
        words[offset:offset + count] ^= np.frombuffer(patch, dtype="<u4", count=count, offset=at)
    return out


def raw(text, expected):
    data = zlib.decompress(base64.b64decode(encoded(text), validate=True), -15) if expected else b""
    if len(data) != expected:
        raise ValueError("converted pixel/patch length mismatch")
    return data


def sparse_difference(base, current):
    words = np.bitwise_xor(base.reshape(-1).view("<u4"), current.reshape(-1).view("<u4"))
    indices = np.flatnonzero(words)
    if not indices.size:
        return b""
    starts = np.r_[0, np.flatnonzero(np.diff(indices) != 1) + 1]
    ends = np.r_[starts[1:], len(indices)]
    return b"".join(struct.pack("<II", int(indices[a]), int(b - a)) + words[indices[a]:indices[b - 1] + 1].tobytes() for a, b in zip(starts, ends))


def compress(data):
    encoder = zlib.compressobj(6, zlib.DEFLATED, -15)
    return base64.b64encode(encoder.compress(data) + encoder.flush()).decode("ascii")


def build(source, output, map_id):
    source, output = source.resolve(), output.resolve()
    if output.name != "DevAssets" and "DevAssets" not in output.parts:
        raise ValueError("output must be a local git-ignored DevAssets directory")
    if not re.fullmatch(r"[A-Za-z0-9_]+", map_id):
        raise ValueError("invalid map id")
    meta = (source / f"City_{map_id}.luau").read_text(encoding="utf-8")
    lighting = re.search(r"lighting\s*=\s*\{([^}]+)\}", meta)
    base = number(lighting[1], "base") if lighting else 0
    frames = range(1, number(lighting[1], "steps") + 2) if lighting else [0]
    matcher = re.compile(r"City_" + re.escape(map_id) + r"_\d+_\d+\.luau$")
    sources = sorted(p for p in source.glob(f"City_{map_id}_*.luau") if matcher.fullmatch(p.name))
    if not sources:
        raise ValueError("no converted town source chunks")
    output.mkdir(parents=True, exist_ok=True)
    count = 0
    for path in sources:
        text = path.read_text(encoding="utf-8")
        w, h = number(text, "width"), number(text, "height")
        original = np.frombuffer(raw(text, w * h * 4), dtype=np.uint8).reshape(h, w, 4)
        source_hash = zlib.adler32(encoded(text).encode("ascii"))
        base_levels = {2: half(original)}
        base_levels[4] = half(base_levels[2])
        patches = {2: [], 4: []}
        for frame in frames:
            patch_text = "" if frame == base else (source / f"{path.stem}_Light{frame}.luau").read_text(encoding="utf-8")
            patch = raw(patch_text, number(patch_text, "bytes")) if patch_text else b""
            lit = apply_patch(original, patch)
            patch_hash = zlib.adler32(encoded(patch_text).encode("ascii"))
            for stride in (2, 4):
                lit = half(lit)
                delta = sparse_difference(base_levels[stride], lit)
                data = compress(delta) if delta else ""
                patches[stride].append(f'[{frame}]={{ sourceHash={patch_hash}, bytes={len(delta)}, deflate="{data}" }}')
        for stride in (2, 4):
            level = base_levels[stride]
            data = compress(level.tobytes())
            target = output / f"{path.stem}_Mip{stride}.luau"
            target.write_text("-- GENERATED original-art LOD; local only, git-ignored.\n"
                f'return {{ format=2, stride={stride}, baseFrame={base}, width={level.shape[1]}, height={level.shape[0]}, '
                f'sourceHash={source_hash}, deflate="{data}", patches={{' + ",".join(patches[stride]) + "} }\n", encoding="utf-8")
            count += 1
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--map", default="saddle")
    args = parser.parse_args()
    print(f"Generated {build(args.source, args.output, args.map)} ignored town LOD modules")
