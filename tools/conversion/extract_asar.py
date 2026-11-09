#!/usr/bin/env python3
"""Extract an Electron app.asar (read-only on the source) into a separate output folder.
Usage: python extract_asar.py <path/to/app.asar> <out_dir>
Never point out_dir inside the game install."""
import json, os, struct, sys

def main(src, dst):
    with open(src, 'rb') as f:
        _, header_size, _, json_len = struct.unpack('<IIII', f.read(16))
        header = json.loads(f.read(json_len))
        base = 8 + header_size
        count = 0
        def walk(node, path):
            nonlocal count
            for name, entry in node.get('files', {}).items():
                out = os.path.join(path, name)
                if 'files' in entry:
                    os.makedirs(out, exist_ok=True); walk(entry, out)
                elif entry.get('unpacked') or 'link' in entry:
                    continue  # lives in app.asar.unpacked / symlink
                else:
                    f.seek(base + int(entry['offset']))
                    with open(out, 'wb') as o:
                        o.write(f.read(entry['size']))
                    count += 1
        os.makedirs(dst, exist_ok=True)
        walk(header, dst)
    print(f'{count} files extracted to {dst}')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
