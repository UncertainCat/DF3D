-- Cold typed transport acceptance: no native Stocks menu has been opened.
local out,probe=...
local json=require('json');local script=require('gui.script')
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local changed_material,old_name,old_adj
return dfhack.with_finalize(function()
 if changed_material then
  changed_material.state_name[df.matter_state.Solid]=old_name
  changed_material.state_adj[df.matter_state.Solid]=old_adj
  assert(changed_material.state_name[df.matter_state.Solid]==old_name and changed_material.state_adj[df.matter_state.Solid]==old_adj)
  write('stocks-pages-restored','yes')
 end
end,function()
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
 if os.getenv('DF3D_STOCKS_MORE_FURNITURE')=='1' then families={10,15,16,19,21,33,34,37,38};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_MATERIAL_SHEETS')=='1' then families={0,1,2,3,4,5};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_TEXTILE_SHEETS')=='1' then families={57,58};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_EQUIPMENT_SHEETS')=='1' then families={24,27,31,61,62,82,83};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_SUBTYPE_SHEETS')=='1' then families={14,65,68};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_ART_SHEETS')=='1' then families={22,36};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_CRITTER_SHEETS')=='1' then families={51,52};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_EGG_REMAINS_SHEETS')=='1' then families={88,47};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_TOOL_SHEETS')=='1' then families={86};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_COIN_SHEETS')=='1' then families={74};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_LEATHER_SHEETS')=='1' then families={55,59,66,76,91};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_REMAINING_FURNITURE')=='1' then families={40,41,42,43,44,63,64,67,77,78,79,80,81,84,85,92};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_FISH_SHEETS')=='1' then families={49,50};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_MEAL_SHEETS')=='1' then families={56,72};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_LIQUID_SHEETS')=='1' then families={69,70,73};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_FOOD_SHEETS')=='1' then families={48,54,71,75};reference.missing_furniture={}end
 if os.getenv('DF3D_STOCKS_CONTAINER_SHEETS')=='1' then families={17,31,32};reference.missing_furniture={}end
 for _,kind in ipairs(families)do
  local selection=probe('stocks-selection-probe',tostring(kind),'')
  if #selection.groups==0 and reference.missing_furniture then reference.missing_furniture[#reference.missing_furniture+1]=kind
  else
   assert(#selection.groups>0,'Missing furniture fixture '..kind)
   reference.furniture[#reference.furniture+1]={kind=kind,id=selection.groups[1].ids[1]}
  end
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
if os.getenv('DF3D_STOCKS_PAGES')=='1' then
 local selected=probe('stocks-selection-probe','4','');local chosen
 for _,group in ipairs(selected.groups)do if #group.ids>=64 then chosen=group;break end end
 assert(chosen,'Need64 boulders of one material for paged Stocks fixture')
 local info=assert(dfhack.matinfo.decode(df.item.find(chosen.ids[1])))
 changed_material=info.material;old_name=changed_material.state_name[df.matter_state.Solid];old_adj=changed_material.state_adj[df.matter_state.Solid]
 local long=string.rep('p',12000)
 changed_material.state_name[df.matter_state.Solid]=long;changed_material.state_adj[df.matter_state.Solid]=long
 local ids={};for index=1,64 do ids[index]=chosen.ids[index]end
 reference.paged={ids=ids,selection=probe('stocks-selection-probe','4',''),minimum_caption_bytes=12000}
end
-- Establish edit invariants after all native read-side lazy initialization.
if os.getenv('DF3D_STOCKS_SCENE')=='1' then
 local prior={};for _,item in ipairs(df.global.world.items.other.IN_PLAY)do prior[item.id]=item.flags.whole end
 probe('item-inspect-probe',tostring(reference.selection.groups[1].ids[1]))
 local changes={};for _,item in ipairs(df.global.world.items.other.IN_PLAY)do
  if prior[item.id]~=item.flags.whole then changes[#changes+1]={id=item.id,before=prior[item.id],after=item.flags.whole}end
 end
 write('stocks-scene-read-initialization.json',json.encode(changes))
end
for _,item in ipairs(df.global.world.items.other.IN_PLAY)do before[item.id]=item.flags.whole end
write('stocks-wire-reference.json',json.encode(reference))
write('shot.tmp','stocks-wire');assert(os.rename(out..'/shot.tmp',out..'/shot'))
local scene=os.getenv('DF3D_STOCKS_SCENE')=='1'
local checked=0;local deadline=dfhack.getTickCount()+(scene and 115000 or reference.child_flags and 60000 or 25000)
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
assert(checked==(scene and 0 or 2),'Stocks wire effects incomplete')
if scene then
 local changes={};for id,flags in pairs(before)do
  if df.item.find(id).flags.whole~=flags then changes[#changes+1]={id=id,before=flags,after=df.item.find(id).flags.whole}end
 end
 write('stocks-scene-effects.json',json.encode({changes=changes,unchanged=#changes==0}))
 assert(#changes==0,'Stocks scene navigation changed item flags')
end
if reference.child_flags then assert(checked_child==8,'Child effects incomplete');write('stocks-child-flags-native-result.json',json.encode({success=true,steps=checked_child,restored=true,target=reference.child_flags}))end
assert(not df.global.game.main_interface.stocks.open,'Typed Stocks opened native menu')

end)
