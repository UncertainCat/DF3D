-- Protected real hauling after public assignment. No worker/item/job fabrication.
local out,view,b,capture,select_map=...
local gui=require('gui');local script=require('gui.script');local json=require('json');local utils=require('utils')
local result={start_tick=df.global.world.frame_counter,building_id=b.id,samples={}}
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(json.encode(value));f:close()end
local function save()write('display-hauling-native.json',result)end
local function body()
 local text,rc=dfhack.run_command_silent('df3d','display-picker-probe',tostring(b.id),'37','');assert(rc==0,text);return json.decode(text)
end
local function holder(item)
 for _,ref in ipairs(item.general_refs)do if ref:getType()==df.general_ref_type.BUILDING_HOLDER and ref:getBuilding()==b then return true end end
 return false
end
local function expected(stage,id)return {haul_stage=stage,item_id=id,target={id=b.id,tile={b.centerx,b.centery,b.z},custom_name=dfhack.df2utf(b.name)}}end
local ok,err=xpcall(function()
 assert(df.global.pause_state and #b.displayed_items==0 and #b.jobs==0)
 local id=assert(body().items[1]);local item=assert(df.item.find(id));result.item_id=id
 write('display-wire-expected.json',expected('assign',id));capture('display-wire')
 local f=assert(io.open(out..'/display-wire-result.json'));local assigned=json.decode(f:read('*a'));f:close()
 assert(assigned.success and #b.displayed_items==1 and b.displayed_items[0]==id and not holder(item),'Public assignment did not enter Assigned state')
 if df.global.game.main_interface.view_sheets.open then gui.simulateInput(view,'LEAVESCREEN')end
 local deadline=dfhack.getTickCount()+180000;local next_sample=0;local workers={}
 df.global.pause_state=false
 while not holder(item) and df.global.world.frame_counter-result.start_tick<12000 and dfhack.getTickCount()<deadline do
  script.sleep(1,'frames')
  local tick=df.global.world.frame_counter-result.start_tick
  local jobs={}
  for _,job in utils.listpairs(df.global.world.jobs.list)do if job.job_type==df.job_type.PutItemOnDisplay then
   local target=false;local worker=-1
   for _,ref in ipairs(job.items)do if ref.item and ref.item.id==id then target=true end end
   for _,ref in ipairs(job.general_refs)do
    if ref:getType()==df.general_ref_type.BUILDING_HOLDER and ref:getBuilding()==b then target=true end
    if ref:getType()==df.general_ref_type.UNIT_WORKER then worker=ref:getUnit().id end
   end
   if target then jobs[#jobs+1]={id=job.id,worker=worker};if worker>=0 then workers[tostring(worker)]=true end end
  end end
  if tick>=next_sample then result.samples[#result.samples+1]={tick=tick,jobs=jobs,item_pos={item.pos.x,item.pos.y,item.pos.z}};next_sample=tick+100;save()end
  if df.global.pause_state then result.native_paused=true;break end
 end
 df.global.pause_state=true;result.end_tick=df.global.world.frame_counter;result.workers=workers;result.delivered=holder(item);save()
 assert(result.delivered and next(workers),'Display item was not delivered by a native worker within the bounded interval')
 local observed=body();assert(#observed.body==1 and observed.body[1].on_display and observed.body[1].status=='On display' and observed.body[1].color==10)
 result.native_body=observed.body
 select_map(b);view:render(dfhack.getTickCount())
 local sheet=df.global.game.main_interface.view_sheets
 result.initial_selection={kind=df.view_sheet_type[sheet.active_sheet],id=sheet.active_id}
 if sheet.active_sheet~=df.view_sheet_type.BUILDING or sheet.active_id~=b.id then
  local index;for i,kind in ipairs(sheet.tab)do if kind==df.view_sheet_type.BUILDING and sheet.tab_id[i]==b.id then index=i;break end end
  assert(index,'Native selection omitted display alternative')
  local g=df.global.gps;g.precise_mouse_x=920;g.precise_mouse_y=70+36*index;g.mouse_x=115;g.mouse_y=(g.precise_mouse_y-4)//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 end
 assert(sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==b.id)
 capture('display-haul-on-display')
 write('display-wire-expected.json',expected('delivered',id));capture('display-haul-wire')
 f=assert(io.open(out..'/display-haul-wire-result.json'));result.viewer=json.decode(f:read('*a'));f:close()
 assert(result.viewer.success and #b.displayed_items==0 and not item.flags2.location_reserved,'Public delivered-item removal failed')
 result.success=true
end,debug.traceback)
df.global.pause_state=true;result.end_tick=df.global.world.frame_counter;result.error=ok and nil or err;save();assert(ok,err)
return result
