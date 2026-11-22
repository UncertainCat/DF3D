local out,list=...
local json=require('json');local samples={};local visible=0
local function compare(widget,active)
 active=active and (widget.flag.whole&1)==1
 local target,kind
 if df.widget_unit_portrait:is_instance(widget)then target=widget.u;kind=0 end
 if df.widget_item_portrait:is_instance(widget)then target=widget.i;kind=1 end
 if target then
  local owners={}
  local function names(child)
   if df.widget_unit_name:is_instance(child) and child.u then owners[#owners+1]=child end
   if df.widget_container:is_instance(child)then for _,nested in ipairs(dfhack.gui.getWidgetChildren(child))do names(nested)end end
  end
  for ordinal,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do if ordinal>=6 then names(child)end end
  local text,rc=dfhack.run_command_silent('df3d','pet-controls-probe',tostring(kind),tostring(target.id),'owners');assert(rc==0,text)
  local rows=json.decode(text);assert(#rows==#owners,'Pet owner count differs')
  for i,name in ipairs(owners)do
   local row=rows[i];local width=math.max(name.min_w,name.rect.x2-name.rect.x1+1)
   assert(row.id==name.u.id and row.columns==width and row.show_gender==name.show_gender and row.show_profession==name.show_profession and row.one_line_only==name.one_line_only,'Pet owner widget options differ')
   if active and (name.flag.whole&1)==1 and name.rect.y1>=14 and name.rect.y1<df.global.gps.dimy-8 then
    for line,caption in ipairs{row.first_line,row.second_line}do
     local bytes=dfhack.utf2df(caption)
     for x=1,#bytes do
      local tile=dfhack.screen.readTile(name.rect.x1+x-1,name.rect.y1+line-2)
      if tile.ch~=bytes:byte(x)then
       local cells={};for yy=name.rect.y1-3,name.rect.y1+2 do
        local chars={};for xx=name.rect.x1,name.rect.x1+width-1 do chars[#chars+1]=dfhack.screen.readTile(xx,yy).ch end
        cells[#cells+1]={y=yy,chars=chars}
       end
       local f=assert(io.open(out..'/pet-owner-failure.json','w'));f:write(json.encode({pet=target.id,owner=row,rect={name.rect.x1,name.rect.y1,name.rect.x2,name.rect.y2},cells=cells,dimy=df.global.gps.dimy}));f:close()
      end
      assert(tile.ch==bytes:byte(x),'Pet owner text differs '..row.id..':'..line..':'..x..' actual='..tile.ch..' expected='..bytes:byte(x))
      local function matches(c)return tile.fg==c[1] and tile.bg==c[2] and (tile.bold and 1 or 0)==c[3]end
      assert(matches(row.color) or (row.effect~=0 and matches(row.alternate)),'Pet owner color differs '..row.id)
     end
    end
    visible=visible+1
   end
  end
  samples[#samples+1]={kind=kind,id=target.id,owners=rows}
 end
 if df.widget_container:is_instance(widget)then
  for ordinal,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   local visible=active
   if df.widget_scroll_rows:is_instance(widget)then visible=visible and ordinal>widget.scroll and ordinal<=widget.scroll+widget.num_visible end
   compare(child,visible)
  end
 end
end
compare(list,true);assert(visible>0,'No visible owner name verified')
local f=assert(io.open(out..'/pet-owner-rows.json','w'));f:write(json.encode({samples=samples,visible=visible}));f:close()
