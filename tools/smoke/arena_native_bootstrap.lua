-- Development-only helpers for an owned fresh object-testing arena.
-- All UI interactions target observed native labels; no persistent mod presets.
local M={}
local function rows()
    local out={};local w,h=dfhack.screen.getWindowSize()
    assert(w<=512 and h<=256,'Unexpected native window dimensions')
    for y=0,h-1 do
        local row={}
        for x=0,w-1 do local p=dfhack.screen.readTile(x,y);local c=p and p.ch or 32
            row[#row+1]=string.char(c>=32 and c<127 and c or 32)
        end
        out[#out+1]=table.concat(row)
    end
    return out
end
function M.state()
    local s=dfhack.gui.getDFViewscreen(true);local out={screen=tostring(s),focus=dfhack.gui.getFocusStrings(s),rows={}}
    for i,row in ipairs(rows()) do if row:find('%a') then out.rows[#out.rows+1]=('%d: %s'):format(i-1,row:gsub('%s+$','')) end end
    if df.viewscreen_new_arenast:is_instance(s) then
        out.mods=s.doing_mods;out.raw_load=s.raw_load;out.step=s.cur_step
        out.active_mods={};for _,id in ipairs(s.object_load_order_id) do out.active_mods[#out.active_mods+1]=id.value end
    end
    return out
end
local function find_label(label)
    local hit
    for i,row in ipairs(rows()) do
        local start=row:lower():find(label:lower(),1,true)
        if start then assert(not hit,'Ambiguous native button '..label);hit={x=start-1+#label//2,y=i-1} end
    end
    return hit
end
function M.visible(label)
    return find_label(label)~=nil
end
function M.click(label)
    local hit=assert(find_label(label),'Native button not visible: '..label)
    local g=df.global.gps;local old={g.mouse_x,g.mouse_y,g.precise_mouse_x,g.precise_mouse_y}
    g.mouse_x=hit.x;g.mouse_y=hit.y;g.precise_mouse_x=hit.x*g.tile_pixel_x;g.precise_mouse_y=hit.y*g.tile_pixel_y
    local ok,err=pcall(require('gui').simulateInput,dfhack.gui.getDFViewscreen(true),'_MOUSE_L')
    g.mouse_x,g.mouse_y,g.precise_mouse_x,g.precise_mouse_y=old[1],old[2],old[3],old[4]
    assert(ok,err)
end
return M
