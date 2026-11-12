-- Protected oracle only. Native widgets and rank maps are never runtime inputs.
local out,view,probe,settle,tab,capture=...
local gui=require('gui');local json=require('json')
local entity=assert(df.global.plotinfo.main.fortress_entity)
local execution=entity.assignments_by_type.EXECUTIONS
local enforcement=entity.assignments_by_type.LAW_ENFORCEMENT
local function copy(v)local r={};for _,p in ipairs(v)do r[#r+1]=p end;return r end
local saved_execution,saved_enforcement=copy(execution),copy(enforcement)
local leader=assert(saved_enforcement[1]);local saved_squad=leader.squad_id
local function restore()
 leader.squad_id=saved_squad
 execution:resize(0);enforcement:resize(0)
 for _,p in ipairs(saved_execution)do execution:insert('#',p)end
 for _,p in ipairs(saved_enforcement)do enforcement:insert('#',p)end
end
local function observe(name)
 local supplied=probe('justice-guard-probe')
 gui.simulateInput(view,'D_JUSTICE');settle()
 if df.global.game.main_interface.help.open then
  local g=df.global.gps;g.mouse_x=88;g.mouse_y=35;g.precise_mouse_x=711;g.precise_mouse_y=430
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
 end
 tab('Fortress guard')
 local ids,caption={},nil
 local function walk(w)
  if (w.flag.whole&1)==0 then return end
  if df.widget_unit_name:is_instance(w)and w.u then ids[#ids+1]=w.u.id end
  if df.widget_text:is_instance(w)and w.str:find('Desired metal cages',1,true)then
   caption=dfhack.df2utf(w.str)
  end
  if df.widget_container:is_instance(w)then for i,c in ipairs(dfhack.gui.getWidgetChildren(w))do
   if not df.widget_tabs:is_instance(w)or i-1==w.cur_idx then walk(c)end
  end end
 end
 local menu=df.global.game.main_interface.info.justice;walk(menu)
 assert(caption==supplied.caption,'Guard capacity caption differs')
 -- widget text palette field names are captured separately by the shared oracle.
 local expected={};for _,row in ipairs(supplied.members)do expected[#expected+1]=row.unit_id end
 table.sort(ids);table.sort(expected);assert(json.encode(ids)==json.encode(expected),'Guard membership differs: '..name)
 local _,address=df.sizeof(menu);local map=address+0x3e0
 local head=df.reinterpret_cast('uint64_t',map+8).value
 local count=df.reinterpret_cast('uint64_t',map+16).value;assert(count<=1048576)
 local node=df.reinterpret_cast('uint64_t',head).value;local ranks={}
 for _=1,count do
  assert(node~=head);local unit=df.reinterpret_cast(df.unit,df.reinterpret_cast('uint64_t',node+16).value)
  ranks[tostring(unit.id)]=df.reinterpret_cast('int32_t',node+24).value
  node=df.reinterpret_cast('uint64_t',node).value
 end
 assert(node==head)
 for _,row in ipairs(supplied.members)do assert(ranks[tostring(row.unit_id)]==row.rank,'Guard judiciary rank differs: '..json.encode{provider=supplied,native_ranks=ranks})end
 return {name=name,provider=supplied,native_ids=ids,native_caption=caption,ranks=ranks}
end
local samples={}
local ok,err=xpcall(function()
 gui.simulateInput(view,'LEAVESCREEN');settle()
 samples[#samples+1]=observe('baseline');capture('justice-guard-provider')
 gui.simulateInput(view,'LEAVESCREEN');settle();leader.squad_id=-1
 samples[#samples+1]=observe('individual-enforcer')
 gui.simulateInput(view,'LEAVESCREEN');settle();restore();execution:insert('#',leader)
 samples[#samples+1]=observe('execution-precedence')
 gui.simulateInput(view,'LEAVESCREEN');settle();restore()
 gui.simulateInput(view,'D_JUSTICE');settle()
 gui.simulateInput(view,'LEAVESCREEN');settle();execution:resize(0)
 samples[#samples+1]=observe('without-executions')
 gui.simulateInput(view,'LEAVESCREEN');settle();restore();enforcement:resize(0)
 samples[#samples+1]=observe('without-enforcement')
 gui.simulateInput(view,'LEAVESCREEN');settle();execution:resize(0)
 samples[#samples+1]=observe('no-guard-assignments')
end,debug.traceback)
restore()
local f=assert(io.open(out..'/justice-guard.json','w'));f:write(json.encode{samples=samples,restored=true});f:close()
assert(ok,err)
