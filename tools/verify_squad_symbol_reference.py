"""Compare protected native squad captures with installed symbol masks.

Diagnostic only: native texture IDs and dumps are never product inputs.
No game artwork is copied into the repository or the compact result.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

from PIL import Image


def verify(run: Path, df_path: Path) -> dict:
    graphics = df_path / 'data/vanilla/vanilla_interface/graphics'
    definitions = (graphics / 'graphics_interface.txt').read_text(encoding='utf-8')
    tiles = re.findall(r'\[TILE_GRAPHICS:CUSTOM_SYMBOLS:(\d+):(\d+):CUSTOM_SYMBOL\]', definitions)
    assert len(tiles) == 23, 'native custom-symbol mapping changed'
    pages = (graphics / 'tile_page_interface.txt').read_text(encoding='utf-8')
    page = re.search(r'\[TILE_PAGE:CUSTOM_SYMBOLS\](.*?)(?=\[TILE_PAGE:|\Z)', pages, re.S)
    assert page and '[TILE_DIM:32:32]' in page[1], 'symbol tile dimensions changed'
    source = graphics / re.search(r'\[FILE:([^\]]+)\]', page[1])[1]
    sheet = Image.open(source).convert('RGBA')
    result = json.loads((run / 'result.json').read_text(encoding='utf-8'))
    assert result['success'], 'native diagnostic failed'
    observations = []
    for record in result['records']:
        if not record.get('symbols'):
            continue
        screenshot = Image.open(run / (record['name'] + '.png')).convert('RGB')
        for row, symbol in enumerate(record['symbols']):
            x, y = map(int, tiles[symbol['index']])
            assert (symbol['page'], symbol['x'], symbol['y']) == ('CUSTOM_SYMBOLS', x, y)
            mask = sheet.crop((x * 32, y * 32, (x + 1) * 32, (y + 1) * 32))
            hashes = {}
            # DF40ac50 tests source alpha !=0, ignores mask RGB and alpha
            # magnitude, and uses alpha255 for solid /160 for blended output.
            for variant, alpha in [('solid', 255), ('blended', 160)]:
                expected = bytes(component for pixel in mask.getdata()
                                 for component in [*(symbol['foreground'] if pixel[3] else symbol['background']), alpha])
                observed = (run / symbol[variant + '_file']).read_bytes()
                assert observed == expected, f'{record["name"]} {variant} pixels differ'
                hashes[variant + '_sha256'] = hashlib.sha256(observed).hexdigest()
                if variant == 'solid':
                    rgb = Image.frombytes('RGBA', (32, 32), observed).convert('RGB').tobytes()
                    top = 102 + row * 36
                    assert screenshot.crop((376, top, 408, top + 32)).tobytes() == rgb, f'{record["name"]} row{row} rendered symbol differs'
            observations.append(dict(capture=record['name'], id=symbol['id'], index=symbol['index'],
                                     x=x, y=y, foreground=symbol['foreground'], background=symbol['background'],
                                     **hashes))
    assert {o['index'] for o in observations if '-symbol-' in o['capture']} == set(range(23)), 'missing mask cases'
    assert len(observations) == 31, 'missing ordinary picker rows'
    return dict(scope='All23 masks plus4 ordinary squads in each picker; exact solid/blended RGBA and rendered32x32 RGB',
                source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), observations=observations)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--df-path', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.run, args.df_path)
    (args.run / 'symbol-pixels.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('SQUAD_SYMBOL_PIXELS_PASS: 31 symbols, 62 textures, 31 rendered crops')
