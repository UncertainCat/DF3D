-- Protected oracle only: selected-list grouping and nested callback identity.
local out,view,probe,settle,click,capture=...
local json=require('json');local base=dfhack.internal.getImageBase()
local function current()
 local list
 local function walk(w)
  if (w.flag.whole&1)==0 then return end
  if df.widget_unit_list:is_instance(w)then assert(not list);list=w end
  if df.widget_container:is_instance(w)then for index,child in ipairs(dfhack.gui.getWidgetChildren(w))do
   if not df.widget_tabs:is_instance(w)or index-1==w.cur_idx then walk(child)end
  end end
 end
 walk(df.global.game.main_interface.info.justice);assert(list)
 local ids={}
 local function names(w)
  if df.widget_unit_name:is_instance(w)and w.u then ids[#ids+1]=w.u.id end
  if df.widget_container:is_instance(w)then for _,child in ipairs(dfhack.gui.getWidgetChildren(w))do names(child)end end
 end
 names(list)
 local _,address=df.sizeof(list)
 local context=df.reinterpret_cast('uint64_t',address+0x3b0).value;assert(context~=0)
 local vt=df.reinterpret_cast('uint64_t',context).value
 return ids,df.reinterpret_cast('uint64_t',vt+16).value-base
end
local function owned(spec)
 local ids={};for _,row in ipairs(probe('justice-interrogation-candidates-probe',{'9','',spec}))do ids[#ids+1]=row.unit_id end
 return ids
end
local before,callback=current();assert(#before>=7)
assert(json.encode(before)==json.encode(owned('3:0,1:0')),'Initial Interrogate order differs')
local target=before[7]
click(808,172+6*36+18)
local selected=current()
local facts=probe('justice-candidate-facts-probe',9);local found=false
for _,row in ipairs(facts)do if row.unit_id==target then found=(row.flags&1)~=0 end end
assert(found,'Native checkbox did not select the seventh row')
assert(json.encode(selected)==json.encode(before),'Checkbox unexpectedly reordered native rows')
local f=assert(io.open(out..'/justice-interrogate-list.json','w'))
f:write(json.encode({target=target,selected_callback_rva=callback,before=before,selected=selected}));f:close()
capture('justice-interrogate-grouped')
local gui=require('gui')
gui.simulateInput(view,'STANDARDSCROLL_DOWN');settle();capture('justice-interrogate-selected-away')
gui.simulateInput(view,'STANDARDSCROLL_UP');settle()
-- Record checkbox-time ordering before requesting a header re-sort.
click(592,154)
local sorted=current()
f=assert(io.open(out..'/justice-interrogate-list.json','w'))
f:write(json.encode({target=target,selected_callback_rva=callback,before=before,selected=selected,sorted=sorted}));f:close()
assert(sorted[1]==target,'Scheduled row was not grouped first after sorting')
assert(json.encode(sorted)==json.encode(owned('1:1')),'Owned selected grouping differs from native')
click(808,190)
local facts_off=probe('justice-candidate-facts-probe',9)
for _,row in ipairs(facts_off)do if row.unit_id==target then assert((row.flags&1)==0,'Cancel failed')end end
