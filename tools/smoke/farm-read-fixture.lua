-- Protected paused clone, read-only farm reference for the real wire consumer.
local out=...
local json=require('json')
assert(df.global.pause_state)
df.global.d_init.feature.autosave=df.d_init_autosave.NONE
local farm=assert(df.global.world.buildings.other.FARM_PLOT[0])
local function vector(values)local out={};for _,v in ipairs(values)do out[#out+1]=v end;return out end
local state={id=farm.id,current_season=df.global.cur_season,seasons={},choices={},
 nonfarm=assert(df.global.world.buildings.other.STOCKPILE[0]).id}
for season=0,3 do
 state.seasons[#state.seasons+1]=farm.plant_id[season]
 local text,code=dfhack.run_command_silent('df3d','farm-choices-read',tostring(farm.id),tostring(season))
 assert(code==0,text);local rows=json.decode(text).rows
 for _,row in ipairs(rows)do row.raw_id=assert(df.plant_raw.find(row.crop_id)).id end
 state.choices[#state.choices+1]=rows
end
_G.df3d_farm_read_fixture={farm=farm,seasons=state.seasons,frame=df.global.world.frame_counter,
 crops=json.encode(vector(df.global.plotinfo.selected_farm_crops)),seeds=json.encode(vector(df.global.plotinfo.available_seeds)),
 tab=df.global.game.main_interface.view_sheets.active_sub_tab}
local f=assert(io.open(out..'/fixture.json','w'));f:write(json.encode(state));f:close()
print('FIXTURE_READY')
