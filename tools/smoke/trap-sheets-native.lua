-- Native screen discovery and optional restored edits in a paused owned clone.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={buildings={},frame=df.global.world.frame_counter}
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function persist()
 local f=assert(io.open(out..'/trap-sheets-native.json','w'));f:write(json.encode(result));f:close()
end
for subtype=2,5 do
 local b
 for _,candidate in ipairs(df.global.world.buildings.other.TRAP)do
  local d=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
  if candidate.trap_type==subtype and candidate:getBuildStage()==candidate:getMaxBuildStage() and d and not d.hidden and #candidate.jobs==0 then b=candidate;break end
 end
 local prior
 if not b then
  b=assert(df.building.find(61));assert(df.building_trapst:is_instance(b) and #b.jobs==0)
  prior=b.trap_type;b.trap_type=subtype
 end
 local row={id=b.id,subtype=subtype,fixture=prior~=nil and 'Paused existing trap61 with temporary subtype; not native construction defaults.' or 'Existing completed revealed trap.',name=dfhack.df2utf(b.name),tile={b.centerx,b.centery,b.z},state=b.state,ready_timeout=b.ready_timeout,fill_timer=b.fill_timer,stop_flags=b.stop_flags.whole,track={friction=b.track_stop_info.friction,flags=b.track_stop_info.track_flags.whole,dump_x=b.track_stop_info.dump_x_shift,dump_y=b.track_stop_info.dump_y_shift},items={},lines={}}
 result.buildings[#result.buildings+1]=row
 local ok,err=xpcall(function()
  if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
  view:render(dfhack.getTickCount());select_map(b)
  assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==b.id)
  for _,held in ipairs(b.contained_items)do row.items[#row.items+1]={id=held.item.id,type=held.item:getType(),use_mode=held.use_mode}end
  for y=4,g.dimy-1 do
   local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
  end
  persist();capture('trap-sheet-'..subtype)
  if os.getenv('DF3D_TRAP_STATES_NATIVE')=='1'then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('trap%-sheets%-native.lua$','trap-states-native.lua')
   row.states=assert(loadfile(source))(out,view,b,capture)
  end
  if os.getenv('DF3D_TRAP_SHEETS_RUNTIME')=='1'then
   local function shot(label)view:render(dfhack.getTickCount());capture('trap-sheet-'..subtype..'-'..label)end
   local name=b.name;local item=assert(b.contained_items[0].item);row.original_forbid=item.flags.forbid
   click(800,82);gui.simulateInput(view,'STRING_A120');gui.simulateInput(view,'SELECT');assert(b.name==name..'x');shot('renamed')
   click(800,82);gui.simulateInput(view,'STRING_A000');gui.simulateInput(view,'SELECT');assert(b.name==name);shot('restored')
   click(796,562);assert(item.flags.forbid~=row.original_forbid);shot('forbid')
   click(796,562);assert(item.flags.forbid==row.original_forbid)
   click(540,520);shot('links');click(720,520)
   click(832,82);assert(#b.jobs==1 and b.jobs[0].job_type==df.job_type.DestroyBuilding);shot('removing')
   -- Native cancel removal appears at the shared header's first action row.
   click(520,202);assert(#b.jobs==0);shot('removal-cancelled')
   local f=assert(io.open(out..'/trap-sheet-expected.json','w'));f:write(json.encode(row));f:close()
   local label='trap-sheet-wire-'..subtype;capture(label)
   f=assert(io.open(out..'/'..label..'-result.json'));row.viewer=json.decode(f:read('*a'));f:close()
   assert(row.viewer.success and b.name==name and item.flags.forbid==row.original_forbid and #b.jobs==0,'Trap viewer did not restore native state')
  end
  assert(#b.jobs==0 and df.global.world.frame_counter==result.frame)
 end,debug.traceback)
 if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
 if prior~=nil then b.trap_type=prior end
 assert(ok,err)
end
result.success=true;persist();return result
