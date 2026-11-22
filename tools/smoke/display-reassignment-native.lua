-- Disposable second pedestal; assignment effects come from native UI and public DF3D.
local out,view,first,capture,select_map=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local picker=df.global.game.main_interface.assign_display_item
local second,pedestal
local result={}
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(json.encode(value));f:close()end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function open(b)
 if df.global.game.main_interface.view_sheets.open then gui.simulateInput(view,'LEAVESCREEN')end
 select_map(b);view:render(dfhack.getTickCount())
end
local function entry(b)return {id=b.id,tile={b.centerx,b.centery,b.z},custom_name=dfhack.df2utf(b.name)}end
local function refs(item)
 local ids={};for _,ref in ipairs(item.general_refs)do if ref:getType()==df.general_ref_type.BUILDING_DISPLAY_FURNITURE then ids[#ids+1]=ref:getBuilding().id end end;return ids
end
local function assign(b,id)
 open(b);click(520,406);assert(picker.open and picker.display_bld==b)
 click(160,130);assert(picker.current_type==df.item_type.AMULET)
 local item=assert(picker.current_type_i_list[0]);assert(not id or item.id==id,'Reassignment candidate changed or became unavailable')
 click(916,166);assert(#picker.new_display_itid==1 and picker.new_display_itid[0]==item.id)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not picker.open)
 return item
end
local ok,err=xpcall(function()
 assert(#first.displayed_items==0 and #first.jobs==0 and df.global.pause_state)
 for y=80,140,4 do for x=80,160,4 do
  local pos={x=x,y=y,z=first.z};local d,o=dfhack.maps.getTileFlags(pos)
  if d and not d.hidden and o and not o.item and not o.unit and not o.unit_grounded and not dfhack.buildings.findAtTile(pos) then
   local success,b=pcall(dfhack.buildings.constructBuilding,{type=df.building_type.DisplayFurniture,pos=pos,full_rectangle=true})
   if success and b then second=b;break end
  end
 end;if second then break end end
 assert(second,'No second pedestal fixture site')
 while #second.jobs>0 do assert(dfhack.job.removeJob(second.jobs[0]))end
 second:setBuildStage(second:getMaxBuildStage());second.flags.exists=true;second:updateOccupancy(second.centerx,second.centery)
 second.mat_type=first.mat_type;second.mat_index=first.mat_index
 local subtype=-1;for i,raw in ipairs(df.global.world.raws.itemdefs.tools)do if raw.id=='ITEM_TOOL_PEDESTAL'then subtype=i;break end end;assert(subtype>=0)
 local worker;for _,u in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(u)then worker=u;break end end
 local items=dfhack.items.createItem(assert(worker),df.item_type.TOOL,subtype,second.mat_type,second.mat_index);assert(#items==1);pedestal=items[1]
 assert(dfhack.items.moveToBuilding(pedestal,second,2,true))
 local item=assign(first);local id=item.id
 assert(#first.displayed_items==1 and first.displayed_items[0]==id and json.encode(refs(item))==json.encode{first.id})
 open(first);capture('display-reassign-first-assigned')
 assign(second,id)
 result.native={item_id=id,from=entry(first),to=entry(second),references=refs(item)}
 assert(#first.displayed_items==0 and #second.displayed_items==1 and second.displayed_items[0]==id and json.encode(refs(item))==json.encode{second.id},'Native reassignment did not move membership/reference')
 open(first);capture('display-reassign-first-empty')
 open(second);capture('display-reassign-second-assigned');click(880,142)
 assert(#second.displayed_items==0 and #refs(item)==0 and not item.flags2.location_reserved)
 capture('display-reassign-second-removed')
 write('display-wire-expected.json',{reassignment=true,from=entry(first),to=entry(second),item_id=id})
 capture('display-wire')
 local f=assert(io.open(out..'/display-wire-result.json'));result.viewer=json.decode(f:read('*a'));f:close()
 assert(result.viewer.success and #first.displayed_items==0 and #second.displayed_items==0 and #refs(item)==0 and not item.flags2.location_reserved,'Public reassignment did not restore memberships/reference')
 assert(#first.jobs==0 and #second.jobs==0)
 result.success=true
end,debug.traceback)
if picker.open then gui.simulateInput(view,'LEAVESCREEN')end
if df.global.game.main_interface.view_sheets.open then gui.simulateInput(view,'LEAVESCREEN')end
if pedestal then pedestal.flags.in_building=false;assert(dfhack.items.remove(pedestal))end
if second then second:setBuildStage(0);second.flags.exists=false;assert(dfhack.buildings.deconstruct(second))end
result.error=ok and nil or err;write('display-reassignment-native.json',result);assert(ok,err)
return result
