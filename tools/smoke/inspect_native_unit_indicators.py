"""Build-pinned, read-only evidence for DF's native overhead status selector.

This disassembles a bounded set of functions. It never calls native functions,
attaches to a process, changes game state, or supplies runtime presentation data.
"""
import os
import argparse
import hashlib
import json
import struct
import re
import xml.etree.ElementTree as ET
from pathlib import Path

import capstone
import pefile

EXPECTED = '205770918fd54c96cbbcf89223ebd449e2e113c7c873ed81177c4511a3450db7'
REGIONS = {
    'status_asset_binding': (0x11a3183, 0x11a31fe),
    'overhead_draw_call': (0xea329b, 0xea339c),
    'status_selector': (0x269340, 0x269acd),
    'injury_classification': (0x136ea20, 0x136eb19),
    'critical_missing_part': (0x1383a70, 0x1383b39),
    'fortress_control_gate': (0x138ed20, 0x138ee1f),
    'adventure_needs_comparison_only': (0xb00904, 0xb00c09),
    'map_warning_asset_binding': (0x125c519, 0x125c648),
    'map_warning_draw': (0xe86000, 0xe86240),
    'map_viewport_eligibility': (0xe84bc0, 0xe84da3),
    'map_passability_gate': (0x14c9be0, 0x14c9d3d),
    'map_tile_passability_lookup': (0x1436f30, 0x1436f5f),
    'map_closed_door': (0x5a8320, 0x5a838b),
    'map_closed_wall_grate': (0x5a8470, 0x5a84db),
    'map_closed_vertical_bars': (0x5a8550, 0x5a85bb),
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', default=os.path.join(os.environ.get('DF3D_DF_PATH', 'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'), 'Dwarf Fortress.exe'))
    parser.add_argument('--output', default='build/native-unit-indicators.json')
    args = parser.parse_args()
    raw = Path(args.exe).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED:
        raise SystemExit('Unsupported executable: expected Steam DF 53.16')
    pe = pefile.PE(data=raw)
    disassembler = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    evidence = {
        key: [f'{i.address:08x} {i.mnemonic} {i.op_str}'
              for i in disassembler.disasm(pe.get_data(start, end-start), start)]
        for key, (start, end) in REGIONS.items()
    }
    selector = '\n'.join(evidence['status_selector'])
    assert 'cmp dword ptr [r15 + 0x98c], 0x61a8' in selector
    assert 'cmp dword ptr [r15 + 0x988], 0xc350' in selector
    assert 'cmp dword ptr [r15 + 0x990], 0xe100' in selector
    clock = next(f.name.decode() for dll in pe.DIRECTORY_ENTRY_IMPORT for f in dll.imports
                 if f.address-pe.OPTIONAL_HEADER.ImageBase == 0x26936c+0x137be7c)
    assert clock == 'GetTickCount'
    warning_tools = [i for i in range(25)
                     if struct.unpack('<I', pe.get_data(
                         0xe8d124 + pe.get_data(0xe8d12c+i, 1)[0]*4, 4))[0] == 0xe86144]
    assert warning_tools == list(range(7)) + [23, 24]
    nonpassable_tiles = [i for i in range(1, 695)
                        if pe.get_data(0x1436f68+i-1, 1)[0] == 1]
    root = Path(__file__).resolve().parents[2]
    tile_names = {int(i): name for name, i in re.findall(
        r'^\s*(\w+).*?// (\d+),',
        (root/'external/dfhack/library/include/df/tiletype.h').read_text(), re.M)}
    tile_enum = ET.parse(root/'external/dfhack/library/xml/df.d_basics.xml').getroot().find(
        "enum-type[@type-name='tiletype']")
    tile_shapes = {e.get('name'): next((a.get('value') for a in e.findall('item-attr')
                                      if a.get('name') == 'shape'), 'NONE')
                   for e in tile_enum.findall('enum-item')}
    nonpassable_names = [{'id': i, 'name': tile_names.get(i),
                         'shape': tile_shapes.get(tile_names.get(i), 'NONE')}
                        for i in nonpassable_tiles]
    assert sum(x['shape'] == 'TRUNK_BRANCH' for x in nonpassable_names) == 8
    assert sum(x['shape'] == 'BROOK_BED' for x in nonpassable_names) == 8
    result = {
        'executable_sha256': digest,
        'status_atlas_rva': '0x266d24c',
        'selector_rva': '0x269340',
        'clock': clock,
        'phase': 'uint32(GetTickCount() + unit.id * 34536) % 7000',
        'movement_only_phase': 'phase <= 5000',
        'thresholds': {'thirst': 25000, 'hunger': 50000, 'drowsy': 57600,
                       'paralysis': 100, 'webbed': 10, 'stress': 10000,
                       'distracted_focus_percent_at_most': 80},
        'map_warning_tools': warning_tools,
        'map_nonpassable_tile_ids': nonpassable_tiles,
        'map_nonpassable_tiles': nonpassable_names,
        'map_warning_fortification_exclusions': [65, 322, 323, 356, 432, 490],
        'warnings': [
            'Adventure status-row hunger/thirst/drowsy thresholds differ; do not reuse them for fortress overheads.',
            'Native picks one eligible status by priority; this is not round-robin cycling through every status.',
            'The native focus and limb helpers can update derived caches. Copy semantic rules; do not invoke presentation functions.',
        ],
        'evidence': evidence,
    }
    path = Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'output': str(path), 'regions': len(evidence),
                      'selector_rva': result['selector_rva'], 'thresholds': result['thresholds']}))

if __name__ == '__main__':
    main()
