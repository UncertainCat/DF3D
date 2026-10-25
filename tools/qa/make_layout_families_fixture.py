"""Build native layout-stage replay cases without distributing game pixels."""
from pathlib import Path
import gzip,json,subprocess
root=Path(__file__).resolve().parents[2]
source=json.loads(gzip.decompress((root/'fixtures/construction/layout_families_rendering.json.gz').read_bytes()))
materials=['INORGANIC:GRANITE','INORGANIC:IRON','GLASS_GREEN','PLANT:OAK:WOOD']
lines=[]
for c in source['cases']:
    material=-1 if c['material']=='NONE' else materials.index(c['material'])
    values=[c['kind'],c['subtype_id'],c.get('custom','-'),c['stage'],c['maximum'],c['width'],c['height'],material]
    lines.append(' '.join(map(str,values)))
(root/'build/layout-families-input.txt').write_text('\n'.join(lines)+'\n')
(root/'build/layout-families-pixels.json').write_text(json.dumps(source['cases']))
subprocess.run([str(root/'build/tools/make_layout_families_fixture.exe'),str(root/'build/layout-families-input.txt'),str(root/'build/layout-families.df3dfix')],check=True)
print('QA_LAYOUT_FAMILIES_FIXTURE_PASS',len(lines))
