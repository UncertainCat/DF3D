-- Native input/layout reference in the paused, owned fixture. No text is edited.
local unit,view,capture=...
local gui=require('gui')
local g=df.global.gps
local main=df.global.game.main_interface
local sheet=main.view_sheets
local original={nickname=unit.name.nickname,profession=unit.custom_profession,
 customizing=sheet.unit_overview_customizing,nickname_focus=sheet.unit_overview_entering_nickname,
 profession_focus=sheet.unit_overview_entering_profession_nickname,draft=sheet.unit_overview_entering_str}
local frame=df.global.world.frame_counter
local observations={}
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.mouse_x=x//8;g.mouse_y=(y-4)//12;g.precise_mouse_x=x;g.precise_mouse_y=y
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function record(name)
 capture('unit-header-actions-'..name)
 observations[#observations+1]={name=name,customizing=sheet.unit_overview_customizing,
  nickname_focus=sheet.unit_overview_entering_nickname,
  profession_focus=sheet.unit_overview_entering_profession_nickname,
  draft=dfhack.df2utf(sheet.unit_overview_entering_str),open=sheet.open,active_id=sheet.active_id}
 assert(unit.name.nickname==original.nickname and unit.custom_profession==original.profession,'focus action edited unit')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'header reference advanced simulation')
end
local function click(x,y)
 pointer(x,y);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local ok,err=xpcall(function()
 local found
 for y=64,136,12 do for x=792,888,8 do
  pointer(x,y)
  if main.current_hover==df.main_hover_instruction.UNIT_SHEET_CUSTOMIZE then found={x,y};break end
 end if found then break end end
 assert(found,'native Customize hitbox not found')
 observations[#observations+1]={name='customize-hitbox',mouse=found,hover=main.current_hover}
 click(found[1],found[2]);assert(sheet.unit_overview_customizing,'Customize did not open editor')
 record('open')
 click(600,82);assert(sheet.unit_overview_entering_nickname,'nickname field did not focus');record('nickname-focus')
 click(600,118);assert(sheet.unit_overview_entering_profession_nickname,'profession field did not focus');record('profession-focus')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not sheet.unit_overview_customizing and sheet.open and sheet.active_id==unit.id,'Escape did not return to unit Overview')
 record('escape')
end,debug.traceback)
sheet.unit_overview_customizing=original.customizing
sheet.unit_overview_entering_nickname=original.nickname_focus
sheet.unit_overview_entering_profession_nickname=original.profession_focus
sheet.unit_overview_entering_str=original.draft
pointer(0,4)
assert(ok,err)
return observations
