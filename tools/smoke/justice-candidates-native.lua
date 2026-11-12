-- Protected oracle only. Native map storage is never a runtime input.
local out,view,probe,settle,tab,capture,cold=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local info=df.global.game.main_interface.info
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function map(offset)
 local _,address=df.sizeof(info.justice);address=address+offset
 local head=df.reinterpret_cast('uint64_t',address+8).value
 local count=df.reinterpret_cast('uint64_t',address+16).value
 assert(count<=1048576,'Justice map too large')
 local node=df.reinterpret_cast('uint64_t',head).value;local values={}
 for _=1,count do
  assert(node~=head,'Justice map ended early')
  local unit=df.reinterpret_cast(df.unit,df.reinterpret_cast('uint64_t',node+16).value)
  values[tostring(unit.id)]=df.reinterpret_cast('int32_t',node+24).value
  node=df.reinterpret_cast('uint64_t',node).value
 end
 assert(node==head,'Justice map did not end');return values,count
end
local result={crime_id=9,panels={}}
for _,kind in ipairs{'Interrogate','Convict'}do
 if df.global.game.main_interface.help.open then click(711,430);assert(not df.global.game.main_interface.help.open,'Justice help did not close')end
 tab('Open cases');click(100,202);click(100,166)
 local ranks,count=map(0x360);local flags,flag_count=map(0x3a0)
 local supplied=probe('justice-candidate-facts-probe',9)
 assert(json.encode(supplied)==json.encode(cold),'Candidate facts depend on native menu history')
 assert(#supplied==count and count==flag_count,'Native candidate fact count differs')
 for _,row in ipairs(supplied)do
  assert(ranks[tostring(row.unit_id)]==row.rank and flags[tostring(row.unit_id)]==row.flags,'Native candidate facts differ for '..row.unit_id)
 end
 local after_ranks=map(0x360);local after_flags=map(0x3a0)
 assert(json.encode(ranks)==json.encode(after_ranks)and json.encode(flags)==json.encode(after_flags),'Owned facts changed native map backing')
 click(kind=='Interrogate' and 564 or 652,190)
 capture('justice-candidates-'..kind:lower())
 local lists={}
 local function walk(widget)
  if (widget.flag.whole&1)==0 then return end
  if df.widget_unit_list:is_instance(widget)then
   local ids={};for _,entry in ipairs(widget.entry_list)do if entry.t==0 and entry.u then ids[#ids+1]=entry.u.id end end
   local sorting={};local base=dfhack.internal.getImageBase()
   for _,entry in ipairs(widget.sorting_by)do
    local _,address=df.sizeof(entry.fn);local context=df.reinterpret_cast('uint64_t',address+56).value
    assert(context~=0,'Empty native sort callback')
    local vt=df.reinterpret_cast('uint64_t',context).value
    sorting[#sorting+1]={ident=entry.ident,callback_rva=df.reinterpret_cast('uint64_t',vt+16).value-base}
   end
   local displayed={}
   local function names(child)
    if df.widget_unit_name:is_instance(child)and child.u then displayed[#displayed+1]=child.u.id end
    if df.widget_container:is_instance(child)then for _,nested in ipairs(dfhack.gui.getWidgetChildren(child))do names(nested)end end
   end
   names(widget)
   -- Native stores one byte here; generated bitfield whole also reads padding.
   lists[#lists+1]={ids=ids,filter=widget.filter_str,sort_flags=widget.sort_flags.whole&0xff,sorting=sorting,displayed_ids=displayed,
    always_sort_count=#widget.always_sorting_by,partition_count=#widget.partitions,filter_count=#widget.filter_func}
  end
  if df.widget_container:is_instance(widget)then for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if not df.widget_tabs:is_instance(widget)or index-1==widget.cur_idx then walk(child)end end end
 end
 walk(info.justice)
 result.panels[#result.panels+1]={kind=kind,facts=supplied,lists=lists}
 local f=assert(io.open(out..'/justice-candidates.json','w'));f:write(json.encode(result));f:close()
 assert(#lists==1 and #lists[1].ids>0,'Justice candidate picker missing')
 if kind=='Convict' then
  local ordered=probe('justice-conviction-candidates-probe',9);local ids={}
  for _,row in ipairs(ordered)do ids[#ids+1]=row.unit_id end
  assert(json.encode(ids)==json.encode(lists[1].displayed_ids),'Owned conviction list differs from native displayed order')
  result.conviction_candidates=ordered
  local f=assert(io.open(out..'/justice-candidates.json','w'));f:write(json.encode(result));f:close()
 end
 gui.simulateInput(view,'LEAVESCREEN');settle()
 if not info.open then gui.simulateInput(view,'D_JUSTICE');settle()end
end
