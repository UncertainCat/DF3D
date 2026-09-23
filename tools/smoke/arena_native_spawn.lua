-- Development capture helper ONLY: current DF native arena creature creation.
-- Never call from product UI/runtime. DF creates the actual body/soul/graphics.
local M={}
function M.begin()
    local session={gamemode=df.global.gamemode,gametype=df.global.gametype,
        window={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z}}
    dfhack.run_script('gui/sandbox')
    session.sandbox=dfhack.script_environment('gui/sandbox')
    if not session.sandbox.view then
        session.sandbox.view=session.sandbox.SandboxScreen{}:show()
    end
    session.owner=dfhack.gui.getDFViewscreen(true)
    return session
end
function M.spawn(session,token,pos,team)
    local race
    for i,raw in ipairs(df.global.world.raws.creatures.all) do if raw.creature_id==token then race=i; break end end
    assert(race,'Creature raw not loaded in this world: '..token)
    local gui=require('gui')
    gui.simulateInput(session.owner,'ARENA_CREATE_CREATURE')
    local interface=df.global.game.main_interface.arena_unit
    assert(interface.open,'Native arena creature selector did not open')
    interface.race=race; interface.caste=0; interface.team=team or 1
    interface.interaction=-1; interface.tame=false
    for _,name in ipairs({'skills','skill_levels','equipment_item_type','equipment_item_subtype',
        'equipment_mat_type','equipment_mat_index','equipment_quantity'}) do interface[name]:resize(0) end
    gui.simulateInput(session.owner,'SELECT')
    assert(not interface.open,'Native arena creature selection not accepted')
    dfhack.gui.revealInDwarfmodeMap(pos,true)
    local g=df.global.gps
    local old={g.mouse_x,g.mouse_y,g.precise_mouse_x,g.precise_mouse_y,df.global.enabler.tracking_on}
    local scale=g.viewport_zoom_factor/4
    g.precise_mouse_x=math.floor((pos.x-df.global.window_x+.5)*scale)
    g.precise_mouse_y=math.floor((pos.y-df.global.window_y+.5)*scale)
    g.mouse_x=math.floor(g.precise_mouse_x/g.tile_pixel_x)
    g.mouse_y=math.floor(g.precise_mouse_y/g.tile_pixel_y)
    df.global.enabler.tracking_on=1
    local id=df.global.unit_next_id
    local ok,err=pcall(gui.simulateInput,session.owner,'_MOUSE_L')
    g.mouse_x,g.mouse_y,g.precise_mouse_x,g.precise_mouse_y=old[1],old[2],old[3],old[4]
    df.global.enabler.tracking_on=old[5]
    assert(ok,err)
    local unit=df.unit.find(id)
    assert(unit and unit.race==race and df.global.unit_next_id==id+1,'Native creature placement failed')
    return unit
end
function M.finish(session)
    df.global.game.main_interface.arena_unit.open=false
    df.global.game.main_interface.bottom_mode_selected=-1
    if session.sandbox.view then session.sandbox.view:dismiss() end
    df.global.gamemode=session.gamemode; df.global.gametype=session.gametype
    df.global.window_x,df.global.window_y,df.global.window_z=session.window.x,session.window.y,session.window.z
end
return M
