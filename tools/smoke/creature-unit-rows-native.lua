-- Compare sibling-tab identity/activity data with native rows and screen cells.
local out,list,tab=...
local json=require('json');local samples={};local g=df.global.gps
local function collect(widget,active)
 active=active and (widget.flag.whole&1)==1
 if active and (widget.flag.whole&2)~=0 and df.widget_unit_name:is_instance(widget) and widget.u and widget.show_profession then
  local width=math.min(widget.rect.x2-widget.rect.x1+1,widget.min_w)
  if widget.rect.y1>=14 and widget.rect.y1<g.dimy-8 and width>=3 then
   assert(not widget.one_line_only and widget.show_gender==(tab==1),'Unexpected creature name options')
   local text,rc=dfhack.run_command_silent('df3d','creature-unit-row-read',tostring(widget.u.id),tostring(width),widget.show_gender and '1' or '0')
   assert(rc==0,text);local row=json.decode(text);assert(row.happiness==-1,'Sibling row has a happiness indicator')
   local grazer=widget.u.enemy.caste_flags[df.caste_raw_flags.GRAZER]
   local observed={}
   for line,caption in ipairs{row.first_line,row.second_line}do
    local y=widget.rect.y1+line-2
    if grazer and row.second_line~='' then y=y-1 end
    local expected=dfhack.utf2df(caption);local bytes={}
    for x=1,width do
     local tile=dfhack.screen.readTile(widget.rect.x1+x-1,y);bytes[#bytes+1]=tile.ch
     if not(grazer and line==2 and expected=='')then assert(tile.ch==(expected:byte(x)or 0),'Creature name mismatch '..tab..':'..widget.u.id..':'..line..':'..x)end
    end
    observed[#observed+1]=bytes
   end
   local job;local recenter=false;local sheet=false
   for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
    if child.name=='Job'then job=child end
    if child.name=='Recenter button'then recenter=true end
    if child.name=='Unit sheet button'then sheet=true end
    assert(child.name~='Happiness indicator','Native sibling has unexpected happiness')
   end
   assert(recenter==(tab~=3) and sheet==(tab~=3),'Creature navigation options differ')
   assert(job,'Creature activity container missing')
   local caption=dfhack.gui.getWidgetChildren(job)[1];assert(df.widget_text:is_instance(caption))
   assert(dfhack.df2utf(caption.str)==row.activity.caption and caption.fg==row.activity.fg and caption.bg==row.activity.bg and caption.bright==row.activity.bright,'Creature activity differs '..widget.u.id)
   samples[#samples+1]={id=widget.u.id,provider=row,screen=observed,width=width,show_gender=widget.show_gender,recenter=recenter,sheet=sheet}
  end
 end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
end
collect(list,true);assert(#samples>0,'No visible sibling unit rows')
local f=assert(io.open(out..'/creature-unit-rows-'..tab..'.json','w'));f:write(json.encode(samples));f:close()
