-- Snapshot independent native-provider observations for the protected wire lane.
-- The enclosing lane owns the disposable save and closes without saving.
local out,observations=...
local json=require('json')
local function probe(...)
 local text,rc=dfhack.run_command_silent('df3d',...);assert(rc==0,text);return json.decode(text)
end
local expected={tabs={},knowledge=probe('pet-training-probe').rows}
local flags={}
local heading_reference
local heading_path=os.getenv('DF3D_PET_TRAINER_HEADING_REFERENCE')
if heading_path and heading_path~='' then
 local f=assert(io.open(heading_path));heading_reference=json.decode(f:read('*a'));f:close()
end
local heading_observed=false
for _,snapshot in ipairs(observations)do
 if snapshot.tab>0 and snapshot.query=='' and not expected.tabs[tostring(snapshot.tab)] then
  local rows={}
  for _,target in ipairs(snapshot.rows)do
   local row={kind=target.kind,id=target.id}
   if target.kind==0 then
    local unit=assert(df.unit.find(target.id));row.text=probe('creature-unit-row-read',tostring(target.id),'30',snapshot.tab==1 and '1' or '0')
    row.position={unit.pos.x,unit.pos.y,unit.pos.z}
    row.grazer=unit.enemy.caste_flags[df.caste_raw_flags.GRAZER]
   else
    row.text=probe('creature-item-row-read',tostring(target.id));row.position=row.text.position
    local item=assert(df.item.find(target.id));local raw=assert(df.global.world.raws.creatures.all[item:getMaterial()])
    local caste=item:getMaterialIndex()>=0 and raw.caste[item:getMaterialIndex()] or nil
    local graphics=caste and caste.caste_graphics or nil
    if not graphics or graphics.creature_small_texpos[0]==0 then graphics=raw.graphics end
    local tile=assert(graphics).creature_small_texpos[0];assert(tile>0,'Wire item fixture needs original selector art')
    for _,page in ipairs(df.global.texture.page)do
     for index,value in ipairs(page.texpos)do if value==tile then row.art={page=page.token,x=index%page.page_dim_x,y=index//page.page_dim_x};break end end
     if row.art then break end
    end
    assert(row.art,'Wire item selector page absent')
   end
   if snapshot.tab==1 then
    row.pet=probe('pet-edit-probe',tostring(target.kind),tostring(target.id))
    row.controls=probe('pet-controls-probe',tostring(target.kind),tostring(target.id))
    row.owners=probe('pet-controls-probe',tostring(target.kind),tostring(target.id),'owners')
    for _,action in ipairs(row.pet.actions)do if action==3 then
     assert(not df.training_assignment.find(target.id),'Trainer wire fixture requires no initial assignment')
     row.trainers=probe('pet-trainers-probe',tostring(target.id)).rows
     for _,candidate in ipairs(row.trainers)do candidate.grazer=assert(df.unit.find(candidate.id)).enemy.caste_flags[df.caste_raw_flags.GRAZER] end
     if heading_reference and heading_reference.id==target.id then row.trainer_header=heading_reference.header;heading_observed=true end
    end end
    local target_object=target.kind==0 and df.unit.find(target.id) or df.item.find(target.id)
    flags[#flags+1]={kind=target.kind,id=target.id,values=target.kind==0 and {target_object.flags1.whole,target_object.flags2.whole,target_object.flags3.whole} or {target_object.flags.whole,target_object.pet_flags.whole}}
   end
   rows[#rows+1]=row
  end
  expected.tabs[tostring(snapshot.tab)]=rows
 end
end
assert(not heading_reference or heading_observed,'Recorded trainer heading target missing')
local f=assert(io.open(out..'/creature-workflows-wire-reference.json','w'));f:write(json.encode(expected));f:close()
return function()
 for _,before in ipairs(flags)do
  local target=before.kind==0 and df.unit.find(before.id) or df.item.find(before.id)
  local after=before.kind==0 and {target.flags1.whole,target.flags2.whole,target.flags3.whole} or {target.flags.whole,target.pet_flags.whole}
  assert(json.encode(before.values)==json.encode(after),'Wire pet flags not restored '..before.id)
 end
 for _,row in ipairs(expected.tabs['1'])do if row.trainers then assert(not df.training_assignment.find(row.id),'Wire trainer assignment not restored')end end
end
