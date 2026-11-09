-- Protected native input observation only; never a runtime widget provider.
local out,view,list,headers,shot=...
local gui=require('gui');local script=require('gui.script')
local base=dfhack.internal.getImageBase();local g=df.global.gps
local observations={}
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function observe(label)
 local sorts,directions,ids={},{},{}
 for _,entry in ipairs(list.sorting_by)do sorts[#sorts+1]=entry.ident end
 local _,address=df.sizeof(list);local head=df.reinterpret_cast('uint64_t',address+0x1c8).value
 local node=df.reinterpret_cast('uint64_t',head).value;local count=0
 while node~=head do
  count=count+1;assert(count<=4,'Direction map exceeded four columns')
  local length=df.reinterpret_cast('uint64_t',node+0x20).value;assert(length<=15)
  local chars={};for i=0,length-1 do chars[#chars+1]=string.char(df.reinterpret_cast('uint8_t',node+0x10+i).value)end
  directions[table.concat(chars)]=df.reinterpret_cast('uint8_t',node+0x30).value
  node=df.reinterpret_cast('uint64_t',node).value
 end
 local function collect(widget)
  if (widget.flag.whole&1)==0 then return end
  if df.widget_unit_portrait:is_instance(widget) and widget.u then ids[#ids+1]=widget.u.id end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child)end end
 end
 collect(list)
 if os.getenv('DF3D_WORK_DETAILS_MULTISORT_PROVIDER')=='1' then
  local columns={Cat=0,Name=1,Prof=2,Skills=3};local args={'df3d','work-detail-multisort-probe','0',''}
  for _,name in ipairs(sorts)do args[#args+1]=tostring(columns[name]);args[#args+1]=tostring(directions[name])end
  local text,code=dfhack.run_command_silent(table.unpack(args));assert(code==0,'Owned multisort provider rejected: '..label)
  local actual=require('json').decode(text).ids;assert(require('json').encode(actual)==require('json').encode(ids),'Owned multisort order differs: '..label)
 end
 observations[#observations+1]={label=label,sorts=sorts,directions=directions,ids=ids,modifier=df.reinterpret_cast('uint8_t',base+0x238d0b8).value}
 if #sorts==5 then shot('work-details-five-priorities')end
end
local function click(name,modifier)
 local widget=assert(headers[name]);local x,y=widget.rect.x1+1,widget.rect.y1
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 local flags=df.reinterpret_cast('uint8_t',base+0x238d0b8);local previous=flags.value
 if modifier~=nil then flags.value=modifier end
 local ok,err=pcall(gui.simulateInput,view,'_MOUSE_L');flags.value=previous
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(ok,err);settle()
end
observe('initial')
for _,step in ipairs{{'Name',0},{'Cat',1},{'Prof',1},{'Name',1},{'Name',1},{'Name',2},{'Cat',2},{'Prof',2},{'Skills',0},{'Skills',1},{'Skills',2}}do
 click(step[1],step[2]);observe('controlled-'..step[2]..'-'..step[1])
end
local function modifier(action)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('kitchen-'..action);f:close();assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+5000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Modifier timeout');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));settle()
end
click('Skills',0)
for _,mode in ipairs{'shift','control'}do
 modifier(mode..'-down');click('Name');observe('window-'..mode..'-Name');modifier(mode..'-up')
end
return observations
