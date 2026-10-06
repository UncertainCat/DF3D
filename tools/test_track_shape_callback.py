"""Replay captured additional native shapes through the real Lua reader/C++ route."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'


def main():
    cases = json.loads((ROOT / 'fixtures/construction/connected_track.json').read_text())['additional_terrain_shapes']['cases']
    script = 'local cases=' + lua(cases) + '''
df={tiletype_shape={},tiletype_material={CONSTRUCTION=1},tiletype={
 [43]='StoneFloorSmooth',OpenSpace=32,Chasm=19,EeriePit=21,attrs={[43]={shape='FLOOR',material=0}}}}
df.tiletype_shape.FLOOR='FLOOR'
local block={tiletype={},designation={},occupancy={},walkable={}}
for x=0,15 do
 block.tiletype[x]={};block.designation[x]={};block.occupancy[x]={};block.walkable[x]={}
 for y=0,15 do
  block.tiletype[x][y]=43;block.designation[x][y]={hidden=false,flow_size=0,liquid_type=false}
  block.occupancy[x][y]={building=0};block.walkable[x][y]=1
 end
end
dfhack={maps={getTileBlock=function()return block end},buildings={findAtTile=function()return nil end}}
for i,c in ipairs(cases)do
 local id=1000+i
 df.tiletype[id]=c.tile;df.tiletype.attrs[id]={shape=c.shape,material=0};df.tiletype_shape[c.shape]=c.shape
 block.tiletype[8][7]=id;block.walkable[8][7]=c.walkable
 local goal={x=7+c.target[1],y=7+c.target[2],z=c.target[3]}
 local r=route(native_reader,{x=7,y=7,z=0},goal,{x=14,y=14,z=0})
 assert(r.status==( #c.path==0 and 1 or 0),'shape status mismatch '..c.scenario)
 assert(#r.path==#c.path,'shape route length mismatch '..c.scenario)
 for n,p in ipairs(r.path)do
  local expected=c.path[n]
  assert(p.x==expected.x+7 and p.y==expected.y+7 and p.z==expected.z,'shape route mismatch '..c.scenario)
 end
end
print('TRACK_SHAPE_NATIVE_PASS '..#cases)
'''
    with tempfile.TemporaryDirectory(prefix='track-shapes-', dir=ROOT / 'build/qa') as temp:
        path = Path(temp) / 'replay.lua'
        path.write_text(script, encoding='utf-8')
        subprocess.run([str(Path(sys.argv[1]).resolve()), str(ROOT / 'bridge/plugin/construction_track.lua'), str(path)], check=True, timeout=30)


if __name__ == '__main__':
    main()
