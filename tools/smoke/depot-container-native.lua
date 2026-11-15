-- Diagnostic-only native container expansion oracle in a paused disposable save.
local view,b,capture,click=...
local gui=require('gui')
local json=require('json')
local menu=df.global.game.main_interface.assign_trade
local frame=df.global.world.frame_counter
assert(menu.open and #b.jobs==0 and menu.item_filter=='')
local function select_type(kind)
 local index
 for i,v in ipairs(menu.filtered_type_list)do if v==kind then index=i;break end end
 assert(index,'Missing container category')
 menu.scroll_position_type=math.max(0,index-3);view:render(dfhack.getTickCount())
 click(150,4+(7+3*(index-menu.scroll_position_type))*12+12)
 assert(menu.current_type==kind)
end
local function children(item)
 local result={}
 for _,ref in ipairs(item.general_refs)do
  if ref:getType()==df.general_ref_type.CONTAINS_ITEM then
   local child=ref:getItem()
   if child then result[#result+1]={id=child.id,type=child:getType(),flags=child.flags.whole}end
  end
 end
 return result
end
select_type(df.item_type.BIN)
local target,cell
local cursor=9
for i,subtype in ipairs(menu.current_type_a_subtype)do
 if menu.current_type_a_on[i]then
  cursor=cursor+3
  if menu.current_type_a_expanded[i]then
   for _,row in ipairs(menu.current_type_tgi)do
    if row.it:getSubtype()==subtype and row.it:getMaterial()==menu.current_type_a_subcat1[i] and row.it:getMaterialIndex()==menu.current_type_a_subcat2[i]then
     if not target and #children(row.it)>0 then target=row;cell=cursor end
     cursor=cursor+3+(row.expanded_container and row.container_amount*3 or 0)
    end
   end
  end
 end
end
assert(target and not target.expanded_container,'No collapsed populated bin')
local id=target.it.id
local initial_children=children(target.it)
assert(target.container_amount==#initial_children,'Native count differs from resolved direct children')
local result={id=id,children=initial_children,container_amount=target.container_amount,cases={}}
local initial_tags={}
for _,row in ipairs(menu.master_i_list.tgi)do initial_tags[row.it.id]=row.tag end
local function current()
 for _,row in ipairs(menu.master_i_list.tgi)do if row.it.id==id then return row end end
 error('Container disappeared')
end
local function sample(label)
 view:render(dfhack.getTickCount())
 assert(menu.open and #b.jobs==0 and df.global.world.frame_counter==frame)
 local row=current();local observed=children(row.it)
 assert(#observed==#initial_children)
 for i,child in ipairs(observed)do assert(child.id==initial_children[i].id and child.flags==initial_children[i].flags)end
 local tags={};for _,entry in ipairs(menu.master_i_list.tgi)do
  assert(entry.tag==initial_tags[entry.it.id],'Container interaction changed haul selection')
  tags[#tags+1]={id=entry.it.id,tag=entry.tag}
 end
 result.cases[#result.cases+1]={label=label,expanded=row.expanded_container,height=menu.i_height,scroll=menu.scroll_position_item,category=menu.current_type,query=menu.item_filter,tags=tags}
 capture('depot-container-'..label)
end
-- Oracle viewport setup; expansion itself uses the real row hitbox.
menu.scroll_position_item=math.max(0,cell-12)
sample('initial')
local initial_height=menu.i_height
click(500,4+(cell-menu.scroll_position_item)*12+12)
sample('expanded')
assert(current().expanded_container and menu.i_height==initial_height+3*#initial_children,'Container click/height differs')
if os.getenv('DF3D_DEPOT_CONTAINER_PROVIDER')=='1' then
 local function probe(parent,offset,limit,expect_ok)
  local text,code=dfhack.run_command_silent('df3d','depot-container-probe',tostring(b.id),tostring(parent),tostring(offset),tostring(limit))
  if expect_ok then assert(code==0,text);return json.decode(text)end
  assert(code~=0,'Malformed/foreign contents request accepted')
 end
 local all=probe(id,0,64,true)
 assert(all.total==#initial_children and #all.items==#initial_children and all.appraisal==0)
 view:render(dfhack.getTickCount())
 for i,row in ipairs(all.items)do
  assert(row.id==initial_children[i].id and row.type==initial_children[i].type and row.value_caption=='')
  assert(row.contained_count==#children(df.item.find(row.id)))
  local native=dfhack.utf2df(row.caption);local chars={}
  local y=cell-menu.scroll_position_item+3*i+1
  assert(y<df.global.gps.dimy-5,'Child not visible for caption comparison')
  for x=54,54+#native-1 do chars[#chars+1]=string.char(dfhack.screen.readTile(x,y).ch)end
  assert(table.concat(chars)==native,'Native child caption differs: '..row.caption)
 end
 local offset=0
 while offset<all.total do
  local page=probe(id,offset,3,true);assert(page.total==all.total)
  assert(#page.items==math.min(3,all.total-offset))
  for i,row in ipairs(page.items)do assert(row.id==all.items[offset+i].id and row.caption==all.items[offset+i].caption and row.value==all.items[offset+i].value)end
  offset=offset+#page.items
 end
 assert(#probe(id,all.total,3,true).items==0)
 probe(id,all.total+1,3,false);probe(id,0,0,false);probe(id,0,65,false)
 probe(initial_children[1].id,0,3,false)
 result.provider={matched=all.total,pages=math.ceil(all.total/3),bounds_rejected=true,child_as_parent_rejected=true,items=all.items}
end
click(500,4+(cell-menu.scroll_position_item+3)*12+12)
sample('child-click')
assert(current().expanded_container and menu.i_height==initial_height+3*#initial_children,'Child row changed expansion')
-- Search/category changes must be observed, not assumed to reset expansion.
click(500,94);for byte in ('bin'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
sample('searched')
for i=1,3 do gui.simulateInput(view,'STRING_A000')end
sample('cleared-search')
select_type(df.item_type.ANVIL);select_type(df.item_type.BIN)
sample('returned-category')
assert(current().expanded_container,'Category navigation discarded container expansion')
menu.scroll_position_item=math.max(0,cell-12);view:render(dfhack.getTickCount())
click(500,4+(cell-menu.scroll_position_item)*12+12)
sample('restored')
assert(not current().expanded_container and menu.i_height==initial_height)
select_type(df.item_type.ANVIL)
-- Native category navigation retains search focus. Restore the initial focus
-- through its actual toggle before handing back to other picker checks.
if menu.entering_item_filter then click(500,94)end
assert(not menu.entering_item_filter)
return result
