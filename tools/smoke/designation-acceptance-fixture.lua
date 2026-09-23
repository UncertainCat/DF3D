-- Development-only fixtures. Owned paused session exits without saving.
local out=...
local json=require('json')
df.global.pause_state=true
local u
for _,v in ipairs(df.global.world.units.active) do if dfhack.units.isCitizen(v) then u=v;break end end
assert(u,'citizen required')
local x,y,z=u.pos.x,u.pos.y,u.pos.z
local cases={}
local function tile(px,py,pz,typ)
 local b=assert(dfhack.maps.getTileBlock(px,py,pz));local lx,ly=px%16,py%16
 b.tiletype[lx][ly]=assert(df.tiletype[typ]);b.designation[lx][ly].whole=0;b.occupancy[lx][ly].whole=0
 return {x=px,y=py,z=pz}
end
local function add(name,method,p,kind,priority,marker,expected,extra)
 local c={name=name,method=method,tile=p,kind=kind,priority=priority,marker=marker,expected=expected}
 for k,v in pairs(extra or {}) do c[k]=v end;cases[#cases+1]=c
end
local p=tile(x,y,z,'StoneWall')
add('dig explicit marker priority','dig',p,0,2,true,{dig='Default',marked=true,priority=2000})
add('activate preserves priority','dig',p,8,6,true,{dig='Default',marked=false,priority=2000})
add('hold preserves priority','dig',p,9,6,false,{dig='Default',marked=true,priority=2000})
add('erase designation','dig',p,6,4,false,{dig='No',marked=false})
p=tile(x+1,y,z,'StoneRamp');add('remove ramp','dig',p,7,3,true,{dig='Default',marked=true,priority=3000})
p=tile(x+2,y,z,'StoneWall');add('smooth','smooth',p,0,5,true,{smooth=1,marked=true,priority=5000})
p=tile(x+3,y,z,'StoneFloorSmooth');add('engrave','smooth',p,1,6,true,{smooth=2,marked=true,priority=6000})
p=tile(x+4,y,z,'StoneWallSmoothRD2');add('fortify','smooth',p,3,1,true,{smooth=1,marked=true,priority=1000})
p=tile(x+5,y,z,'StoneWall');tile(x+5,y,z+1,'StoneWall');tile(x+5,y,z+2,'StoneWall')
add('stairs span','stairs',p,0,3,true,{dig='UpStair',marked=true,priority=3000},{z2=z+2,levels={'UpStair','UpDownStair','DownStair'}})
p=tile(x+6,y,z,'StoneWall');tile(x+6,y,z+1,'StoneFloorSmooth');tile(x+6,y,z+2,'StoneWall')
add('stairs floor middle','stairs',p,0,2,true,{dig='UpStair',marked=true,priority=2000},{z2=z+2,levels={'UpStair','DownStair','DownStair'}})
for px=x-3,x+3 do for py=y+4,y+10 do tile(px,py,z,'StoneFloorSmooth') end end
tile(x,y+7,z,'StoneWall')
p={x=x-2,y=y+7,z=z};add('track obstacle route','track',p,0,4,true,{marked=true,priority=4000},{width=5,track_check=true})
p=tile(x+7,y,z,'MineralWall')
local b=dfhack.maps.getTileBlock(p);local mineral=df.block_square_event_mineralst:new()
for i,r in ipairs(df.global.world.raws.inorganics.all) do if r.id=='HEMATITE' then mineral.inorganic_mat=i;break end end
mineral.tile_bitmask.bits[p.y%16]=1 << (p.x%16);b.block_events:insert('#',mineral)
add('automatic ore mining','dig',p,0,2,true,{dig='Default',marked=true,priority=2000,auto=true},{mining_mode=1})
p=tile(x+8,y,z,'StoneWall')
local job=df.job:new();job.job_type=df.job_type.Dig;job.pos:assign(p);assert(dfhack.job.linkIntoWorld(job,true))
add('new marker replaces active job','dig',p,0,3,true,{dig='Default',marked=true,priority=3000},{no_jobs=true})
p=tile(x+9,y,z,'StoneWall');add('single elevation stairs rejected','stairs',p,0,4,false,{dig='No',marked=false},{z2=z,status=1})
for i,typ in ipairs({'StoneRamp','StoneStairU','StoneStairUD','StoneStairD'}) do
 p=tile(x+9+i,y,z,typ);add('mine ignores '..typ,'dig',p,0,4,false,{dig='No',marked=false},{status=1})
end
for dz=0,2 do tile(x,y+1,z+dz,'StoneWall');tile(x+1,y+1,z+dz,'StoneWall') end
p={x=x,y=y+1,z=z};add('mine three elevations','dig',p,0,2,true,{dig='Default',marked=true,priority=2000},{max_z=z+2,levels={'Default','Default','Default'}})
add('activate three elevations','dig',p,8,6,false,{dig='Default',marked=false,priority=2000},{max_z=z+2,levels={'Default','Default','Default'}})
add('hold three elevations','dig',p,9,6,false,{dig='Default',marked=true,priority=2000},{max_z=z+2,levels={'Default','Default','Default'}})
p={x=x+1,y=y+1,z=z};add('smooth three elevations','smooth',p,0,6,true,{smooth=1,marked=true,priority=6000},{max_z=z+2,smooth_levels={1,1,1}})
p=tile(x+2,y+1,z,'MineralWall')
local block=dfhack.maps.getTileBlock(p);local coal=df.block_square_event_mineralst:new()
for i,r in ipairs(df.global.world.raws.inorganics.all) do if r.id=='LIGNITE' then coal.inorganic_mat=i;break end end
coal.tile_bitmask.bits[p.y%16]=1 << (p.x%16);block.block_events:insert('#',coal)
add('automatic coal mining','dig',p,0,2,true,{dig='Default',marked=true,priority=2000,auto=true},{mining_mode=1})
add('erase automatic mining','dig',p,6,4,false,{dig='No',marked=false,auto=false})
add('ore gem excludes coal','dig',p,0,2,true,{dig='No',marked=false,auto=false},{mining_mode=2,status=1})
p=tile(x+3,y+1,z,'StoneWall');add('automatic excludes layer','dig',p,0,2,true,{dig='No',marked=false,auto=false},{mining_mode=1,status=1})
local found={}
for _,plant in ipairs(df.global.world.plants.all) do
 local tree=plant.tree_info~=nil;local shrub=df.plant_type.attrs[plant.type].is_shrub
 local name=tree and 'chop' or shrub and 'gather' or nil
 if name and not found[name] then
  local px,py,pz=dfhack.designations.getPlantDesignationTile(plant);local b=dfhack.maps.getTileBlock(px,py,pz)
  if b and not b.designation[px%16][py%16].hidden then
   dfhack.designations.unmarkPlant(plant);b.occupancy[px%16][py%16].dig_marked=false
   p={x=px,y=py,z=pz};add(name,name,p,0,name=='chop' and 2 or 3,true,{dig='Default',marked=true,priority=name=='chop' and 2000 or 3000});found[name]=true
  end
 end
 if found.chop and found.gather then break end
end
assert(found.chop and found.gather,'need native plants')
p=tile(x+4,y+1,z,'StoneFloorSmooth');local track_job=df.job:new();track_job.job_type=df.job_type.CarveTrack;track_job.pos:assign(p)
track_job.specflag.carve_track_flags.carve_track_east=true;track_job.specflag.carve_track_flags.carve_track_west=true;assert(dfhack.job.linkIntoWorld(track_job,true))
add('erase pending track job','smooth',p,2,4,false,{smooth=0,marked=false},{check_track_job=true,no_jobs=true})
local gui=require('gui');local s=dfhack.gui.getCurViewscreen(true)
df.global.game.main_interface.designation.mine_mode=df.mine_mode_type.ALL
local function click(px,py)
 local g=df.global.gps;local scale=g.viewport_zoom_factor/4
 g.precise_mouse_x=math.floor((px-df.global.window_x+.5)*scale);g.precise_mouse_y=math.floor((py-df.global.window_y+.5)*scale)
 g.mouse_x=math.floor(g.precise_mouse_x/g.tile_pixel_x);g.mouse_y=math.floor(g.precise_mouse_y/g.tile_pixel_y);df.global.enabler.tracking_on=1
 s:render(dfhack.getTickCount());local q=dfhack.gui.getMousePos();assert(q.x==px and q.y==py);gui.simulateInput(s,'_MOUSE_L')
end
for _,typ in ipairs({'StoneRamp','StoneStairU','StoneStairUD','StoneStairD'}) do
 tile(x,y+12,z,typ);tile(x+1,y+12,z,typ)
 gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'D_DESIGNATE_DIG');gui.simulateInput(s,'DESIGNATE_DIG');gui.simulateInput(s,'DESIGNATE_RECTANGLE')
 dfhack.gui.revealInDwarfmodeMap(x,y+12,z,true);click(x,y+12);click(x+1,y+12)
 local b=dfhack.maps.getTileBlock(x,y+12,z);print('NATIVE_MINE '..typ..' '..df.tile_dig_designation[b.designation[x%16][(y+12)%16].dig])
end
for dz=0,2 do for dx=0,1 do tile(x+dx,y+13,z+dz,'StoneWall') end end
gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'D_DESIGNATE_DIG');gui.simulateInput(s,'DESIGNATE_DIG');gui.simulateInput(s,'DESIGNATE_RECTANGLE')
dfhack.gui.revealInDwarfmodeMap(x,y+13,z,true);click(x,y+13);df.global.window_z=z+2;click(x+1,y+13)
for dz=0,2 do local b=dfhack.maps.getTileBlock(x,y+13,z+dz);print('NATIVE_MINE_SPAN '..dz..' '..df.tile_dig_designation[b.designation[x%16][(y+13)%16].dig]) end
for n,material in ipairs({'LIGNITE','HEMATITE','LAYER'}) do
 local px,py=x+2*n+2,y+13
 for dx=0,1 do
  local p=tile(px+dx,py,z,material=='LAYER' and 'StoneWall' or 'MineralWall')
  if material~='LAYER' then
   local b=dfhack.maps.getTileBlock(p);local event=df.block_square_event_mineralst:new();local found=false
   for i,r in ipairs(df.global.world.raws.inorganics.all) do if r.id==material then event.inorganic_mat=i;found=true;break end end
   assert(found);event.tile_bitmask.bits[py%16]=1<<((px+dx)%16);b.block_events:insert('#',event)
  end
 end
 gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'D_DESIGNATE_DIG');gui.simulateInput(s,'DESIGNATE_DIG');gui.simulateInput(s,'DESIGNATE_RECTANGLE');df.global.game.main_interface.designation.show_advanced_options=true;gui.simulateInput(s,'DESIGNATE_MINE_MODE_AUTO');print('NATIVE_AUTO_MODE '..tostring(df.global.game.main_interface.designation.mine_mode))
 dfhack.gui.revealInDwarfmodeMap(px,py,z,true);click(px,py);click(px+1,py)
 local b=dfhack.maps.getTileBlock(px,py,z);print('NATIVE_AUTO '..material..' '..df.tile_dig_designation[b.designation[px%16][py%16].dig]..' auto='..tostring(b.occupancy[px%16][py%16].dig_auto))
end
gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'LEAVESCREEN');gui.simulateInput(s,'D_DESIGNATE_TRAFFIC')
local d=df.global.game.main_interface.designation;d.priority=7000;d.marker_only=false;d.mine_mode=df.mine_mode_type.MARK_GEMS_ONLY
_G.df3d_designation_acceptance=cases
_G.df3d_designation_acceptance_focus=table.concat(dfhack.gui.getFocusStrings(s),',')
local f=assert(io.open(out..'/cases.json','w'));f:write(json.encode(cases));f:close()
print('FIXTURE_READY '..#cases..' native priority=7000 marker=false gems-only traffic-menu')
