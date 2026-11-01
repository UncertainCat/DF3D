-- Synthetic containment references in an owned paused clone. No equip or move
-- action; the selected creature doubles as a contained name-formatting input.
local unit,pointer,read,view,capture=...
local parent=unit.inventory[0].item;local child=unit.inventory[1].item
local parent_flags,child_flags=parent.flags.whole,child.flags.whole
local parent_count,child_count=#parent.general_refs,#child.general_refs
local item_ref=df.general_ref_contains_itemst:new();item_ref.item_id=child.id
local unit_ref=df.general_ref_contains_unitst:new();unit_ref.unit_id=unit.id
local missing_ref=df.general_ref_contains_itemst:new();missing_ref.item_id=2147483647
local nested_ref=df.general_ref_contains_itemst:new();nested_ref.item_id=unit.inventory[2].item.id
local function reset()
 while #parent.general_refs>parent_count do parent.general_refs:erase(#parent.general_refs-1)end
 while #child.general_refs>child_count do child.general_refs:erase(#child.general_refs-1)end
 parent.flags.whole=parent_flags;child.flags.whole=child_flags
end
local function line(y)
 local text={}
 for x=61,111 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256) or ' 'end
 return dfhack.df2utf(table.concat(text)):match('^%s*(.-)%s*$')
end
local function visible(text)
 return dfhack.df2utf(dfhack.utf2df(text):gsub('[%z\1-\31]',' ')):match('^%s*(.-)%s*$')
end
local cases={}
local function navigation()
 local gui=require('gui');local script=require('gui.script')
 local main=df.global.game.main_interface;local sheet=main.view_sheets;local g=df.global.gps
 local saved,vectors={},{}
 for _,key in ipairs{'open','context','active_sheet','active_id','active_sub_tab','scroll_position_inventory',
  'scroll_position','viewing_bldid','viewing_x','viewing_y','viewing_z'}do saved[key]=sheet[key]end
 for _,key in ipairs{'viewing_unid','viewing_itid','viewing_vermin_combined_id'}do
  vectors[key]={};for _,id in ipairs(sheet[key])do vectors[key][#vectors[key]+1]=id end
 end
 local function restore()
  for key,value in pairs(saved)do sheet[key]=value end
  for key,values in pairs(vectors)do sheet[key]:resize(0);for _,id in ipairs(values)do sheet[key]:insert('#',id)end end
  pointer(400,400)
 end
 local result={targets={},weight_cache_items={}}
 local old_flags={};for i,entry in ipairs(unit.inventory)do old_flags[i]=entry.item.flags.whole end
 local ok,err=xpcall(function()
  capture('unit-items-contained-rows')
  for _,case in ipairs{{'item',262,child.id,df.view_sheet_type.ITEM,295},
   {'creature',298,unit.id,df.view_sheet_type.UNIT,296}}do
   restore();local deadline=dfhack.getTickCount()+650
   while dfhack.getTickCount()<deadline do pointer(852,case[2]);script.sleep(1,'frames')end
   pointer(852,case[2]);assert(main.current_hover==case[5] and main.hover_instructions_on,'Contained help did not activate')
   local value={name=case[1],hover=main.current_hover,lines={}}
   for y=0,17 do
    local text={};for x=g.dimx-24,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);text[#text+1]=pen.ch>=32 and string.char(pen.ch%256)or' 'end
    value.lines[#value.lines+1]=dfhack.df2utf(table.concat(text)):gsub('%s+$','')
   end
   while #value.lines>0 and value.lines[#value.lines]==''do table.remove(value.lines)end
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   pointer(400,400);value.open=sheet.open;value.kind=sheet.active_sheet;value.id=sheet.active_id;value.tab=sheet.active_sub_tab
   assert(value.open and value.kind==case[4] and value.id==case[3],'Contained View selected wrong target')
   capture('unit-items-contained-'..case[1]..'-inspected');result.targets[#result.targets+1]=value
  end
  restore();pointer(852,334)
  result.missing_hover=main.current_hover
 end,debug.traceback)
 restore()
 local flags_ok=true
 for i,entry in ipairs(unit.inventory)do
  local before,after=old_flags[i],entry.item.flags.whole
  if before~=after then
   flags_ok=flags_ok and (after==(before|0x20000000)) and (entry.item.id==child.id or entry.item.id==nested_ref.item_id)
   result.weight_cache_items[#result.weight_cache_items+1]=entry.item.id
   entry.item.flags.whole=before
  end
 end
 assert(ok,err);assert(flags_ok,'Contained inspection changed unexpected item flags');return result
end
local ok,err=xpcall(function()
 for _,case in ipairs{{'item-creature-missing',false,true},{'creature-item-missing',true,true},{'container-flag-off',false,false}}do
  reset();parent.flags.container=case[3];child.flags.container=true
  child.general_refs:insert('#',nested_ref)
  parent.general_refs:insert('#',case[2]and unit_ref or item_ref)
  parent.general_refs:insert('#',case[2]and item_ref or unit_ref)
  parent.general_refs:insert('#',missing_ref)
  local result=read();pointer(400,400)
  local contents=result.rows[1].contents;local captions={}
  if case[3]then
   assert(#contents==3,'Expected immediate refs, including unresolved blank row')
   assert(contents[1].kind==(case[2]and 2 or 1) and contents[2].kind==(case[2]and 1 or 2),'Contained order')
   assert(contents[3].id==-1 and contents[3].caption=='','Unresolved ref must preserve blank row')
   for i,row in ipairs(contents)do
    captions[i]=line(18+i*3)
    assert(visible(row.caption)==captions[i],'Contained caption differs: '..case[1]..' row '..i..' ['..row.caption..'] ['..captions[i]..']')
   end
   assert(line(30)==visible(result.rows[2].caption),'Unexpected recursive expansion or lost blank row')
  else
   assert(#contents==0,'Container flag ignored')
   assert(line(21)==visible(result.rows[2].caption),'Native container flag ignored')
  end
  local value={name=case[1],contents=contents,native_captions=captions,guards_unchanged=result.guards_unchanged}
  if case[1]=='item-creature-missing'and os.getenv('DF3D_UNIT_ITEMS_CONTENTS_NAVIGATION')=='1'then value.navigation=navigation()end
  cases[#cases+1]=value
 end
end,debug.traceback)
reset()
for _,ref in ipairs{item_ref,unit_ref,missing_ref,nested_ref}do df.delete(ref)end
pointer(400,400)
assert(ok,err)
return cases
