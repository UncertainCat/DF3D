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
elseif request.op~='final' then error('unknown farm verification operation')end
local f=assert(io.open(out..'/response-'..index..'.json','w'))
f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' farm read guards')
