-- Observe native Other Details controls and compare their actual markup to the
-- owned provider. Runs only in the enclosing disposable protected native lane.
local out,view,info,list,callbacks=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local buttons={}
local original_cursor=list.cursor_idx
local function find(widget,owner)
 if (widget.flag.whole&1)==0 then return end
 if owner and (widget.flag.whole&2)~=0 and widget.min_w==3 and widget.min_h==3 then
  for _,target in ipairs(callbacks(widget.custom_activated,64))do
   if target==0x1431cd0 or target==0x1431d60 then buttons[#buttons+1]={widget=widget,id=owner.id};break end
  end
 end
 if df.widget_container:is_instance(widget)then
  local children=dfhack.gui.getWidgetChildren(widget)
  for _,child in ipairs(children)do if df.widget_unit_name:is_instance(child) and child.u then owner=child.u;break end end
  for _,child in ipairs(children)do find(child,owner)end
 end
end
find(list,nil);assert(#buttons>0,'No native Other activity buttons')
local g=df.global.gps;local en=df.global.enabler
local mouse={g.precise_mouse_x,g.precise_mouse_y,g.mouse_x,g.mouse_y};local focus,tracking=en.mouse_focus,en.tracking_on
local function settle()script.sleep(3,'frames');view:render(dfhack.getTickCount())end
local function click(widget)
 local x,y=widget.rect.x1+1,widget.rect.y1+1
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 en.mouse_focus=true;en.tracking_on=1;en.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
 en.mouse_lbut=0;en.mouse_lbut_down=0;en.mouse_lbut_lift=1;settle()
end
local observations={}
for _,entry in ipairs(buttons)do
 local text,rc=dfhack.run_command_silent('df3d','residents-activity-description-probe',tostring(entry.id),'80')
 assert(rc==0,text);observations[tostring(entry.id)]=json.decode(text)
end
click(buttons[1].widget)
local opened_cursor=list.cursor_idx
local box=info.creatures.activity_details_text;local words={}
for _,word in ipairs(box.word)do words[#words+1]={text=dfhack.df2utf(word.str),rgb={word.red,word.green,word.blue},link=word.link_index,x=word.px,y=word.py,flags=word.flags.whole}end
assert(#words>0,'Other activity button did not populate native markup')
local text,rc=dfhack.run_command_silent('df3d','residents-activity-description-probe',tostring(buttons[1].id),tostring(box.current_width))
assert(rc==0,text);local provider=json.decode(text)
assert(provider.max_y==box.max_y and json.encode(provider.words)==json.encode(words),'Other activity description differs from native click')
local shot=assert(io.open(out..'/shot.tmp','w'));shot:write('other-activity-details');shot:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+30000
while true do
 local ack=io.open(out..'/ack-other-activity-details');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Other activity screenshot timeout');script.sleep(1,'frames')
end
local close
local function find_close(widget)
 if (widget.flag.whole&1)==0 then return end
 if df.widget_text:is_instance(widget) and widget.str=='Close' then close=widget.parent end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find_close(child)end end
end
find_close(info.creatures);click(assert(close,'Other activity Close missing'));assert(info.open,'Other Close lost list')
local closed_cursor=list.cursor_idx;list.cursor_idx=original_cursor
g.precise_mouse_x=mouse[1];g.precise_mouse_y=mouse[2];g.mouse_x=mouse[3];g.mouse_y=mouse[4];en.mouse_focus=focus;en.tracking_on=tracking;settle()
local f=assert(io.open(out..'/other-activity-reference.json','w'));f:write(json.encode({rows=observations,cursor_before=original_cursor,cursor_open=opened_cursor,cursor_closed=closed_cursor,clicked=buttons[1].id,clicked_provider=provider,native_matches=true,closed=true}));f:close()
