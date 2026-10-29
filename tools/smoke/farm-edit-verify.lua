-- Verify effects after real wire requests; never apply the requested edit here.
local out,index=...
local json=require('json');local state=assert(_G.df3d_farm_read_fixture)
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
assert(request.op=='verify' or request.op=='external_change' or request.op=='mark_removal' or request.op=='clear_removal','unexpected edit verification')
assert(df.global.pause_state and df.global.world.frame_counter==state.frame,'edit advanced simulation')
assert(#request.seasons==4)
for season=0,3 do assert(state.farm.plant_id[season]==request.seasons[season+1],'wire edit/native selection mismatch')end
local function vector(values)local out={};for _,v in ipairs(values)do out[#out+1]=v end;return out end
assert(json.encode(vector(df.global.plotinfo.selected_farm_crops))==state.crops,'edit changed native crop menu')
assert(json.encode(vector(df.global.plotinfo.available_seeds))==state.seeds,'edit changed native seed menu')
assert(df.global.game.main_interface.view_sheets.active_sub_tab==state.tab,'edit changed native tab')
assert(df.global.game.main_interface.view_sheets.building_entering_nickname==state.editing and
 df.global.game.main_interface.view_sheets.building_entering_str==state.draft,'edit changed native rename scratch')
if request.op=='mark_removal' then
 assert(not dfhack.buildings.markedForRemoval(state.farm),'fixture already removing')
 dfhack.buildings.deconstruct(state.farm)
 assert(df.building.find(state.farm.id)==state.farm and dfhack.buildings.markedForRemoval(state.farm),'fixture did not stage removal')
elseif request.op=='clear_removal' then
 local jobs={};for _,job in ipairs(state.farm.jobs)do if job.job_type==df.job_type.DestroyBuilding then jobs[#jobs+1]=job end end
 assert(#jobs==1,'removal fixture changed');dfhack.job.removeJob(jobs[1])
 assert(not dfhack.buildings.markedForRemoval(state.farm),'removal fixture did not clear')
end
if request.op=='external_change' then
 assert(request.season~=df.global.cur_season,'external fixture requires future season')
 local text,code=dfhack.run_command_silent('df3d','farm-crop-set',tostring(state.farm.id),tostring(request.season),tostring(request.crop))
 assert(code==0 and json.decode(text).accepted,'external fixture edit refused')
end
local fertilizer
if request.fertilization then
 local f=request.fertilization;local farm=state.farm;local pending=0
 for _,job in ipairs(farm.jobs)do if job.job_type==df.job_type.FertilizeField then
  pending=pending+1;assert(dfhack.job.getHolder(job)==farm,'fertilizer holder differs')
 end end
 assert(farm.current_fertilization==f.current_fertilization and farm.max_fertilization==f.max_fertilization,'fertilizer progress differs')
 assert(farm.farm_flags.seasonal_fertilize==f.seasonal_fertilization and pending==f.pending_fertilization,'fertilizer intent/jobs differ')
 fertilizer={current=farm.current_fertilization,maximum=farm.max_fertilization,pending=pending,seasonal=farm.farm_flags.seasonal_fertilize}
end
local header
if request.name~=nil then
 assert(dfhack.df2utf(state.farm.name)==request.name,'wire rename/native name mismatch')
 local text,code=dfhack.run_command_silent('df3d','farm-header-read',tostring(state.farm.id))
 assert(code==0,text);header=json.decode(text)
 assert(header.custom_name==request.name,'header custom name differs')
end
local result={status='passed',selections=vector(state.farm.plant_id),native_menu_unchanged=true,fertilization=fertilizer,header=header}
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' farm edit effects and menu guards')
