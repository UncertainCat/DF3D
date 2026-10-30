local out,index=...
local json=require('json');local state=assert(_G.df3d_farm_read_fixture)
local input=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(input:read('*a'));input:close()
local result={status='passed',selections_unchanged=true,menu_vectors_unchanged=true,tab_unchanged=true}
assert(df.global.pause_state and df.global.world.frame_counter==state.frame,'read advanced simulation')
for season=0,3 do assert(state.farm.plant_id[season]==(state.expected or state.seasons)[season+1],'read changed seasonal selection')end
local function vector(values)local out={};for _,v in ipairs(values)do out[#out+1]=v end;return out end
assert(json.encode(vector(df.global.plotinfo.selected_farm_crops))==state.crops,'read changed native crop menu')
assert(json.encode(vector(df.global.plotinfo.available_seeds))==state.seeds,'read changed native seed menu')
assert(df.global.game.main_interface.view_sheets.active_sub_tab==state.tab,'read changed native tab')
if request.op=='change' or request.op=='restore' then
 assert(df.global.cur_season~=0,'revision fixture requires future spring')
 local crop=state.seasons[1]
 if request.op=='change' then
  if crop>=0 then crop=-1 else
   local text,code=dfhack.run_command_silent('df3d','farm-choices-read',tostring(state.farm.id),'0')
   assert(code==0,text);crop=assert(json.decode(text).rows[1]).crop_id
  end
 end
 local text,code=dfhack.run_command_silent('df3d','farm-crop-set',tostring(state.farm.id),'0',tostring(crop))
 assert(code==0 and json.decode(text).accepted,'controlled seasonal change refused')
 state.expected={table.unpack(state.seasons)};state.expected[1]=crop;result.crop=crop
elseif request.op=='header-change' or request.op=='header-restore' then
 state.farm.name=request.op=='header-change' and 'wire farm' or state.name
 local text,code=dfhack.run_command_silent('df3d','farm-header-read',tostring(state.farm.id));assert(code==0,text);result.header=json.decode(text)
elseif request.op=='item-cold' then
 local item=assert(df.item.find(request.item_id));assert(item:getType()==df.item_type.SEEDS)
 item.flags.weight_computed=false;item.weight.whole=0;item.weight.fraction=0
elseif request.op=='item-position-state' then
 local item=assert(df.item.find(request.item_id));local c=assert(_G.df3d_contents_fixture)
 if not c.position_original then
  local block=assert(dfhack.maps.getTileBlock(item.pos));local designation=block.designation[item.pos.x%16][item.pos.y%16]
  c.position_original={item=item,flags=item.flags.whole,x=item.pos.x,y=item.pos.y,z=item.pos.z,designation=designation,bits=designation.whole}
 end
 local old=c.position_original;assert(old.item==item,'position fixture target changed')
 if request.state=='moved' then item.pos.x=old.x+1;item.pos.y=old.y-1
 elseif request.state=='removed' then item.flags.removed=true
 elseif request.state=='item-hidden' then item.flags.hidden=true
 elseif request.state=='terrain-hidden' then old.designation.hidden=true
 elseif request.state=='restored' then
  item.flags.whole=old.flags;item.pos.x=old.x;item.pos.y=old.y;item.pos.z=old.z;old.designation.whole=old.bits;c.position_original=nil
 else error('unknown position fixture state')end
elseif request.op=='item-position' then
 local text,code=dfhack.run_command_silent('df3d','item-position-probe',string.format('%d',request.item_id));assert(code==0,text)
 local native=json.decode(text)
 assert(native.valid and native.item_id==request.item_id and native.x==request.x and native.y==request.y and native.z==request.z,'wire item position differs from native resolver')
 for _,guard in ipairs(_G.df3d_contents_guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'position read changed UI scratch')end
 result.item_position_equal=true;result.ui_scratch_unchanged=true
elseif request.op=='item-inspect' then
 local observed=request.item
 if request.independent then
  local text,code=dfhack.run_command_silent('df3d','item-inspect-probe',string.format('%d',observed.id));assert(code==0,text)
  local native=json.decode(text).snapshot
  assert(native.revision==request.revision_text,'independent revision differs')
  assert(native.caption==observed.name and native.weight==observed.weight and native.description==observed.description,'independent native text differs')
  for _,key in ipairs{'item_type','material_token','forbid','dump','melt','hidden','can_dump','can_melt'}do assert(native[key]==observed[key],'independent facts differ: '..key)end
  for _,key in ipairs{'holder','stockpile'}do
   local link=native[key];local actual=observed[key]
   if link and link~=json.null then assert(actual and actual.id==link.id and actual.type==link.type and actual.name==link.name,'independent link differs')else assert(not actual or actual==json.null,'invented independent link')end
  end
 else
 local text,code=dfhack.run_command_silent('df3d','farm-item-description-probe',tostring(assert(_G.df3d_contents_fixture).farm.id),string.format('%d',observed.id));assert(code==0,text)
 local native=json.decode(text)
 assert(native.contents_revision==request.revision_text,'item inspection revision differs')
 assert(native.caption==observed.name and native.weight==observed.weight and native.description==observed.description,'item inspection native text differs')
 assert(native.building_id==observed.building_id and native.completed==observed.completed and native.removing==observed.removing,'item inspection building facts differ')
 for _,key in ipairs{'item_type','material_token','subtype_raw','forbid','dump','melt','hidden','can_dump','can_melt'}do assert(native.facts[key]==observed[key],'item inspection facts differ: '..key)end
 if native.holder then assert(observed.holder and observed.holder.id==native.holder.building_id and observed.holder.type==native.holder.building_type and observed.holder.name==native.holder.name,'item inspection holder differs')else assert(not observed.holder,'invented item holder')end
 end
 for _,guard in ipairs(_G.df3d_contents_guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'inspection changed UI scratch')end
 result.item_inspection_equal=true;result.ui_scratch_unchanged=true
elseif request.op=='contents-verify' then
 local c=assert(_G.df3d_contents_fixture)
 local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(c.farm.id));assert(code==0,text)
 local actual=json.decode(text);local cursor=request.cursor or 0
 assert(cursor>=0 and cursor%1==0 and cursor<=#actual.rows,'invalid verification cursor')
 assert(#actual.rows-cursor==#request.rows,'contents size differs')
 for index,row in ipairs(request.rows)do
  local live=actual.rows[index+cursor];local item=c.farm.contained_items[index+cursor-1].item
  assert(row.id==live.id and row.role==live.role_value and row.name==live.name,'contents receipt identity/name differs')
  for _,key in ipairs{'forbid','dump','melt','hidden','in_job','in_building'}do assert(row[key]==item.flags[key],'contents receipt flag differs: '..key)end
  assert(row.can_dump==live.can_dump and row.can_melt==live.can_melt,'contents eligibility differs')
  local material=dfhack.matinfo.decode(item:getMaterial(),item:getMaterialIndex())
  local subtype=dfhack.items.getSubtypeDef(item:getType(),item:getSubtype())
  assert(row.item_type==item:getType() and row.material_token==(material and dfhack.df2utf(material:getToken()) or '') and row.subtype_raw==(subtype and dfhack.df2utf(subtype.id) or ''),'contents semantic item identity differs')
 end
 for _,guard in ipairs(_G.df3d_contents_guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'contents edit changed UI scratch')end
 result.native_contents_equal=true;result.ui_scratch_unchanged=true
elseif request.op=='contents-change'  or request.op=='contents-restore' then
 local c=assert(_G.df3d_contents_fixture)
 local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(c.farm.id));assert(code==0,text)
 local revision=json.decode(text).revision
 local desired=request.op=='contents-change' and not c.hidden or c.hidden
 -- Explicit branch avoids Lua's false-valued ternary pitfall.
 if request.op=='contents-change' then desired=not c.hidden end
 text,code=dfhack.run_command_silent('df3d','farm-item-edit',tostring(c.farm.id),tostring(c.item.id),'hidden',desired and '1' or '0',revision)
 assert(code==0 and json.decode(text).outcome=='completed',text)
 result.contents_revision=json.decode(text).revision
elseif request.op~='final'  then error('unknown farm verification operation')end
if request.op=='final' then assert(state.farm.name==state.name,'read fixture name not restored');local c=_G.df3d_contents_fixture;assert(c.item.flags.hidden==c.hidden,'contents not restored');assert(not c.position_original,'position fixture not restored')end
local f=assert(io.open(out..'/response-'..index..'.json','w'))
f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' farm read guards')
