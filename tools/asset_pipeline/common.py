"""Shared constants and helpers for the sprite pipeline (Python 3, Pillow)."""
import json, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# WarFront's facing convention, recovered from the game's renderer (see docs/sprites/FACING_CONVENTION.md):
# index = round(angle / (2*pi/16)) mod 16, angle = atan2(dy, dx) with y pointing down,
# so index 0 faces east (+x) and indices increase clockwise on screen. Pivot = frame centre.
DIRECTION_ORDER = {
    "count": 16,
    "zero": "east",
    "winding": "clockwise",
    "stepDegrees": 22.5,
    "angleSource": "atan2(dy, dx), pixel y down",
}

def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def save_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")

def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")
