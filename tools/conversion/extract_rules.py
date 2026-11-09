#!/usr/bin/env python3
"""Pull the 'Every rule you can change' table out of dist/modding-guide.html.
Usage: python extract_rules.py <modding-guide.html> <rules.tsv>
Output: one 'key<TAB>value' line per rule (expect 1435)."""
import html, re, sys

def main(src, dst):
    t = open(src, encoding='utf-8').read()
    t = re.sub(r'<style.*?</style>|<script.*?</script>', '', t, flags=re.S)
    i = t.rfind('Every rule you can change')  # last occurrence; the first is the table of contents
    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', t[i:], flags=re.S)
    out = []
    for r in rows:
        cells = [html.unescape(re.sub(r'<[^>]+>', '', c)).strip()
                 for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', r, flags=re.S)]
        if len(cells) == 2 and '.' in cells[0]:
            out.append(f'{cells[0]}\t{cells[1]}')
    open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(f'{len(out)} rules written to {dst}')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
