-- df3d-glyph-probe: helpers for tools/smoke/classic_glyph_probe.ps1 (the
-- classic tile and colour per item kind). Subcommands: kinds [n], pick,
-- center <i>, cell <i>, calib. See each branch below.
-- Read-only. Staged into hack/scripts by the lane.
--@ module = false

local world = df.global.world
local gps = df.global.gps
local function p(...) print(string.format(...)) end

local args = {...}
local cmd = args[1] or 'kinds'

local function mat_token(it)
    local mi = dfhack.matinfo.decode(it:getMaterial(), it:getMaterialIndex())
    return mi and mi:getToken() or '?'
end

local function color_text()
    local f, b = gps.screenf, gps.screenb
    return string.format('%s:%s:%d', tostring(f), tostring(b), gps.screenbright and 1 or 0)
end

if cmd == 'kinds' then
    local n = tonumber(args[2]) or 4
    local per = {}
    local order = {}
    for _, it in ipairs(world.items.other.IN_PLAY) do
        local t = it:getType()
        local e = per[t]
        if not e then
            e = {seen = {}, rows = {}, count = 0, tiles = {}}
            per[t] = e
            table.insert(order, t)
        end
        e.count = e.count + 1
        local key = string.format('%d|%s', it:getSubtype(), mat_token(it))
        -- Body components and remains carry no material: key them by race
        -- and corpse flags (their tile / colour comes from the creature).
        if t == df.item_type.CORPSE or t == df.item_type.CORPSEPIECE then
            key = string.format('%d|%s|%s', it.race, tostring(it.corpse_flags.bone), tostring(it.corpse_flags.rottable))
        elseif t == df.item_type.REMAINS or t == df.item_type.VERMIN or t == df.item_type.PET then
            key = string.format('%d', it.race)
        end
        if t == df.item_type.THREAD then key = key .. (it.flags.spider_web and '|web' or '') end
        if not e.seen[key] and #e.rows < n then
            e.seen[key] = true
            local ok, tile = pcall(function() return it:drawSelf() end)
            if not ok then tile = 'ERR ' .. tostring(tile) end
            gps.screenf, gps.screenb, gps.screenbright = 15, 15, false
            local ok2, err = pcall(function() it:setDisplayColor(0) end)
            local col = ok2 and color_text() or ('ERR ' .. tostring(err))
            local inv = it:hasInvertedTile() and 1 or 0
            local mi = dfhack.matinfo.decode(it:getMaterial(), it:getMaterialIndex())
            local mtxt = '-'
            if mi and mi.material then
                local m = mi.material
                mtxt = string.format('tile %d sym %d basic %d:%d', m.tile, m.item_symbol, m.basic_color[0], m.basic_color[1])
            end
            local sub = it:getSubtype()
            local def = sub >= 0 and dfhack.items.getSubtypeDef(t, sub) or nil
            local subid = def and def.id or (sub >= 0 and tostring(sub) or '-')
            if t == df.item_type.CORPSE or t == df.item_type.CORPSEPIECE or t == df.item_type.REMAINS
               or t == df.item_type.VERMIN or t == df.item_type.PET then
                local raw = world.raws.creatures.all[it.race]
                if raw then
                    mtxt = string.format('creature %s tile %d color %d:%d:%d', raw.creature_id, raw.creature_tile,
                        raw.color[0], raw.color[1], raw.color[2])
                    if t ~= df.item_type.REMAINS and t ~= df.item_type.VERMIN and t ~= df.item_type.PET then
                        local lt = dfhack.matinfo.decode(it.largest_tissue.mat_type, it.largest_tissue.mat_index)
                        mtxt = mtxt .. string.format('; tissue %s basic %s', lt and lt:getToken() or '?',
                            lt and lt.material and (lt.material.basic_color[0] .. ':' .. lt.material.basic_color[1]) or '?')
                        subid = (it.corpse_flags.bone and 'bone' or '-') .. (it.corpse_flags.rottable and ',rottable' or '')
                    end
                end
            end
            if t == df.item_type.THREAD and it.flags.spider_web then subid = 'web' end
            table.insert(e.rows, string.format('    id %-7d sub %-28s mat %-34s tile %-4s color %-8s inv %d  (%s)',
                it.id, subid, mat_token(it), tostring(tile), col, inv, mtxt))
            if type(tile) == 'number' then e.tiles[tile] = (e.tiles[tile] or 0) + 1 end
        end
    end
    table.sort(order)
    p('item kinds present: %d (tile = item::drawSelf / getsymbol; color = gps after item::setDisplayColor(0), fg:bg:bright)', #order)
    for _, t in ipairs(order) do
        local e = per[t]
        local tiles = {}
        for tile, c in pairs(e.tiles) do table.insert(tiles, tile .. 'x' .. c) end
        table.sort(tiles)
        p('%-20s (%d items) tiles %s', df.item_type[t], e.count, table.concat(tiles, ' '))
        for _, r in ipairs(e.rows) do print(r) end
    end
    -- What getMaterial() returns for corpses and pieces (item_body_component
    -- has no mat fields).
    local shown = 0
    for _, it in ipairs(world.items.other.IN_PLAY) do
        local t = it:getType()
        if (t == df.item_type.CORPSE or t == df.item_type.CORPSEPIECE) and shown < 4 then
            shown = shown + 1
            local lt = it.largest_tissue
            local mi = dfhack.matinfo.decode(lt.mat_type, lt.mat_index)
            p('corpse-material item %d %s getMaterial %d/%d largest_tissue %d/%d = %s', it.id, df.item_type[t],
                it:getMaterial(), it:getMaterialIndex(), lt.mat_type, lt.mat_index, mi and mi:getToken() or '?')
        end
    end
elseif cmd == 'pick' then
    local occupied = {}
    local function k(x, y, z) return x .. ',' .. y .. ',' .. z end
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground then
            local kk = k(it.pos.x, it.pos.y, it.pos.z)
            occupied[kk] = (occupied[kk] or 0) + 1
        end
    end
    local picks, seen = {}, {}
    for _, it in ipairs(world.items.other.IN_PLAY) do
        local t = it:getType()
        if it.flags.on_ground and not seen[t] then
            local kk = k(it.pos.x, it.pos.y, it.pos.z)
            local pos = xyz2pos(it.pos.x, it.pos.y, it.pos.z)
            if occupied[kk] == 1 and not dfhack.units.getUnitsInBox(pos, pos)[1]
               and not dfhack.buildings.findAtTile(pos) then
                seen[t] = true
                table.insert(picks, {id = it.id, t = t, x = it.pos.x, y = it.pos.y, z = it.pos.z})
            end
        end
    end
    table.sort(picks, function(a, b) return a.t < b.t end)
    for i, pk in ipairs(picks) do
        p('pick %d: %-18s item %d at %d,%d,%d', i - 1, df.item_type[pk.t], pk.id, pk.x, pk.y, pk.z)
    end
    _G.df3d_glyph_picks = picks
elseif cmd == 'center' then
    local i = (tonumber(args[2]) or 0) + 1
    local pk = (_G.df3d_glyph_picks or {})[i]
    if not pk then p('no pick %d (run `pick` first)', i - 1) return end
    dfhack.gui.revealInDwarfmodeMap(xyz2pos(pk.x, pk.y, pk.z), true)
    p('centered on %d,%d,%d (%s item %d)', pk.x, pk.y, pk.z, df.item_type[pk.t], pk.id)
elseif cmd == 'cell' or cmd == 'calib' then
    local x, y, z, what
    if cmd == 'cell' then
        local i = (tonumber(args[2]) or 0) + 1
        local pk = (_G.df3d_glyph_picks or {})[i]
        if not pk then p('no pick %d (run `pick` first)', i - 1) return end
        x, y, z, what = pk.x, pk.y, pk.z, string.format('%s item %d', df.item_type[pk.t], pk.id)
    else
        local wz = df.global.window_z
        for _, u in ipairs(world.units.active) do
            if u.pos.z == wz and not u.flags1.caged and not u.flags1.inactive then
                local raw = world.raws.creatures.all[u.race]
                x, y, z = u.pos.x, u.pos.y, u.pos.z
                what = string.format('unit %d %s (creature_tile %d color %d:%d:%d)', u.id, raw.creature_id,
                    raw.creature_tile, raw.color[0], raw.color[1], raw.color[2])
                dfhack.gui.revealInDwarfmodeMap(xyz2pos(x, y, z), true)
                break
            end
        end
        if not x then p('calib: no unit at the view z') return end
    end
    local vp = gps.main_viewport
    local wx, wy, wz = df.global.window_x, df.global.window_y, df.global.window_z
    local vx, vy = x - wx, y - wy
    local ascii = not df.global.init.display.flag.USE_GRAPHICS
    p('%s at %d,%d,%d; window %d,%d,%d; viewport dim %dx%d screen %d,%d; gps %dx%d; use_old_16 %s; classic ascii %s',
        what, x, y, z, wx, wy, wz, vp.dim_x, vp.dim_y, vp.screen_x, vp.screen_y, gps.dimx, gps.dimy,
        tostring(gps.use_old_16_colors), tostring(ascii))
    -- In classic ASCII mode the viewport struct is stale (25x17 on a 150x66
    -- screen): the map is drawn straight into gps.screen at the window
    -- offset, so only the window bounds it.
    local dimx, dimy = vp.dim_x, vp.dim_y
    if ascii then dimx, dimy = gps.dimx, gps.dimy end
    if z ~= wz or vx < 0 or vy < 0 or vx >= dimx or vy >= dimy then
        p('  not in the viewport at the current z')
        return
    end
    local idx = vx * vp.dim_y + vy
    if ascii then idx = -1 end
    -- Decode a texpos through the curses font: init.font.large_font_texpos[ch].
    local font = df.global.init.font
    local function decode(tex)
        if not tex or tex <= 0 then return '-' end
        for c = 0, 255 do
            if font.large_font_texpos[c] == tex then return string.format('%d (font char)', c) end
        end
        return tostring(tex) .. ' (not a font char)'
    end
    if idx >= 0 then
        p('  viewport texpos: item %s | background %s | background_two %s | creature %s | building_one %s',
            decode(vp.screentexpos_item[idx]), decode(vp.screentexpos_background[idx]),
            decode(vp.screentexpos_background_two[idx]), decode(vp.screentexpos[idx]),
            decode(vp.screentexpos_building_one[idx]))
    end
    -- The character cell at the window offset (classic ASCII mode draws the
    -- map into gps.screen), plus its 8 neighbours for a sanity check of
    -- the offset; the calib read on a unit (creature tile 1) validates it.
    local sx, sy = vx, vy
    if not ascii then sx, sy = vp.screen_x + vx, vp.screen_y + vy end
    for dy = -1, 1 do
        local row = {}
        for dx = -1, 1 do
            local pen = dfhack.screen.readTile(sx + dx, sy + dy, false)
            if pen then
                table.insert(row, string.format('[%3d %2d:%2d:%d t%d]', pen.ch or -1, pen.fg or -1, pen.bg or -1,
                    pen.bold and 1 or 0, pen.tile or 0))
            else
                table.insert(row, '[   none    ]')
            end
        end
        p('  screen (%d,%d)%s: %s', sx, sy + dy, dy == 0 and ' <-' or '   ', table.concat(row, ' '))
    end
else
    p('usage: df3d-glyph-probe kinds [n] | pick | center <i> | cell <i> | calib')
end
