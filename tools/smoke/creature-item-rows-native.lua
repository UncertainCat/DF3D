-- Controlled viewport positioning; native rendering remains the row oracle.
local out,view,list=...
local script=require('gui.script');local json=require('json');local found=false
local function contains_item(widget)
 if df.widget_item_name:is_instance(widget) and widget.it then return true end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if contains_item(child)then return true end end end
 return false
end
local function position(widget)
 if df.widget_scroll_rows:is_instance(widget)then
  local rows=dfhack.gui.getWidgetChildren(widget)
  for ordinal,row in ipairs(rows)do if contains_item(row)then widget.scroll=math.max(0,math.min(ordinal-1,#rows-widget.num_visible));found=true;return end end
 end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do position(child)end end
end
position(list);assert(found,'No item pet row in fixture')
for _=1,15 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local samples={};local g=df.global.gps
local function collect(widget)
 if df.widget_item_name:is_instance(widget) and widget.it and widget.rect.y1>=14 and widget.rect.y1<g.dimy-8 then
  local item=widget.it;local flags=item.flags.whole
  local text,rc=dfhack.run_command_silent('df3d','creature-item-row-read',tostring(item.id));assert(rc==0,text)
  local row=json.decode(text);local caption=dfhack.utf2df(row.caption);local cells={}
  assert(#caption>0 and widget.rect.x1+#caption<g.dimx,'Item caption outside fixture viewport')
  for index=1,#caption do
   local tile=dfhack.screen.readTile(widget.rect.x1+index-1,widget.rect.y1-1)
   assert(tile.ch==caption:byte(index),'Item pet caption differs '..index)
   assert(tile.fg==row.color[1] and tile.bg==row.color[2] and (tile.bold and 1 or 0)==row.color[3],'Item pet caption color differs')
   cells[#cells+1]={ch=tile.ch,fg=tile.fg,bg=tile.bg,bright=tile.bold}
  end
  local position;local sheet=false;local activity
  for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
   if child.name=='Recenter button'then
    local _,address=df.sizeof(child);position={}
    for index=0,2 do position[#position+1]=df.reinterpret_cast('int16_t',address+0x150+index*2).value end
   end
   if df.widget_item_sheet_button:is_instance(child)then sheet=true end
   if child.name=='Job'then activity=dfhack.gui.getWidgetChildren(child)[1]end
  end
  assert(position and json.encode(position)==json.encode(row.position),'Item pet Recenter position differs')
  assert(sheet and item.flags.whole==flags,'Item pet navigation/flags differ')
  assert(activity and dfhack.df2utf(activity.str)==row.activity and activity.fg==row.activity_color[1] and activity.bg==row.activity_color[2] and (activity.bright and 1 or 0)==row.activity_color[3],'Item pet activity differs')
  samples[#samples+1]={id=item.id,provider=row,cells=cells,position=position,sheet=sheet}
 end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child)end end
end
collect(list);assert(#samples>0,'Item pet not visible')
local f=assert(io.open(out..'/creature-item-rows.json','w'));f:write(json.encode(samples));f:close()
