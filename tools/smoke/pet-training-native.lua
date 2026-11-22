-- Native-only discovery in a protected, paused, owned session.
local out,view,info,callbacks=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local button
local function find(widget)
 if (widget.flag.whole&1)==0 then return end
 for _,target in ipairs(callbacks(widget.custom_activated,64))do if target==0x3d15c0 then button=widget end end
 if df.widget_container:is_instance(widget)then
  for ordinal,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   if not df.widget_tabs:is_instance(widget) or ordinal-1==widget.cur_idx then find(child)end
  end
 end
end
find(info.creatures);assert(button,'Overall Training button missing')
local provider
if os.getenv('DF3D_PET_TRAINING_PROVIDER')=='1' then
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
assert(loadfile(source))(out..'/pet-training-widgets.json','all')
local controls={};local knowledge={};local base=dfhack.internal.getImageBase()
local function collect(widget,path)
 if (widget.flag.whole&1)==0 then return end
 assert(#controls<4096,'Training tree exceeds bound')
 local _,address=df.sizeof(widget)
 local value={path=path,name=widget.name,vtable=df.reinterpret_cast('uint64_t',address).value-base,
  rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},
  activated=callbacks(widget.custom_activated,64),feed=callbacks(widget.custom_feed,64)}
 if df.widget_text:is_instance(widget)then value.text=dfhack.df2utf(widget.str);value.color={widget.fg,widget.bg,widget.bright}end
 if df.widget_creature_portrait:is_instance(widget)then
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
local f=assert(io.open(out..'/pet-training-controls.json','w'));f:write(json.encode(controls));f:close()
local matches=not provider or json.encode(provider)==json.encode(knowledge)
f=assert(io.open(out..'/pet-training-reference.json','w'));f:write(json.encode({native=knowledge,provider=provider,matches=matches}));f:close()
assert(#knowledge>0 and matches,'Overall Training provider differs')
f=assert(io.open(out..'/shot.tmp','w'));f:write('pet-training-root');f:close()
assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+30000
while true do
 local ack=io.open(out..'/ack-pet-training-root');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Training capture timeout');script.sleep(1,'frames')
end
