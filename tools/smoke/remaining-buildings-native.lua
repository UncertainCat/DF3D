-- Native inventory/captures for completed building types still outside public routes.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local kinds={6,7,16,17,18,19,20,21,22,24,25,26,27,28,31,32,45,47,48,49,53}
local wanted={};for _,kind in ipairs(kinds)do wanted[kind]=true end
local result={frame=df.global.world.frame_counter,inventory={},buildings={},missing={}}
local selected={}
for _,b in ipairs(df.global.world.buildings.all)do
 local kind=b:getType()
 if wanted[kind]then
  local d=dfhack.maps.getTileFlags(b.centerx,b.centery,b.z)
  local complete=b:getBuildStage()==b:getMaxBuildStage()
  result.inventory[#result.inventory+1]={id=b.id,type=kind,subtype=b:getSubtype(),complete=complete,revealed=d and not d.hidden or false}
  if complete and d and not d.hidden and not selected[kind]then selected[kind]=b end
 end
end
for _,kind in ipairs(kinds)do
 local b=selected[kind]
 if b then
  if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
  view:render(dfhack.getTickCount());select_map(b)
  local row={id=b.id,type=kind,subtype=b:getSubtype(),tile={b.centerx,b.centery,b.z},native_type=df.building_type[kind],selected_sheet=sheet.active_sheet,selected_id=sheet.active_id,lines={}}
  capture('remaining-building-'..kind)
  for y=4,g.dimy-1 do
   local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
  end
  if kind==18 and os.getenv('DF3D_WELL_PROVIDER')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','well-status-native.lua')
   result.well_status=assert(loadfile(source))(out,view,b,capture)
  end
  result.buildings[#result.buildings+1]=row
 else result.missing[#result.missing+1]=kind end
end
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
assert(df.global.world.frame_counter==result.frame)
result.success=true
local f=assert(io.open(out..'/remaining-buildings-native.json','w'));f:write(json.encode(result));f:close()
return result
