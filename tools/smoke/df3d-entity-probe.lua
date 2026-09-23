-- df3d-entity-probe: dumps the DF building / item facts the bridge's
-- schema-v4 mapping relies on: build-stage vs `exists`
-- boundaries per building type, room.extents encodings, custom types,
-- door/hatch forbid flags, civzone ownership, and the on_ground flag
-- combinations of items in play. Read-only. Run via
-- tools/smoke/entity_probe.ps1 (staged into hack/scripts by the lane).
--@ module = false

local world = df.global.world
local function p(...) print(string.format(...)) end
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
local function dump(title, t)
    p('--- %s', title)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do p('  %-70s %d', k, t[k]) end
end

-- ---- buildings ----
local byType, stages, extents, rel, doors, mats, custom = {}, {}, {}, {}, {}, {}, {}
local nb = 0
for _, b in ipairs(world.buildings.all) do
    nb = nb + 1
    local t = df.building_type[b:getType()]
    bump(byType, t)
    bump(stages, string.format('%s stage=%d/%d exists=%s', t, b:getBuildStage(),
        b:getMaxBuildStage(), tostring(b.flags.exists)))
    if b.room.extents ~= nil then
        local w, h = b.room.width, b.room.height
        local area = (b.x2 - b.x1 + 1) * (b.y2 - b.y1 + 1)
        local match = (b.room.x == b.x1 and b.room.y == b.y1 and w * h == area)
        local hist = {}
        for i = 0, w * h - 1 do bump(hist, tostring(b.room.extents[i])) end
        local hs = {}
        for k, v in pairs(hist) do table.insert(hs, k .. 'x' .. v) end
        table.sort(hs)
        bump(extents, string.format('%s extents match=%s vals=%s', t, tostring(match), table.concat(hs, ',')))
        if not match then
            p('  mismatch %s id=%d rect=(%d,%d)-(%d,%d) room=(%d,%d %dx%d)', t, b.id, b.x1, b.y1, b.x2, b.y2,
                b.room.x, b.room.y, w, h)
        end
    else
        bump(extents, t .. ' no-extents')
    end
    local ct = b:getCustomType()
    if ct >= 0 then
        local def = df.building_def.find(ct)
        bump(custom, string.format('%s custom=%d code=%s', t, ct, def and def.code or '?'))
    end
    bump(rel, string.format('%s relations=%d', t, #b.relations))
    if b._type == df.building_doorst then
        bump(doors, 'door forbidden=' .. tostring(b.door_flags.forbidden) .. ' closed=' .. tostring(b.door_flags.closed))
    elseif b._type == df.building_hatchst then
        bump(doors, 'hatch forbidden=' .. tostring(b.door_flags.forbidden))
    end
    local mi = dfhack.matinfo.decode(b.mat_type, b.mat_index)
    bump(mats, string.format('%s mat=%s', t, mi and mi:getToken() or ('invalid ' .. b.mat_type .. '/' .. b.mat_index)))
end
p('buildings total %d', nb)
dump('buildings by type', byType)
dump('build stage / max / exists', stages)
dump('extents', extents)
dump('custom types', custom)
dump('relations (zones containing the building)', rel)
dump('door/hatch flags', doors)
dump('materials (sample keys)', mats)

-- civzones
local zones = {}
local ok, zoneVec = pcall(function() return world.buildings.other.ANY_ZONE end)
if not ok then zoneVec = {} end
for _, z in ipairs(zoneVec) do
    bump(zones, string.format('%s owner=%s assigned_units=%d contained=%d', df.civzone_type[z.type],
        tostring(z.assigned_unit_id ~= -1), #z.assigned_units, #z.contained_buildings))
end
dump('civzones', zones)

-- a few samples per type for the tier-4 cross-check
local seen = {}
p('--- samples')
for _, b in ipairs(world.buildings.all) do
    local t = df.building_type[b:getType()]
    if (seen[t] or 0) < 2 then
        seen[t] = (seen[t] or 0) + 1
        p('  %s id=%d sub=%d rect=(%d,%d)-(%d,%d) z=%d center=(%d,%d) stage=%d/%d exists=%s',
            t, b.id, b:getSubtype(), b.x1, b.y1, b.x2, b.y2, b.z, b.centerx, b.centery,
            b:getBuildStage(), b:getMaxBuildStage(), tostring(b.flags.exists))
    end
end

-- ---- items ----
local all = #world.items.all
local inplay = #world.items.other.IN_PLAY
local c = { on_ground = 0, og_clean = 0, og_in_job = 0, og_in_inventory = 0, og_in_building = 0,
            og_removed = 0, og_hidden = 0, og_negpos = 0, og_encased = 0, og_construction = 0,
            og_garbage = 0, og_spider_web = 0 }
local byKind, flags, subtypes = {}, { forbid = 0, dump = 0, melt = 0, on_fire = 0, rotten = 0, artifact = 0 }, {}
local minx, maxx, minz, maxz = 1e9, -1e9, 1e9, -1e9
for _, it in ipairs(world.items.other.IN_PLAY) do
    local f = it.flags
    if f.on_ground then
        c.on_ground = c.on_ground + 1
        if f.in_job then c.og_in_job = c.og_in_job + 1 end
        if f.in_inventory then c.og_in_inventory = c.og_in_inventory + 1 end
        if f.in_building then c.og_in_building = c.og_in_building + 1 end
        if f.removed then c.og_removed = c.og_removed + 1 end
        if f.hidden then c.og_hidden = c.og_hidden + 1 end
        if f.encased then c.og_encased = c.og_encased + 1 end
        if f.construction then c.og_construction = c.og_construction + 1 end
        if f.garbage_collect then c.og_garbage = c.og_garbage + 1 end
        if f.spider_web then c.og_spider_web = c.og_spider_web + 1 end
        if not f.in_inventory and not f.in_building then
            c.og_clean = c.og_clean + 1
            local k = df.item_type[it:getType()]
            bump(byKind, k)
            for fl in pairs(flags) do if f[fl] then flags[fl] = flags[fl] + 1 end end
            if it.pos.x < 0 or it.pos.y < 0 or it.pos.z < 0 then c.og_negpos = c.og_negpos + 1 end
            minx = math.min(minx, it.pos.x); maxx = math.max(maxx, it.pos.x)
            minz = math.min(minz, it.pos.z); maxz = math.max(maxz, it.pos.z)
            local st = it:getSubtype()
            if st >= 0 then
                local def = dfhack.items.getSubtypeDef(it:getType(), st)
                bump(subtypes, string.format('%s subtype=%d def=%s', k, st, def and def.id or 'nil'))
            end
        end
    end
end
p('items all=%d in_play=%d', all, inplay)
dump('on_ground flag combinations', c)
dump('on-ground (clean) by kind', byKind)
dump('on-ground (clean) flags', flags)
dump('on-ground subtypes (sample keys)', subtypes)
p('pos x %d..%d z %d..%d', minx, maxx, minz, maxz)

-- hauling activity right now (Delta expectation)
local haul, haulItems = 0, 0
for _, u in ipairs(world.units.active) do
    local j = u.job.current_job
    if j and df.job_type.attrs[j.job_type].type == df.job_type_class.Hauling then
        haul = haul + 1
        haulItems = haulItems + #j.items
    end
end
p('units hauling now: %d (job items %d)', haul, haulItems)
