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


def verify_initialization(records: list) -> list:
    observations = []
    for record in records:
        if 'initialization' not in record:
            continue
        sample = record['initialization']
        before, after = sample['before'], sample['after']
        words = list(before['words'])
        cursor, draws = before['cursor'] // 4, 0
        assert before['context'] == after['context'] and before['cursor'] % 4 == 0

        def draw(count):
            nonlocal cursor, draws
            assert draws < 1000, 'unexpected native contrast retry count'
            if cursor == 624:
                for i in range(624):
                    value = (words[i] & 0x80000000) | (words[(i + 1) % 624] & 0x7fffffff)
                    words[i] = words[(i + 397) % 624] ^ (value >> 1) ^ (0x9908b0df if value & 1 else 0)
                cursor = 0
            value = words[cursor] % 0x7fffffff
            cursor += 1
            draws += 1
            return value // (0x7fffffff // count + 1)

        palette = sample['swatches']
        assert len(palette) == 1080

        def color():
            index = draw(36) * 10 + draw(10)
            return [palette[index + channel * 360] for channel in range(3)]

        index, foreground, background = draw(23), color(), color()
        while max(abs(a - b) for a, b in zip(foreground, background)) < 64:
            background = color()
        assert sample['symbol'] == [index] + foreground + background, 'native initialized symbol differs'
        assert after['cursor'] == cursor * 4 and after['words'] == words, 'native RNG consumption differs'
        observations.append(dict(capture=record['name'], invalid=sample['invalid'], symbol=sample['symbol'],
                                 draws=draws, controlled=sample['controlled'], swatches_sha256=hashlib.sha256(bytes(palette)).hexdigest()))
    assert len(observations) == 8 and any(s['draws'] > 5 for s in observations), 'missing initialization/retry cases'
    return observations


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
                source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), observations=observations,
                initialization=verify_initialization(result['records']))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--df-path', type=Path, required=True)
    args = parser.parse_args()
    result = verify(args.run, args.df_path)
    (args.run / 'symbol-pixels.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('SQUAD_SYMBOL_PIXELS_PASS: 31 symbols, 62 textures, 31 rendered crops')
