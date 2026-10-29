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
elseif request.op=='contents-verify' then
 local c=assert(_G.df3d_contents_fixture)
 local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(c.farm.id));assert(code==0,text)
 local actual=json.decode(text);assert(#actual.rows==#request.rows,'contents size differs')
 for index,row in ipairs(request.rows)do
  local live=actual.rows[index];local item=c.farm.contained_items[index-1].item
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
if request.op=='final' then assert(state.farm.name==state.name,'read fixture name not restored');local c=_G.df3d_contents_fixture;assert(c.item.flags.hidden==c.hidden,'contents not restored')end
local f=assert(io.open(out..'/response-'..index..'.json','w'))
f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' farm read guards')
