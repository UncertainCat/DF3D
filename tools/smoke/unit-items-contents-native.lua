-- Synthetic containment references in an owned paused clone. No equip or move
-- action; the selected creature doubles as a contained name-formatting input.
local unit,pointer,read=...
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
  cases[#cases+1]={name=case[1],contents=contents,native_captions=captions,guards_unchanged=result.guards_unchanged}
 end
end,debug.traceback)
reset()
for _,ref in ipairs{item_ref,unit_ref,missing_ref,nested_ref}do df.delete(ref)end
pointer(400,400)
assert(ok,err)
return cases
