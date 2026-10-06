-- Partial native Track candidate gate, not a complete recipe/position predicate.
-- DF53.16 collector a29630/a2a630 and bin gate c93380; protected captures
-- material_candidates.json. Callers provide copied item facts, never buildreq.
-- This covers the observed Track recipe with can_steal_haul_items=false and
-- location-reserved materials disallowed. Other recipes need separate evidence.
-- container_kind is a resolved native item type name, or UNIT for inventory
-- without a containing item. nil means missing facts; false is an exclusion.
return function(facts)
    local function flags(value)
        return math.type(value)=='integer' and value>=0 and value<=0xffffffff
    end
    if type(facts)~='table' or not flags(facts.flags) then return nil end
    -- removed, in_building, construction, encased, owned, forbid, dump, on_fire,
    -- in_job, melt. Track lacks allow_melt_dump (native a281fa..a28208).
    -- A known exclusion is decisive even when later facts are unavailable.
    if facts.flags & 0xe90c32~=0 then return false end
    if not flags(facts.flags2) then return nil end
    if facts.flags2 & 8~=0 then return false end
    if facts.flags & 8==0 then return true end
    if type(facts.container_kind)~='string' or facts.container_kind=='' then return nil end
    -- Native c93380 accepts only a direct containing BIN (item type0x20).
    if facts.container_kind~='BIN' then return false end
    if not flags(facts.container_flags) or not flags(facts.container_flags2) then return nil end
    -- A direct bin must itself be uncontained and free of the native obstruction
    -- flags. Bin ownership and dumping do not reject its contents in this gate.
    if facts.container_flags & 0x480c3a~=0 or facts.container_flags2 & 8~=0 then return false end
    return true
end
