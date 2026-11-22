-- Native-only discovery in a protected, paused, owned session.
local out,view,info,callbacks,mode=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local trainer=mode=='trainer'
local prefix=trainer and 'pet-trainer' or 'pet-training'
local button
local function find(widget)
 if (widget.flag.whole&1)==0 then return end
 for _,target in ipairs(callbacks(widget.custom_activated,64))do if target==(trainer and 0x3d1700 or 0x3d15c0) then button=widget end end
 if df.widget_container:is_instance(widget)then
  for ordinal,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   if not df.widget_tabs:is_instance(widget) or ordinal-1==widget.cur_idx then find(child)end
  end
 end
end
find(info.creatures);assert(button,'Overall Training button missing')
local provider
local trainer_provider
if trainer and os.getenv('DF3D_PET_TRAINERS_PROVIDER')=='1' then
 local f=assert(io.open(out..'/pet-trainer-fixture.json'));local fixture=json.decode(f:read('*a'));f:close()
 local text,rc=dfhack.run_command_silent('df3d','pet-trainers-probe',tostring(fixture.id));assert(rc==0,text);trainer_provider=json.decode(text).rows
end
if not trainer and os.getenv('DF3D_PET_TRAINING_PROVIDER')=='1' then
 local text,rc=dfhack.run_command_silent('df3d','pet-training-probe');assert(rc==0,text);provider=json.decode(text).rows
end
local x=math.floor((button.rect.x1+button.rect.x2)/2);local y=math.floor((button.rect.y1+button.rect.y2)/2)
local g=df.global.gps;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
gui.simulateInput(view,'_MOUSE_L')
df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local source=debug.getinfo(1,'S').source:sub(2):gsub('smoke/pet%-training%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(source))(out..'/'..prefix..'-widgets.json','all')
local controls={};local knowledge={};local trainers={};local base=dfhack.internal.getImageBase()
local function collect(widget,path)
 if (widget.flag.whole&1)==0 then return end
 assert(#controls<4096,'Training tree exceeds bound')
 local _,address=df.sizeof(widget)
 local value={path=path,name=widget.name,vtable=df.reinterpret_cast('uint64_t',address).value-base,
  rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},
  activated=callbacks(widget.custom_activated,64),feed=callbacks(widget.custom_feed,64)}
 if df.widget_text:is_instance(widget)then value.text=dfhack.df2utf(widget.str);value.color={widget.fg,widget.bg,widget.bright}end
 if df.widget_unit_name:is_instance(widget) and widget.u then value.unit=widget.u.id end
 if trainer and df.widget_unit_name:is_instance(widget) and widget.u then
  local selectable=false
  for _,target in ipairs(callbacks(widget.parent.custom_activated,64))do if target==0x3d1850 then selectable=true end end
  if selectable then
   local row={id=widget.u.id,skills={}}
   local function text(child)
    if df.widget_text:is_instance(child)then row.skills[#row.skills+1]=dfhack.df2utf(child.str)end
    if df.widget_container:is_instance(child)then for _,nested in ipairs(dfhack.gui.getWidgetChildren(child))do text(nested)end end
   end
   text(widget.parent);trainers[#trainers+1]=row
  end
 end
 if df.widget_unit_list:is_instance(widget)then
  value.filters=callbacks(widget.filter_func,64);value.sorting={};value.ids={}
  for _,entry in ipairs(widget.sorting_by)do value.sorting[#value.sorting+1]=entry.ident end
  for _,entry in ipairs(widget.entry_list)do value.ids[#value.ids+1]={kind=entry.t,id=entry.t==0 and entry.u.id or entry.i.id}end
 end
 if not trainer and df.widget_creature_portrait:is_instance(widget)then
  local texts={}
  for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do if df.widget_text:is_instance(child)then texts[#texts+1]=child end end
  assert(#texts==2,'Training row text structure differs')
  knowledge[#knowledge+1]={race=widget.race,level=df.global.plotinfo.main.fortress_entity.training_knowledge.level[widget.race],
   name=dfhack.df2utf(texts[1].str),caption=dfhack.df2utf(texts[2].str),foreground=texts[2].fg,bright=texts[2].bright}
 end
 controls[#controls+1]=value
 if df.widget_container:is_instance(widget)then
  for ordinal,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   if not df.widget_tabs:is_instance(widget) or ordinal-1==widget.cur_idx then collect(child,path..'/'..(ordinal-1))end
  end
 end
end
collect(info.creatures,'creatures')
local f=assert(io.open(out..'/'..prefix..'-controls.json','w'));f:write(json.encode(controls));f:close()
if trainer_provider then
 local matches=json.encode(trainer_provider)==json.encode(trainers)
 f=assert(io.open(out..'/pet-trainers-reference.json','w'));f:write(json.encode({native=trainers,provider=trainer_provider,matches=matches}));f:close()
 assert(matches and #trainers>0,'Native trainer choices differ')
end
local matches=not provider or json.encode(provider)==json.encode(knowledge)
f=assert(io.open(out..'/'..prefix..'-reference.json','w'));f:write(json.encode({native=knowledge,provider=provider,matches=matches}));f:close()
assert(trainer or (#knowledge>0 and matches),'Overall Training provider differs')
f=assert(io.open(out..'/shot.tmp','w'));f:write(prefix..'-root');f:close()
assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+30000
while true do
 local ack=io.open(out..'/ack-'..prefix..'-root');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Training capture timeout');script.sleep(1,'frames')
end
