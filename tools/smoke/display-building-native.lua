-- Protected native UI observation only. Runtime must use owned semantic inputs.
local out,view,building,capture,select_map=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local main=df.global.game.main_interface;local picker=main.assign_display_item
local function values(v)local result={};for _,value in ipairs(v)do result[#result+1]=value end;return result end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function probe()
 return dfhack.with_suspend(function()
  local guards={}
  for _,storage in ipairs{g,main}do
   local size,address=df.sizeof(storage);local copy=df.new('uint8_t',size)
   dfhack.internal.memmove(copy,address,size);guards[#guards+1]={size=size,address=address,copy=copy}
  end
  local text,code=dfhack.run_command_silent('df3d','display-inventory-probe',tostring(building.id))
  local unchanged=true
  for _,guard in ipairs(guards)do
   unchanged=unchanged and dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0;df.delete(guard.copy)
  end
  assert(code==0,text);assert(unchanged,'Display inventory changed native UI storage')
  return json.decode(text)
 end)
end
local cold_ids
if os.getenv('DF3D_DISPLAY_PROVIDER')=='1' then cold_ids=probe()end
local before={displayed=values(building.displayed_items),jobs=#building.jobs}
g.precise_mouse_x=520;g.precise_mouse_y=406;g.mouse_x=65;g.mouse_y=33
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
assert(picker.open and picker.display_bld==building,'Display assignment did not open')
capture('display-assignment-open');view:render(dfhack.getTickCount());capture('display-assignment-settled')
local result={id=building.id,before=before,types=values(picker.type_list),filtered_types=values(picker.filtered_type_list),
 current_type=picker.current_type,storeamount=values(picker.storeamount),badamount=values(picker.badamount),
 draft=values(picker.new_display_itid),master_ids={},current_ids={},height=picker.i_height,lines={}}
local context_size,context_address=df.sizeof(picker)
result.context_size=context_size;result.context_rva=context_address-dfhack.internal.getImageBase()
local function checkpoint()
 local file=assert(io.open(out..'/display-building-native.json','w'));file:write(json.encode(result));file:close()
end
for _,item in ipairs(picker.master_i_list.l_item)do result.master_ids[#result.master_ids+1]=item.id end
for _,item in ipairs(picker.current_type_i_list)do result.current_ids[#result.current_ids+1]=item.id end
if os.getenv('DF3D_DISPLAY_PROVIDER')=='1' then
 local before_scratch={};for _,item in ipairs(df.global.world.items.other.IN_PLAY)do before_scratch[#before_scratch+1]=item.base_uniform_score end
 result.owned_ids=probe()
 result.cold_ids=cold_ids
 assert(json.encode(cold_ids)==json.encode(result.owned_ids),'Display cold/open inventory differs')
 assert(json.encode(result.master_ids)==json.encode(result.owned_ids),'Owned display inventory/order differs')
 local after_scratch={};for _,item in ipairs(df.global.world.items.other.IN_PLAY)do after_scratch[#after_scratch+1]=item.base_uniform_score end
 assert(json.encode(before_scratch)==json.encode(after_scratch),'Owned display inventory changed item scratch')
end
for y=4,58 do local chars={}
 for x=0,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then result.lines[#result.lines+1]={y=y,text=text}end
end
if os.getenv('DF3D_DISPLAY_SELECT')=='1' then
 click(160,130);assert(picker.current_type==df.item_type.AMULET)
 capture('display-amulets')
 local candidate=assert(picker.current_type_i_list[0]);local candidate_id=candidate.id
 local function snapshot()
  local jobs={};for _,job in ipairs(building.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type]}end
  local refs={};for _,ref in ipairs(candidate.general_refs)do refs[#refs+1]={type=df.general_ref_type[ref:getType()],building=ref:getBuilding() and ref:getBuilding().id or -1}end
  return {displayed=values(building.displayed_items),draft=values(picker.new_display_itid),jobs=jobs,item_flags=tostring(candidate.flags.whole),item_flags2=tostring(candidate.flags2.whole),item_refs=refs}
 end
 result.selection={id=candidate_id,before=snapshot()}
 click(916,166);result.selection.selected=snapshot();capture('display-selected-draft')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not picker.open);result.selection.closed=snapshot();checkpoint()
 -- Escape closes the assignment screen and its parent sheet. Re-select the
 -- building through the ordinary map route before observing/removing the item.
 select_map(building);view:render(dfhack.getTickCount());capture('display-selected-parent')
 if #building.displayed_items>#before.displayed then
  click(880,142);result.selection.removed=snapshot();checkpoint();capture('display-removed-parent')
 end
 assert(#building.displayed_items==#before.displayed,'Display parent removal missed')
 click(520,406);assert(picker.open)
end
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
assert(not picker.open,'Display assignment did not close');capture('display-assignment-closed')
result.after={displayed=values(building.displayed_items),jobs=#building.jobs}
assert(json.encode(before)==json.encode(result.after),'Display open/close changed assignment')
result.success=true
local file=assert(io.open(out..'/display-building-native.json','w'));file:write(json.encode(result));file:close()
return result
