-- Protected paused diagnostic: temporary item power prose, never product copy.
local out,view,records,b,capture,select_map=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local item=assert(b.contained_items[0].item)
local original={magic=item.magic,flags=item.flags.whole,whole=item.weight.whole,fraction=item.weight.fraction}
local all=df.global.world.raws.interactions.all;local index=#all
local interaction=df.interaction:new();local source=df.interaction_source_item_powerst:new()
interaction.sources:insert('#',source);all:insert('#',interaction)
item.magic=nil;item.magic={new=true};local magic=item.magic
local power=df.item_powerst:new();power.interaction_index=index;power.interaction_source_index=0;power.delay=0
magic.power:insert('#',power)
local function move(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function open()
 if sheet.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
 select_map(b);move(756,526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id)
 move(0,4)
 for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
end
local cases={}
for _,length in ipairs{53,54,55,108,109}do cases[#cases+1]={name='word-'..length,text=('ABCDEFGHIJKLMNOPQRSTUVWXYZ'):rep(5):sub(1,length)}end
cases[#cases+1]={name='spaced-long',text=('Native layout probe sentence.  '):rep(100)}
cases[#cases+1]={name='word-long',text=('ABCDEFGHIJKLMNOPQRSTUVWXYZ'):rep(100)}
local ok,err=xpcall(function()
 for _,case in ipairs(cases)do
  source.item_description=case.text;open()
  local expected=dfhack.df2utf(sheet.raw_description)
  local text,code=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(item.id));assert(code==0,text)
  local observed=json.decode(text).snapshot;assert(observed.description==expected,'native description observation differs')
  local row=capture('farm-item-description-layout-'..case.name)
  row.description=expected;row.snapshot=observed;row.description_width=sheet.description_width
  row.positions={}
  for key,value in pairs(sheet)do if type(key)=='string' and key:find('scroll_position',1,true)then row.positions[key]=value end end
  if case.name=='spaced-long' then
   for _,probe in ipairs{{'wheel','CONTEXT_SCROLL_DOWN',600,150},{'page','CONTEXT_SCROLL_PAGEDOWN',600,150},{'outside','CONTEXT_SCROLL_DOWN',600,300},{'arrow','_MOUSE_L',872,214},{'track','_MOUSE_L',872,190},{'bar-page','CONTEXT_SCROLL_PAGEDOWN',872,160},{'standard','STANDARDSCROLL_DOWN',600,150},{'standard-page','STANDARDSCROLL_PAGEDOWN',600,150}}do
    sheet.scroll_position_description=0;sheet.scrolling_description=false
    move(probe[3],probe[4]);gui.simulateInput(view,probe[2]);move(0,4)
    local sample=capture('farm-item-description-layout-'..probe[1])
    sample.description=expected;sample.snapshot=observed;sample.description_width=sheet.description_width
    sample.first=sheet.scroll_position_description;sample.count=#sheet.description.text
   end
   local old_lift=df.global.enabler.mouse_lbut_lift
   local drag_ok,drag_error=xpcall(function()
    for _,y in ipairs{124,160,190,220}do
     sheet.scroll_position_description=0;sheet.scrolling_description=false;move(872,142)
     df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
     g.precise_mouse_x=872;g.precise_mouse_y=y;g.mouse_x=109;g.mouse_y=(y-4)//12
     gui.simulateInput(view,{'_MOUSE_L_DOWN'})
     df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{});move(0,4)
     local sample=capture('farm-item-description-layout-drag-'..y)
     sample.description=expected;sample.snapshot=observed;sample.description_width=sheet.description_width
     sample.first=sheet.scroll_position_description;sample.count=#sheet.description.text
    end
   end,debug.traceback)
   df.global.enabler.mouse_lbut_lift=old_lift;assert(drag_ok,drag_error)
   sheet.scroll_position_description=0;sheet.scrolling_description=false;move(872,214)
   for i=1,100 do gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())end
   move(0,4)
   local sample=capture('farm-item-description-layout-end')
   sample.description=expected;sample.snapshot=observed;sample.description_width=sheet.description_width
   sample.first=sheet.scroll_position_description;sample.count=#sheet.description.text
  end
 end
end,debug.traceback)
if sheet.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
item.magic=original.magic;assert(all[#all-1]==interaction);all:erase(#all-1)
df.delete(power);df.delete(magic);df.delete(source);df.delete(interaction)
item.flags.whole=original.flags;item.weight.whole=original.whole;item.weight.fraction=original.fraction
select_map(b)
assert(item.magic==original.magic and #all==index and item.flags.whole==original.flags)
assert(ok,err)
records[#records+1]={name='farm-item-description-layout-restored',restored=true,item_id=item.id}
