-- df3d-smoke: boots into a fort hands-off, then unpauses.
--
-- Installed into <DF>/hack/scripts/ by tools/smoke/live_smoke.ps1 and run
-- from a dfhack-config/init/dfhackzzz_df3d_smoke.init file. Loads the
-- "Continue active game" slot (slot 0 = most recently played fort) via the
-- same title-screen click simulation DFHack's own CI harness uses
-- (external/dfhack/ci/test.lua) — the scripted load-save path is
-- unavailable in 53.x. Read-only intent: this lane never saves the game.
--@ module = false

local gui = require('gui')
local script = require('gui.script')

local function is_fortress()
    return dfhack.gui.matchFocusString('dwarfmode/Default')
end

local function wait_for(ms, desc, predicate)
    local start_ms = dfhack.getTickCount()
    local prev_ms = start_ms
    while not predicate() do
        script.sleep(10, 'frames')
        local now_ms = dfhack.getTickCount()
        if now_ms - start_ms > ms then
            qerror(('df3d-smoke: %s took too long (at %s)'):format(
                desc, dfhack.gui.getCurFocus(true)[1]))
        end
        if now_ms - prev_ms > 2000 then
            print(('df3d-smoke: waiting for %s...'):format(desc))
            prev_ms = now_ms
        end
    end
end

local function click_top_title_button(scr)
    local sw, sh = dfhack.screen.getWindowSize()
    df.global.gps.mouse_x = sw // 2
    df.global.gps.precise_mouse_x = df.global.gps.mouse_x * df.global.gps.tile_pixel_x
    if sh < 60 then
        df.global.gps.mouse_y = 25
    else
        df.global.gps.mouse_y = (sh // 2) + 3
    end
    df.global.gps.precise_mouse_y = df.global.gps.mouse_y * df.global.gps.tile_pixel_y
    gui.simulateInput(scr, '_MOUSE_L')
end

local function load_first_save(scr)
    if #scr.savegame_header == 0 then
        qerror('df3d-smoke: no savegames available to load')
    end
    print(('df3d-smoke: loading save "%s" (%s)'):format(
        scr.savegame_header[0].fort_name, scr.savegame_header[0].filename_noext))
    click_top_title_button(scr)
    wait_for(5000, 'world list', function() return scr.mode == 2 end)
    click_top_title_button(scr)
    wait_for(5000, 'savegame list', function() return scr.mode == 3 end)
    click_top_title_button(scr)
    wait_for(15000, 'loadgame progress', function()
        return dfhack.gui.matchFocusString('loadgame') or is_fortress()
    end)
end

script.start(function()
    print('df3d-smoke: starting hands-off fort load')
    for attempt = 1, 10 do
        if is_fortress() then
            print('df3d-smoke: fortress loaded; unpausing')
            dfhack.gui.resetDwarfmodeView(true)
            df.global.pause_state = false
            print('df3d-smoke: READY')
            return
        end
        local scr = dfhack.gui.getCurViewscreen()
        if dfhack.gui.matchFocusString('title/Default', scr) then
            load_first_save(scr)
        elseif not dfhack.gui.matchFocusString('loadgame', scr) then
            -- Not title, not loading: ESC toward somewhere recognizable.
            scr:feed_key(df.interface_key.LEAVESCREEN)
        end
        local prev_focus = dfhack.gui.getCurFocus()[1]
        wait_for(120000, 'screen change', function()
            return dfhack.gui.getCurFocus()[1] ~= prev_focus or is_fortress()
        end)
    end
    qerror('df3d-smoke: could not reach a loaded fortress')
end)
