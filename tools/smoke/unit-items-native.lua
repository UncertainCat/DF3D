-- Native Items navigation in an owned paused clone. No item actions are applied.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local main=df.global.game.main_interface;local sheet=main.view_sheets
local frame=df.global.world.frame_counter
local original_tab=sheet.active_sub_tab
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function click(x,y)
 pointer(x,y);df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function inventory()
 local rows={}
 for _,entry in ipairs(unit.inventory)do
  rows[#rows+1]={id=entry.item.id,mode=entry.mode,body_part_id=entry.body_part_id,flags=entry.item.flags.whole}
 end
 return rows
end
local before=inventory()
local result={unit_id=unit.id,inventory=before,original_tab=original_tab,rows={},hovers={}}
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected unit Overview')
 click(548,196);pointer(400,400)
 assert(sheet.open and sheet.active_id==unit.id and sheet.active_sub_tab~=original_tab,'Items tab did not open')
 result.items_tab=sheet.active_sub_tab;capture('unit-items-open')
 for y=0,g.dimy-1 do
  local chars={}
  for x=0,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);chars[#chars+1]=pen.ch>=32 and string.char(pen.ch%256) or ' ' end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
  if text~=''then result.rows[#result.rows+1]={y=y,text=text}end
 end
 if os.getenv('DF3D_UNIT_ITEMS_READER')=='1'then
  local function read()
  local guards={}
  local function guard(address,size)
   if size==0 then return end
   local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
   guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  for _,object in ipairs{unit,sheet,df.global.plotinfo}do local size,address=df.sizeof(object);guard(address,size)end
  for _,object in ipairs(unit.body.spatters)do local size,address=df.sizeof(object);guard(address,size)end
  for _,vector in ipairs{unit.body.components.body_part_status,unit.enemy.motor_nervenet,
    unit.enemy.sensory_nervenet,unit.enemy.body_part_useable}do
   local _,address=df.sizeof(vector)
   local first=df.reinterpret_cast('uint64_t',address).value
   local last=df.reinterpret_cast('uint64_t',address+8).value
   assert(last>=first and last-first<1048576);guard(first,last-first)
  end
  local base=dfhack.internal.getImageBase()
  for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
  local output,status=dfhack.run_command_silent('df3d','unit-items-description-probe',tostring(unit.id))
  local unchanged=true
  for _,v in ipairs(guards)do
   if dfhack.internal.memcmp(v.bytes,v.address,v.size)~=0 then unchanged=false end
   df.delete(v.bytes)
  end
  assert(status==0,output);local reader=json.decode(output);reader.guards_unchanged=unchanged
  assert(unchanged,'Items reader changed creature caches, random state or native UI')
  return reader
  end
  result.reader=read()
  assert(#result.reader.rows==#before,'Inventory reader row count')
  local native={};for _,row in ipairs(result.rows)do native[row.y]=row.text:match('^%s*(.-)%s*$')end
  for i,row in ipairs(result.reader.rows)do
   assert(row.id==before[i].id,'Inventory reader order')
   assert(row.caption==native[18+(i-1)*3],'Inventory caption differs at '..i)
   assert(row.role==native[19+(i-1)*3],'Inventory role differs at '..i)
  end
  for i,row in ipairs(result.reader.spatters)do
   assert(row.caption==native[18+(#before+i-1)*3],'Spatter caption differs')
   assert(row.body_part_caption==native[19+(#before+i-1)*3],'Spatter body part differs')
  end
  if os.getenv('DF3D_UNIT_ITEMS_SPATTERS')=='1'then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-items%-native.lua$','unit-items-spatters-native.lua')
   result.spatter_cases=assert(loadfile(source))(unit,pointer,read)
  end
  if os.getenv('DF3D_UNIT_ITEMS_CONTENTS')=='1'then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-items%-native.lua$','unit-items-contents-native.lua')
   result.contents_cases=assert(loadfile(source))(unit,pointer,read)
  end
  if os.getenv('DF3D_UNIT_ITEMS_ROLES')=='1'then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-items%-native.lua$','unit-items-roles-native.lua')
   result.role_cases=assert(loadfile(source))(unit,view,pointer,read)
  end
 end
 local seen={}
 for y=208,460,12 do for x=424,888,8 do
  pointer(x,y);local hover=main.current_hover
  if hover>=0 and not seen[hover]then seen[hover]=true;result.hovers[#result.hovers+1]={id=hover,name=df.main_hover_instruction[hover],x=x,y=y}end
 end end
 assert(json.encode(inventory())==json.encode(before),'Items navigation changed inventory')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Items navigation advanced simulation')
end,debug.traceback)
click(464,196);pointer(400,400)
result.restored=sheet.open and sheet.active_id==unit.id and sheet.active_sub_tab==original_tab
result.success=ok and result.restored;result.error=not ok and err or nil
local file=assert(io.open(out..'/unit-items-native.json','w'));file:write(json.encode(result));file:close()
assert(result.success,err or 'Items did not restore Overview')
return result
