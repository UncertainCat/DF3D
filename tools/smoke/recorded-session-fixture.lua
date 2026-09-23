-- Development fixture, restricted by recorded_session_smoke to its owned clone.
local output, mode, expected = ...
local json = require('json')
if mode == 'prepare' then
    df.global.pause_state = true
    df.global.d_init.feature.autosave = df.d_init_autosave.NONE
    local unit
    for _, u in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(u) then unit = u; break end
    end
    assert(unit, 'citizen required')
    local p = {x=unit.pos.x, y=unit.pos.y, z=unit.pos.z}
    local b = assert(dfhack.maps.getTileBlock(p))
    b.tiletype[p.x%16][p.y%16] = df.tiletype.StoneWall
    b.designation[p.x%16][p.y%16].whole = 0
    b.occupancy[p.x%16][p.y%16].whole = 0
    local f = assert(io.open(output..'/target.json', 'w'))
    f:write(json.encode({tile=p, unit_id=unit.id, df_version=dfhack.getDFVersion(), dfhack_version=dfhack.getDFHackVersion()})); f:close()
else
    local f = assert(io.open(output..'/target.json')); local target=json.decode(f:read('*a')); f:close()
    local p=target.tile; local b=assert(dfhack.maps.getTileBlock(p)); local x,y=p.x%16,p.y%16
    local priority=4000
    for _, e in ipairs(b.block_events) do
        if df.block_square_event_designation_priorityst:is_instance(e) then priority=e.priority[x][y]; break end
    end
    assert(b.designation[x][y].dig == df.tile_dig_designation.Default, 'native mining designation absent')
    assert(b.occupancy[x][y].dig_marked, 'native marker absent')
    assert(priority == tonumber(expected)*1000, 'native priority mismatch')
    assert(df.unit.find(target.unit_id), 'native unit identity missing')
    local receipt=assert(io.open(output..'/native-'..expected..'.json', 'w'))
    receipt:write(json.encode({priority=priority, marker=true, unit_id=target.unit_id, dig='Default'})); receipt:close()
end
