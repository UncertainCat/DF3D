-- Owned-lane development bootstrap: native object-testing arena, no saved world.
-- Invoke with output status JSON. Poll ready/error; bounded to 60 seconds.
local output=assert((...),'Expected status JSON path')
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local native=assert(loadfile(directory..'arena_native_bootstrap.lua'))()
local json=require('json')
local state={phase='title',ready=false,started_ms=dfhack.getTickCount()}
local previous_status
local function write()
    local encoded=json.encode(state)
    if encoded==previous_status then return end
    local f=assert(io.open(output,'w'));f:write(encoded);f:close();previous_status=encoded
end
local function loaded()
    assert(dfhack.world.isArena(),'Expected native object-testing arena')
    local found=false
    for _,raw in ipairs(df.global.world.raws.creatures.all) do
        if raw.creature_id=='CRETACEOUS_TYRANNOSAURUS' then found=true;break end
    end
    assert(found,'Native arena did not load official extinct creatures')
    df.global.pause_state=true
    dfhack.run_command('enable','df3d')
    local x,y,z=dfhack.maps.getTileSize()
    state.phase='ready';state.ready=true;state.paused=true;state.map={x=x,y=y,z=z}
end
local function step()
    assert(dfhack.getTickCount()-state.started_ms<60000,'Native arena bootstrap timed out')
    local screen=dfhack.gui.getDFViewscreen(true)
    if dfhack.isMapLoaded() then loaded();return end
    if state.phase=='title' and df.viewscreen_titlest:is_instance(screen)
        and native.visible('Object testing arena') then
        native.click('Object testing arena');state.phase='profile'
    elseif state.phase=='profile' and df.viewscreen_new_arenast:is_instance(screen)
        and native.visible('Small arena') then
        local mods={};for _,id in ipairs(screen.object_load_order_id) do mods[id.value]=true end
        assert(mods.vanilla_creatures_extinct and mods.vanilla_creatures_extinct_graphics,
            'Official extinct creature and graphic packs missing from native arena defaults')
        native.click('Small arena');state.phase='create'
    elseif state.phase=='create' and df.viewscreen_new_arenast:is_instance(screen)
        and native.visible('Create arena') then
        native.click('Create arena');state.phase='loading'
    end
end
local function advance()
    local ok,err=xpcall(step,debug.traceback)
    if not ok then state.error=err;state.phase='error';write();return end
    write()
    if not state.ready then dfhack.timeout(3,'frames',advance) end
end
write();dfhack.timeout(3,'frames',advance)
print('ARENA_BOOTSTRAP_STARTED')
