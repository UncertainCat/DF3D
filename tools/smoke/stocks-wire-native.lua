-- Cold typed transport acceptance: no native Stocks menu has been opened.
local out,probe=...
local json=require('json');local script=require('gui.script')
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local reference={selection=probe('stocks-selection-probe','39',''),
 display=probe('stocks-display-probe').rows,order=probe('stocks-categories-probe','').types,
 matches=probe('stocks-categories-probe','iron').types}
local before={}
local members={};for _,id in ipairs(reference.selection.groups[1].ids)do members[id]=true end
local original=df.item.find(reference.selection.groups[1].ids[1]).flags.hidden
for id in pairs(members)do assert(df.item.find(id).flags.hidden==original,'Fixture needs uniform visibility')end
local px,py,pz=dfhack.items.getPosition(df.item.find(reference.selection.groups[1].ids[1]))
reference.position={px,py,pz}
reference.original_hidden=original
reference.individual=os.getenv("DF3D_STOCKS_ITEM_WIRE")=="1"
if reference.individual then members={[reference.selection.groups[1].ids[1]]=true} end
reference.appearance={}
for _,id in ipairs(reference.selection.groups[1].ids)do
 local item=df.item.find(id)
 reference.appearance[tostring(id)]={stack=item:getStackSize(),flags=(item.flags.artifact and 32 or 0)|(item.flags.spider_web and 64 or 0)}
end
if os.getenv('DF3D_STOCKS_FURNITURE_SHEETS')=='1' then
 reference.furniture={}
 local families=os.getenv("DF3D_STOCKS_CONTENTS_RENDER")=="1" and {32} or {6,7,8,9,11,12,17,18,20,32,35,45}
 for _,kind in ipairs(families)do
  local selection=probe('stocks-selection-probe',tostring(kind),'')
  assert(#selection.groups>0,'Missing furniture fixture '..kind)
  reference.furniture[#reference.furniture+1]={kind=kind,id=selection.groups[1].ids[1]}
 end
end
if os.getenv('DF3D_STOCKS_CONTENTS_WIRE')=='1' or os.getenv('DF3D_STOCKS_CHILD_FLAGS')=='1' then
 reference.contents={}
 for _,kind in ipairs{6,17,18,32}do
  local selection=probe('stocks-selection-probe',tostring(kind),'')
  local id=selection.groups[1].ids[1]
  -- Production inspection formats weight first; retain native lazy mass-cache effects.
  probe('item-inspect-probe',tostring(id))
  local contents=probe('item-sheet-contents-probe',tostring(id));local expected={}
  for _,ref in ipairs(df.item.find(id).flags.container and df.item.find(id).general_refs or {})do
   local type=ref:getType();local target
   if type==df.general_ref_type.CONTAINS_ITEM then target=ref:getItem()
   elseif type==df.general_ref_type.CONTAINS_UNIT then target=ref:getUnit()end
   if target then expected[#expected+1]={kind=type==df.general_ref_type.CONTAINS_ITEM and 1 or 2,id=target.id}end
  end
  assert(#expected==#contents.rows,'Contents provider membership count differs')
  for index,row in ipairs(expected)do assert(contents.rows[index].id==row.id and contents.rows[index].kind==row.kind,'Contents provider ordering differs')end
  reference.contents[#reference.contents+1]=contents
 end
end
local before_melt={};local checked_child=0
if os.getenv('DF3D_STOCKS_CHILD_FLAGS')=='1' then
 for _,contents in ipairs(reference.contents)do
  if df.item.find(contents.item_id):getType()==df.item_type.BIN then
   for _,row in ipairs(contents.rows)do
    if row.kind==1 and row.can_melt and row.flags&0x800000==0 then reference.child_flags={parent_id=contents.item_id,id=row.id,flags=row.flags};break end
   end
  end
 end
 assert(reference.child_flags,'Missing meltable bin child fixture')
 for _,item in ipairs(df.global.world.items.other.ANY_MELT_DESIGNATED)do before_melt[item.id]=true end
end
-- Establish edit invariants after all native read-side lazy initialization.
for _,item in ipairs(df.global.world.items.other.IN_PLAY)do before[item.id]=item.flags.whole end
write('stocks-wire-reference.json',json.encode(reference))
write('shot.tmp','stocks-wire');assert(os.rename(out..'/shot.tmp',out..'/shot'))
local checked=0;local deadline=dfhack.getTickCount()+(reference.child_flags and 60000 or 25000)
while true do
 local step=io.open(out..'/stocks-wire-step')
 if step then local index=tonumber(step:read('*a'));step:close()
  if index and index>checked then
   assert(index==checked+1 and index<=2,'Unexpected Stocks edit step')
   local desired
   if index==1 then desired=not original else desired=original end
   for id,flags in pairs(before)do
    local expected=flags
    if members[id]then if desired then expected=flags|0x1000000 else expected=flags&(~0x1000000)end end
    assert(df.item.find(id).flags.whole==expected,'Stocks wire changed wrong item flags '..id)
   end
   checked=index;write('stocks-wire-ack',tostring(index))
  end
 end
 if reference.child_flags then
  local step=io.open(out..'/stocks-child-flags-step')
  if step then local index=tonumber(step:read('*a'));step:close()
   if index and index>checked_child then
    assert(checked==2 and index==checked_child+1 and index<=8,'Unexpected child flag step')
    local operation=(index-1)//2+1;local mask=({0x80000,0x200000,0x800000,0x1000000})[operation]
    local original=before[reference.child_flags.id]&mask~=0;local desired=index%2==1 and not original or index%2==0 and original
    for id,flags in pairs(before)do
     local expected=flags
     if id==reference.child_flags.id then expected=desired and (flags|mask) or (flags&(~mask))end
     assert(df.item.find(id).flags.whole==expected,'Child edit affected wrong flags '..id)
    end
    local expected={};for id in pairs(before_melt)do expected[id]=true end
    if operation==3 then expected[reference.child_flags.id]=desired or nil end
    for _,item in ipairs(df.global.world.items.other.ANY_MELT_DESIGNATED)do assert(expected[item.id],'Unexpected melt registration');expected[item.id]=nil end
    assert(next(expected)==nil,'Missing melt registration')
    checked_child=index;write('stocks-child-flags-ack',tostring(index))
   end
  end
 end
 local ack=io.open(out..'/ack-stocks-wire');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Stocks wire timeout');script.sleep(1,'frames')
end
assert(checked==2,'Stocks wire effects incomplete')
if reference.child_flags then assert(checked_child==8,'Child effects incomplete');write('stocks-child-flags-native-result.json',json.encode({success=true,steps=checked_child,restored=true,target=reference.child_flags}))end
assert(not df.global.game.main_interface.stocks.open,'Typed Stocks opened native menu')
