-- Verifies designation acceptance cases. The pending-job case MUTATES game
-- state (creates a Dig job and clears the tile designation); run only on a
-- disposable clone save in an owned, never-saved session.
local index=tonumber(...)
local c=assert(df3d_designation_acceptance[index]);local rows={}
local function read(p)
 local b=assert(dfhack.maps.getTileBlock(p));local lx,ly=p.x%16,p.y%16;local d=b.designation[lx][ly];local o=b.occupancy[lx][ly]
 local row={dig=df.tile_dig_designation[d.dig],smooth=d.smooth,auto=o.dig_auto,marked=o.dig_marked,priority=4000,jobs={}}
 for _,e in ipairs(b.block_events) do if df.block_square_event_designation_priorityst:is_instance(e) then row.priority=e.priority[lx][ly];break end end
 for _,j in require('utils').listpairs(df.global.world.jobs.list) do if j.pos.x==p.x and j.pos.y==p.y and j.pos.z==p.z then row.jobs[#row.jobs+1]=df.job_type[j.job_type] end end
 return row
end
local row=read(c.tile);rows[1]=row
for k,v in pairs(c.expected) do assert(row[k]==v,c.name..' '..k..' expected '..tostring(v)..' got '..tostring(row[k])) end
if c.levels then for i,v in ipairs(c.levels) do local r=read({x=c.tile.x,y=c.tile.y,z=c.tile.z+i-1});rows[i]=r;assert(r.dig==v and r.marked==c.expected.marked and r.priority==c.expected.priority,c.name..' level '..i..' mismatch '..require('json').encode(r)) end end
if c.smooth_levels then for i,v in ipairs(c.smooth_levels) do local r=read({x=c.tile.x,y=c.tile.y,z=c.tile.z+i-1});rows[i]=r;assert(r.smooth==v and r.marked==c.expected.marked and r.priority==c.expected.priority,c.name..' level '..i..' mismatch') end end
if c.no_jobs then assert(#row.jobs==0,'marker left pending job active') end
if c.track_check then
 local count=0;local outside=false
 for x=c.tile.x-1,c.tile.x+5 do for y=c.tile.y-3,c.tile.y+3 do
  local b=dfhack.maps.getTileBlock(x,y,c.tile.z);local o=b.occupancy[x%16][y%16]
  local mask=(o.carve_track_north and 1 or 0)+(o.carve_track_south and 2 or 0)+(o.carve_track_east and 4 or 0)+(o.carve_track_west and 8 or 0)
  if mask>0 then count=count+1;outside=outside or y~=c.tile.y;assert(o.dig_marked,'route marker not set') end
  if x==c.tile.x+2 and y==c.tile.y then assert(mask==0,'track crosses wall') end
 end end
 assert(count==7 and outside,'expected seven-tile obstacle detour; got '..count)
 row.route_count=count;row.route_outside_selection=outside
end
local d=df.global.game.main_interface.designation
assert(d.priority==7000 and not d.marker_only and d.mine_mode==df.mine_mode_type.MARK_GEMS_ONLY,'native option state was mutated')
assert(table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen(true)),',')==df3d_designation_acceptance_focus,'native designation context unexpectedly changed')
if c.name=='activate preserves priority' then
 local j=df.job:new();j.job_type=df.job_type.Dig;j.pos:assign(c.tile);assert(dfhack.job.linkIntoWorld(j,true));local b=dfhack.maps.getTileBlock(c.tile);b.designation[c.tile.x%16][c.tile.y%16].dig=df.tile_dig_designation.No;print('SEEDED_PENDING_JOB '..j.id)
end
if c.name=='hold preserves priority' then assert(#row.jobs==0,'hold left pending job active') end
print('SEMANTIC_PASS '..c.name..' '..require('json').encode(rows))
