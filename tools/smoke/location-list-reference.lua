-- Protected native presentation capture only. No runtime native-screen dependency.
local out=...
local json=require('json')
local function write(name,v)local f=assert(io.open(out..'/'..name,'w'));f:write(json.encode(v));f:close()end
local function key(k)require('gui').simulateInput(dfhack.gui.getDFViewscreen(true),k)end
local function pixel(x,y)local g=df.global.gps;g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12;key('_MOUSE_L')end
assert(df.global.pause_state,'paused clone required')
local frame=df.global.world.frame_counter
local b=assert(df.building.find(23))
assert(b.location_id<0,'capture bedroom already assigned')
df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
dfhack.gui.revealInDwarfmodeMap({x=b.centerx,y=b.centery,z=b.z},true)
local found=false
for y=0,65 do for x=0,149 do
 local g=df.global.gps;g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
 local p=dfhack.gui.getMousePos(true)
 if p and p.x==b.centerx and p.y==b.centery and p.z==b.z then key('_MOUSE_L');found=true;break end
end if found then break end end
assert(found and df.global.game.main_interface.civzone.cur_bld==b,'native bedroom selection failed')
pixel(336,190)
local selector=df.global.game.main_interface.location_selector
assert(selector.open and not selector.choosing_temple_religious_practice,'location list did not open')
local g=df.global.gps;g.mouse_x=130;g.mouse_y=50;g.precise_mouse_x=1044;g.precise_mouse_y=606
local function render()dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())end
local function line(y)
 local s='';for x=54,80 do local t=dfhack.screen.readTile(x,y);local ch=t and t.ch or 32;s=s..(ch>=32 and ch<=255 and string.char(ch)or' ')end
 return dfhack.df2utf(s):gsub('%s+$','')
end
local function observe(index)
 selector.scroll_position_location=math.min(index,math.max(0,#selector.valid_ab-6))
 render()
 local y=19+3*(index-selector.scroll_position_location)
 return {title=line(y),subtitle=line(y+1)}
end
local baseline={};local guild,guild_index
for i,v in ipairs(selector.valid_ab)do
 local row=observe(i);row.id=v.id;row.type=df.abstract_building_type[v:getType()];row.name=dfhack.df2utf(dfhack.translation.translateName(v.name,true))
 row.tier=v.contents.location_tier;row.profession=v.contents.profession;row.value=v.contents.location_value
 baseline[#baseline+1]=row
 if row.type=='GUILDHALL' then guild=v;guild_index=i end
end
write('native-location-list.json',baseline)
key('LEAVESCREEN');key('LEAVESCREEN')
assert(b.location_id<0 and df.global.pause_state and df.global.world.frame_counter==frame,'capture changed assignment or simulation')
print('LOCATION_LIST_REFERENCE_PASS '..#baseline)
