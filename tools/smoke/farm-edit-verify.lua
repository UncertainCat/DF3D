-- Verify effects after real wire requests; never apply the requested edit here.
local out,index=...
local json=require('json');local state=assert(_G.df3d_farm_read_fixture)
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
assert(request.op=='verify','unexpected edit verification')
assert(df.global.pause_state and df.global.world.frame_counter==state.frame,'edit advanced simulation')
assert(#request.seasons==4)
for season=0,3 do assert(state.farm.plant_id[season]==request.seasons[season+1],'wire edit/native selection mismatch')end
local function vector(values)local out={};for _,v in ipairs(values)do out[#out+1]=v end;return out end
assert(json.encode(vector(df.global.plotinfo.selected_farm_crops))==state.crops,'edit changed native crop menu')
assert(json.encode(vector(df.global.plotinfo.available_seeds))==state.seeds,'edit changed native seed menu')
assert(df.global.game.main_interface.view_sheets.active_sub_tab==state.tab,'edit changed native tab')
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
local result={status='passed',selections=vector(state.farm.plant_id),native_menu_unchanged=true,fertilization=fertilizer}
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' farm edit effects and menu guards')
