-- Native-only header hover oracle; never a runtime menu-state dependency.
local out,view,b,click=...
local gui=require('gui');local script=require('gui.script')
local main=df.global.game.main_interface;local menu=main.assign_trade;local gps=df.global.gps
local frame=df.global.world.frame_counter
local assignments=df.global.plotinfo.main.fortress_entity.assignments_by_type[df.entity_position_responsibility.TRADE]
assert(menu.open and #assignments==0 and #b.jobs==0 and menu.current_type==df.item_type.ANVIL)
local unit
for _,candidate in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(candidate) and candidate.hist_figure_id>=0 and candidate.status.current_soul then unit=candidate;break end end
assert(unit)
local assignment=df.entity_position_assignment:new();assignment.histfig=unit.hist_figure_id
local inserted=false;local result={cases={}}
local function move(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 gps.precise_mouse_x=x;gps.precise_mouse_y=y;gps.mouse_x=x//8;gps.mouse_y=(y-4)//12
 gui.simulateInput(view,{})
 view:render(dfhack.getTickCount())
end
local function sample(label,x,y,instruction)
 local deadline=dfhack.getTickCount()+700
 repeat move(x,y);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 move(x,y);assert(main.current_hover==instruction,'Unexpected depot hover '..label..': '..tostring(main.current_hover))
 local row={label=label,x=x,y=y,instruction=main.current_hover,displayed=main.last_displayed_hover_inst,lines={}}
 if instruction>=0 then
  assert(main.hover_instructions_on)
  for cy=0,17 do local line={}
   for cx=gps.dimx-24,gps.dimx-1 do local ch=dfhack.screen.readTile(cx,cy).ch;line[#line+1]=ch>=32 and string.char(ch%256)or' 'end
   row.lines[#row.lines+1]=dfhack.df2utf(table.concat(line)):gsub('%s+$','')
  end
  while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
 end
 assert(menu.open and #b.jobs==0 and df.global.world.frame_counter==frame)
 result.cases[#result.cases+1]=row

end
local function select_type(kind)
 local index;for i,v in ipairs(menu.filtered_type_list)do if v==kind then index=i;break end end;assert(index)
 menu.scroll_position_type=math.max(0,index-3);view:render(dfhack.getTickCount())
 click(150,4+(7+3*(index-menu.scroll_position_type))*12+12);assert(menu.current_type==kind)
end
local ok,err=xpcall(function()
 sample('hidden-distance',856,94,-1);sample('hidden-value',888,94,-1)
 assignments:insert('#',assignment);inserted=true
 for _,target in ipairs{{'exclude',824,201},{'distance',856,202},{'value',888,203},{'select-all',928,204}}do sample(target[1],target[2],94,target[3])end
 click(824,94);sample('exclude-active',824,94,201);click(824,94)
 select_type(df.item_type.BIN)
 for _,target in ipairs{{'scroll-exclude',808,201},{'scroll-distance',840,202},{'scroll-value',872,203},{'scroll-select-all',912,204}}do sample(target[1],target[2],94,target[3])end
 select_type(df.item_type.ANVIL)
end,debug.traceback)
if inserted then assignments:erase(#assignments-1)end
assignment:delete();move(500,500)
if not ok then error(err)end
result.success=true;return result
