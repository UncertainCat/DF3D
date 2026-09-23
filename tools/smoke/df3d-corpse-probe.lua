-- df3d-corpse-probe: helpers for tools/smoke/corpse_probe.ps1. Subcommands:
-- levels <n>, center <i>, lone [i], lonepiece [i], kill, killed [i], pieces,
-- glyphs. See each branch below.
-- Read-only. Staged into hack/scripts by the lane.
--@ module = false

local world = df.global.world
local function p(...) print(string.format(...)) end

local args = {...}
local cmd = args[1] or 'levels'

local function is_corpse(it)
    local t = it:getType()
    return t == df.item_type.CORPSE or t == df.item_type.CORPSEPIECE
end

local function flags_text(cf)
    local names = {'unbutchered','plant','silk','leather','bone','shell','wood','soap','tooth','horn',
                   'pearl','rottable','skull','use_blood_color','hair_wool','yarn','must_rot_body','must_refresh_texture'}
    local out = {}
    for _, n in ipairs(names) do if cf[n] then table.insert(out, n) end end
    return #out == 0 and '-' or table.concat(out, ',')
end

if cmd == 'levels' then
    local n = tonumber(args[2]) or 3
    local byz = {}
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground and is_corpse(it) then
            local z = it.pos.z
            local e = byz[z] or {count = 0, sx = 0, sy = 0, whole = 0}
            e.count = e.count + 1
            e.sx = e.sx + it.pos.x
            e.sy = e.sy + it.pos.y
            if it:getType() == df.item_type.CORPSE then e.whole = e.whole + 1 end
            byz[z] = e
        end
    end
    local list = {}
    for z, e in pairs(byz) do table.insert(list, {z = z, count = e.count, whole = e.whole, cx = e.sx // e.count, cy = e.sy // e.count}) end
    table.sort(list, function(a, b) return a.count > b.count end)
    local keep = {}
    for i = 1, math.min(n, #list) do
        local l = list[i]
        p('level %d: z %d corpse items %d (whole %d) centroid %d,%d', i - 1, l.z, l.count, l.whole, l.cx, l.cy)
        table.insert(keep, l)
    end
    dfhack.persistent = dfhack.persistent  -- no-op; state lives in a global for the session
    _G.df3d_corpse_levels = keep
elseif cmd == 'center' then
    local i = (tonumber(args[2]) or 0) + 1
    local levels = _G.df3d_corpse_levels or {}
    local l = levels[i]
    if not l then p('no level %d (run `levels` first)', i - 1) return end
    -- Center on the corpse nearest the centroid so the cell is a corpse tile.
    local best, bd = nil, 1e9
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground and is_corpse(it) and it.pos.z == l.z then
            local d = math.abs(it.pos.x - l.cx) + math.abs(it.pos.y - l.cy)
            if d < bd then best, bd = it, d end
        end
    end
    local pos = best and xyz2pos(best.pos.x, best.pos.y, best.pos.z) or xyz2pos(l.cx, l.cy, l.z)
    dfhack.gui.revealInDwarfmodeMap(pos, true)
    p('centered on %d,%d,%d (item %s)', pos.x, pos.y, pos.z, best and best.id or 'none')
elseif cmd == 'lone' then
    -- Whole corpses alone on their tile (no other on-ground item, so the
    -- viewport cell shows them): list them, fresh (rottable) ones first,
    -- and center on the i-th.
    local i = tonumber(args[2])
    local occupied = {}
    local function key(pos) return pos.x .. ',' .. pos.y .. ',' .. pos.z end
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground then occupied[key(it.pos)] = (occupied[key(it.pos)] or 0) + 1 end
    end
    local list = {}
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground and it:getType() == df.item_type.CORPSE and occupied[key(it.pos)] == 1 then
            local raw = world.raws.creatures.all[it.race]
            table.insert(list, {it = it, race = raw and raw.creature_id or '?', fresh = it.corpse_flags.rottable and 1 or 0})
        end
    end
    table.sort(list, function(a, b)
        if a.fresh ~= b.fresh then return a.fresh > b.fresh end
        return a.it.id < b.it.id
    end)
    if not i then
        p('lone whole corpses: %d (fresh first)', #list)
        for j = 1, math.min(#list, 40) do
            local e = list[j]
            p('lone %d: item %d %s at %d,%d,%d flags %s', j - 1, e.it.id, e.race, e.it.pos.x, e.it.pos.y, e.it.pos.z, flags_text(e.it.corpse_flags))
        end
    else
        local e = list[i + 1]
        if not e then p('no lone corpse %d', i) return end
        local pos = xyz2pos(e.it.pos.x, e.it.pos.y, e.it.pos.z)
        dfhack.gui.revealInDwarfmodeMap(pos, true)
        p('centered on %d,%d,%d (item %d %s flags %s)', pos.x, pos.y, pos.z, e.it.id, e.race, flags_text(e.it.corpse_flags))
    end
elseif cmd == 'lonepiece' then
    -- Corpse pieces alone on their tile, one per (corpse flags, tissue)
    -- group: list the groups, or center on the i-th group's sample.
    local i = tonumber(args[2])
    local occupied = {}
    local function key(pos) return pos.x .. ',' .. pos.y .. ',' .. pos.z end
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground then occupied[key(it.pos)] = (occupied[key(it.pos)] or 0) + 1 end
    end
    local groups, order = {}, {}
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground and it:getType() == df.item_type.CORPSEPIECE and occupied[key(it.pos)] == 1 then
            local mi = dfhack.matinfo.decode(it.largest_tissue.mat_type, it.largest_tissue.mat_index)
            local tok = mi and mi:getToken() or '?'
            local tissue = tok:match('^CREATURE:[^:]+:(.*)$') or tok
            local g = flags_text(it.corpse_flags) .. ' / ' .. tissue
            if not groups[g] then
                groups[g] = {it = it, tissue = tissue, count = 0}
                table.insert(order, g)
            end
            groups[g].count = groups[g].count + 1
        end
    end
    table.sort(order)
    if not i then
        p('lone corpse-piece groups (flags / tissue): %d', #order)
        for j, g in ipairs(order) do
            local e = groups[g]
            local raw = world.raws.creatures.all[e.it.race]
            p('lonepiece %d: %-44s x%-3d e.g. item %d %s at %d,%d,%d', j - 1, g, e.count, e.it.id, raw and raw.creature_id or '?',
              e.it.pos.x, e.it.pos.y, e.it.pos.z)
        end
    else
        local g = order[i + 1]
        if not g then p('no lone piece group %d', i) return end
        local e = groups[g]
        local pos = xyz2pos(e.it.pos.x, e.it.pos.y, e.it.pos.z)
        dfhack.gui.revealInDwarfmodeMap(pos, true)
        p('centered on %d,%d,%d (item %d, group %s)', pos.x, pos.y, pos.z, e.it.id, g)
    end
elseif cmd == 'kill' then
    -- Make fresh corpses for the oracle (the lane never saves): one citizen
    -- dwarf (a layered CORPSE set) and one animal (a simple CORPSE sprite),
    -- each standing on a tile with no items, bled out the way
    -- exterminate.lua does (blood_count = 0; no vanish countdown, we want
    -- the corpse).
    local occupied = {}
    local function key(pos) return pos.x .. ',' .. pos.y .. ',' .. pos.z end
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground then occupied[key(it.pos)] = true end
    end
    local picked, ids = {dwarf = nil, animal = nil}, {}
    for _, u in ipairs(world.units.active) do
        if not u.flags1.caged and not u.flags1.inactive and not u.flags2.killed and not u.flags1.chained
           and u.pos.x >= 0 and not occupied[key(u.pos)] and not dfhack.buildings.findAtTile(xyz2pos(u.pos.x, u.pos.y, u.pos.z)) then
            local raw = world.raws.creatures.all[u.race]
            if not picked.dwarf and dfhack.units.isCitizen(u) and raw.creature_id == 'DWARF' and dfhack.units.isAdult(u) then
                picked.dwarf = u
            elseif not picked.animal and dfhack.units.isAnimal(u) and dfhack.units.isTame(u) and raw.creature_id ~= 'DWARF' then
                picked.animal = u
            end
        end
    end
    for _, k in ipairs({'dwarf', 'animal'}) do
        local u = picked[k]
        if u then
            local raw = world.raws.creatures.all[u.race]
            u.body.blood_count = 0
            table.insert(ids, u.id)
            p('kill %s: unit %d %s (%s) at %d,%d,%d blood 0/%d', k, u.id, raw.creature_id, dfhack.units.getReadableName(u),
              u.pos.x, u.pos.y, u.pos.z, u.body.blood_max)
        else
            p('kill %s: no suitable unit', k)
        end
    end
    _G.df3d_kill_ids = ids
elseif cmd == 'killed' then
    local i = tonumber(args[2])
    local ids = _G.df3d_kill_ids or {}
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    local list = {}
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it:getType() == df.item_type.CORPSE and want[it.unit_id] then table.insert(list, it) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    if not i then
        for j, it in ipairs(list) do
            it.flags.forbid = true  -- keep haulers off it (never saved)
            local raw = world.raws.creatures.all[it.race]
            local u = df.unit.find(it.unit_id)
            p('killed %d: corpse item %d %s of unit %d at %d,%d,%d on_ground %s flags %s rot_timer %d (unit %s)', j - 1, it.id,
              raw and raw.creature_id or '?', it.unit_id, it.pos.x, it.pos.y, it.pos.z, tostring(it.flags.on_ground),
              flags_text(it.corpse_flags), it.rot_timer, u and (u.flags2.killed and 'killed' or 'alive?') or 'gone')
        end
        if #list == 0 then p('killed: no corpse yet for units %s', table.concat(ids, ',')) end
    else
        local it = list[i + 1]
        if not it then p('no killed corpse %d', i) return end
        local pos = xyz2pos(it.pos.x, it.pos.y, it.pos.z)
        dfhack.gui.revealInDwarfmodeMap(pos, true)
        p('centered on %d,%d,%d (corpse item %d)', pos.x, pos.y, pos.z, it.id)
    end
elseif cmd == 'pieces' then
    local vp = df.global.gps.main_viewport
    local wx, wy, wz = df.global.window_x, df.global.window_y, df.global.window_z
    local groups, samples = {}, {}
    local n = 0
    for _, it in ipairs(world.items.other.IN_PLAY) do
        if it.flags.on_ground and it:getType() == df.item_type.CORPSEPIECE and it.pos.z == wz then
            local x, y = it.pos.x - wx, it.pos.y - wy
            if x >= 0 and y >= 0 and x < vp.dim_x and y < vp.dim_y then
                n = n + 1
                local idx = x * vp.dim_y + y
                local tex = vp.screentexpos_item[idx]
                -- item_body_component has no mat_type / mat_index (getMaterial()
                -- decodes to nothing); the piece's substance is its largest tissue.
                local mi = dfhack.matinfo.decode(it.largest_tissue.mat_type, it.largest_tissue.mat_index)
                local tok = mi and mi:getToken() or '?'
                local cat = tok:match('^CREATURE:[^:]+:(.*)$') or tok
                local key = string.format('%-14s %-40s', cat, flags_text(it.corpse_flags))
                groups[key] = groups[key] or {}
                groups[key][tex] = (groups[key][tex] or 0) + 1
                if not samples[key] then samples[key] = string.format('item %d %s at %d,%d', it.id, tok, it.pos.x, it.pos.y) end
            end
        end
    end
    p('corpse pieces in the viewport at z %d: %d', wz, n)
    p('%-14s %-40s texpos:count (the viewport item cell shows the top item of the tile)', 'material', 'corpse_flags')
    local keys = {}
    for k in pairs(groups) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local parts = {}
        for tex, c in pairs(groups[k]) do table.insert(parts, tex .. ':' .. c) end
        table.sort(parts)
        p('%s %s   e.g. %s', k, table.concat(parts, ' '), samples[k])
    end
elseif cmd == 'glyphs' then
    for _, id in ipairs({'DWARF', 'CAT', 'GOBLIN', 'DOG', 'SPIDER_CAVE', 'TROLL'}) do
        for _, raw in ipairs(world.raws.creatures.all) do
            if raw.creature_id == id then
                p('creature %-12s tile %3d soldier %3d color %d:%d:%d glowtile %d castes %d caste_tile[0] %d caste_color[0] %d:%d:%d',
                    id, raw.creature_tile, raw.creature_soldier_tile, raw.color[0], raw.color[1], raw.color[2], raw.glowtile,
                    #raw.caste, raw.caste[0].caste_tile, raw.caste[0].caste_color[0], raw.caste[0].caste_color[1], raw.caste[0].caste_color[2])
            end
        end
    end
    -- Raw text to compare: inorganic_stone_layer.txt has GRANITE
    -- [DISPLAY_COLOR:7:7:1][TILE_COLOR:7:7:1]?; the memory shows which of
    -- basic_color / build_color / tile_color holds which.
    for _, tok in ipairs({'INORGANIC:GRANITE', 'INORGANIC:IRON', 'INORGANIC:MAGNETITE', 'INORGANIC:OBSIDIAN', 'PLANT:OAK:WOOD',
                          'CREATURE:DWARF:BONE', 'CREATURE:SPIDER_CAVE:SILK', 'INORGANIC:RUBY'}) do
        local mi = dfhack.matinfo.find(tok)
        if mi and mi.material then
            local m = mi.material
            p('material %-26s tile %3d item_symbol %3d basic %d:%d build %d:%d:%d tile_color %d:%d:%d', tok, m.tile, m.item_symbol,
                m.basic_color[0], m.basic_color[1], m.build_color[0], m.build_color[1], m.build_color[2],
                m.tile_color[0], m.tile_color[1], m.tile_color[2])
        else
            p('material %-26s (not found)', tok)
        end
    end
else
    p('usage: df3d-corpse-probe levels <n> | center <i> | lone [i] | lonepiece [i] | kill | killed [i] | pieces | glyphs')
end
