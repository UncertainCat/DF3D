"""Replay captured additional native shapes through the real Lua reader/C++ route."""
import json
import gzip
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
    with gzip.open(ROOT / 'fixtures/construction/track_terrain_query.json.gz', 'rt', encoding='utf-8') as f:
        captured=json.load(f)['runs']['construction-track-terrain-all-20261023-035931']['rows']
    answers={r['terrain']:r['selected'] for r in captured if r['occupancy']==0 and r['below']=='StoneWall' and r['perimeter']=='StoneFloorSmooth'}
    script = 'terrain_answers=' + lua(answers) + '\nlocal cases=' + lua(cases) + '''
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
    queued=json.loads((ROOT / 'fixtures/construction/connected_track.json').read_text(encoding='utf-8'))['queued_construction_conversion']['cases']
    queued+=json.loads((ROOT / 'fixtures/construction/connected_track.json').read_text(encoding='utf-8'))['queued_construction_terrain_merge']['cases']
    script += '\nlocal queued=' + lua(queued) + """
df.building_type={[0]='Construction'};df.construction_type={}
local next_enum=0
local function enum(name)
 if df.construction_type[name]==nil then df.construction_type[name]=next_enum;df.construction_type[next_enum]=name;next_enum=next_enum+1 end
 return df.construction_type[name]
end
local function mask(name)
 local result=0;for letter in (name:match('TrackRamp([NSEW]+)$')or name:match('Track([NSEW]+)$')or ''):gmatch('.')do result=result|({N=1,S=2,E=4,W=8})[letter]end;return result
end
df.tiletype_shape.RAMP='RAMP';df.tiletype[44]='StoneRamp';df.tiletype.attrs[44]={shape='RAMP',material=0}
dfhack.buildings.markedForRemoval=function()return false end
for _,c in ipairs(queued)do
 local jobs={};local path={}
 for i,b in ipairs(c.before)do
  local subtype=enum(b.subtype)
  jobs[i]={id=b.id,getType=function()return 0 end,getSubtype=function()return subtype end,getBuildStage=function()return 0 end,getMaxBuildStage=function()return 1 end}
  local x=i+4;path[i]={x=x,y=7,z=0};block.tiletype[x][7]=c.terrain=='ramp' and 44 or 43;block.occupancy[x][7].building=1
  if c.terrain:find('Constructed',1,true) then
   df.tiletype[45]=c.terrain;df.tiletype.attrs[45]={shape=c.terrain:find('Ramp',1,true) and 'RAMP' or 'FLOOR',material=1};block.tiletype[x][7]=45
  end
 end
 dfhack.buildings.findAtTile=function(p)if p.y==7 then return jobs[p.x-4]end end
 if c.reverse then path={path[4],path[3],path[2],path[1]}end
 local r=route(native_reader,path[1],path[4],{x=14,y=14,z=0})
 assert(r.status==0 and #r.path==4,'queued native route rejected '..c.existing..' '..c.terrain)
 local p=plan(native_reader,r.path)
 assert(p.verified and p.new_count==0,'queued construction did not reuse recipe')
 for _,piece in ipairs(p.pieces)do
  local index=piece.x-4;local old,new=c.before[index],c.after[index]
  assert(piece.building_id==old.id and piece.expected_subtype==enum(old.subtype))
  assert(piece.connections==mask(new.subtype) and piece.ramp==(new.subtype:find('TrackRamp',1,true)~=nil),'queued shape/connections mismatch')
  assert(piece.action==(old.subtype==new.subtype and 2 or 1),'queued action mismatch')
 end
end
print('TRACK_QUEUED_NATIVE_PASS '..#queued)
"""
    with tempfile.TemporaryDirectory(prefix='track-shapes-', dir=ROOT / 'build/qa') as temp:
        path = Path(temp) / 'replay.lua'
        path.write_text(script, encoding='utf-8')
        subprocess.run([str(Path(sys.argv[1]).resolve()), str(ROOT / 'bridge/plugin/construction_track.lua'), str(path)], check=True, timeout=30)


if __name__ == '__main__':
    main()
