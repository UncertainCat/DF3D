-- Protected native UI oracle. Owned paused clone only; never save.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json');local g=df.global.gps
local ui=df.global.game.main_interface.civzone
local function pixel(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy)
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function mapclick(x,y,z)
 for sy=0,g.dimy-1 do for sx=0,g.dimx-1 do
  g.mouse_x=sx;g.mouse_y=sy;g.precise_mouse_x=sx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=sy*(g.screen_pixel_y//g.dimy)+6
  local p=dfhack.gui.getMousePos(true)
  if p and p.x==x and p.y==y and p.z==z then pixel(g.precise_mouse_x,g.precise_mouse_y);return end
 end end
 error('native Multi corner not visible')
end
local function capture(name)
 g.mouse_x=0;g.mouse_y=0
 for i=1,3 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while not io.open(out..'/ack-'..name,'r')do assert(dfhack.getTickCount()<limit,'capture timed out');script.sleep(1,'frames')end
end
local bed=assert(df.building.find(1310));assert(bed.centerx==172 and bed.centery==57 and bed.z==164)
df.global.game.main_interface.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
dfhack.gui.revealInDwarfmodeMap({x=172,y=57,z=164},true);view:render(dfhack.getTickCount())
pixel(55,320);pixel(310,166)
assert(ui.doing_multizone and ui.adding_new_type==df.civzone_type.Bedroom,'native Bedroom Multi not opened')
for _,case in ipairs{{'visible'},{'hidden-floor',172,58},{'hidden-boundary',169,56},{'hidden-seed',172,57},{'hidden-room'},{'wall-seed'},{'water7-seed'},{'magma-seed'}}do
 local saved={}
 local seed_block=dfhack.maps.getTileBlock({x=172,y=57,z=164})
 local seed_tile=seed_block.tiletype[12][9];local seed_designation=seed_block.designation[12][9].whole
 if case[1]=='wall-seed'then seed_block.tiletype[12][9]=dfhack.maps.getTileBlock({x=173,y=58,z=164}).tiletype[13][10]
 elseif case[1]=='water7-seed'then seed_block.designation[12][9].flow_size=7;seed_block.designation[12][9].liquid_type=df.tile_liquid.Water
 elseif case[1]=='magma-seed'then seed_block.designation[12][9].flow_size=1;seed_block.designation[12][9].liquid_type=df.tile_liquid.Magma end
 local function hide(x,y)
  local b=assert(dfhack.maps.getTileBlock({x=x,y=y,z=164}));local d=b.designation[x%16][y%16]
  saved[#saved+1]={d=d,hidden=d.hidden};d.hidden=true
 end
 if case[2]then hide(case[2],case[3])elseif case[1]=='hidden-room'then
  for y=56,60 do for x=169,173 do hide(x,y)end end
 end
 local ok,why=pcall(function()
  local text,code=dfhack.run_command_silent('df3d','room-read','172','57','164');assert(code==0,text)
  local before=json.decode(text)
  local before_tile=seed_block.tiletype[12][9];local before_designation=seed_block.designation[12][9].whole
  mapclick(172,57,164);mapclick(172,57,164)
  local result={name=case[1],before_tile=before_tile,after_tile=seed_block.tiletype[12][9],before_designation=before_designation,after_designation=seed_block.designation[12][9].whole,bridge_status=before.status,in_use=ui.furniture_rejected_in_use,unenclosed=ui.furniture_rejected_not_enclosed,rooms={}}
  for _,z in ipairs(ui.zone_just_created)do
   local room={x=z.x1,y=z.y1,z=z.z,width=z.x2-z.x1+1,height=z.y2-z.y1+1,extents={}}
   for y=z.y1,z.y2 do for x=z.x1,z.x2 do room.extents[#room.extents+1]=z.room.extents[(y-z.room.y)*z.room.width+x-z.room.x]end end
   result.rooms[#result.rooms+1]=room
  end
  records[#records+1]=result
  if case[1]=='hidden-floor' or case[1]=='hidden-seed'then capture(case[1])end
  for _,v in ipairs(saved)do assert(v.d.hidden,'native Multi revealed hidden terrain')end
  if #ui.zone_just_created>0 then pixel(310,118);assert(#ui.zone_just_created==0,'native Undo failed')end
 end)
 for _,v in ipairs(saved)do v.d.hidden=v.hidden end
 seed_block.tiletype[12][9]=seed_tile;seed_block.designation[12][9].whole=seed_designation
 assert(ok,why)
end
