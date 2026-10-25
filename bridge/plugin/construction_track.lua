-- Semantic Track site reader. Invoke at a DF safe point over a stable map.
-- No buildreq, viewscreen, pointer/camera or staged native editor inputs.
-- Connected Preview and placement planning use these semantic site facts.
local native_site_support=...
assert(type(native_site_support)=='function','Missing native track terrain service')
local function connections(name)
    local suffix=name and name:match('Track([NSEW]+)$')
    local ramp=false
    if not suffix then suffix=name and name:match('TrackRamp([NSEW]+)$');ramp=suffix~=nil end
    if not suffix then return nil end
    local mask=0
    for letter in suffix:gmatch('.') do mask=mask | ({N=1,S=2,E=4,W=8})[letter] end
    return mask,ramp
end
local excluded_movement_ramps={TreeRootSloping=true,TreeTrunkSloping=true,
    TreeDeadRootSloping=true,TreeDeadTrunkSloping=true}

return function(p)
    p={x=p.x,y=p.y,z=p.z}
    local block=dfhack.maps.getTileBlock(p)
    if not block then return {loaded=false} end
    local x,y=p.x%16,p.y%16
    local tile=block.tiletype[x][y]
    local attrs=df.tiletype.attrs[tile]
    local des,occ=block.designation[x][y],block.occupancy[x][y]
    local shape=df.tiletype_shape[attrs.shape]
    local tile_name=df.tiletype[tile]
    local result={loaded=true,tile=tile,native_shape=shape,
        endpoint_only=tile_name=='TreeTwigs' or tile_name=='TreeDeadTwigs',
        hidden=des.hidden,liquid_depth=des.flow_size,magma=des.liquid_type,
        walkable=block.walkable[x][y]~=0,
        occupancy_bits=occ.building,occupancy='Unknown',
        -- Native movement identities; tree/hazard exceptions share nominal shapes.
        movement_ramp=shape=='RAMP' and not excluded_movement_ramps[tile_name],
        support=(shape=='WALL' or shape=='FORTIFICATION') and
            not tile_name:find('Trunk',1,true) and tile_name~='SemiMoltenRock' and tile_name~='GlowingBarrier',
        open=tile==df.tiletype.OpenSpace or tile==df.tiletype.Chasm or tile==df.tiletype.EeriePit}
    local accepted,_,verified=native_site_support(p,'TrackTerrain')
    if verified then result.native_eligible=accepted end
    local b=dfhack.buildings.findAtTile(p)
    if occ.building==0 then result.occupancy='None' end
    if b then
        local kind=df.building_type[b:getType()]
        result.building={id=b.id,kind=kind,stage=b:getBuildStage(),max_stage=b:getMaxBuildStage(),removing=dfhack.buildings.markedForRemoval(b)}
        if kind=='Construction' then
            local name=df.construction_type[b:getSubtype()]
            local mask,ramp=connections(name)
            result.building.subtype=name
            if name and result.building.stage==0 and not result.building.removing then
                result.occupancy='PendingConstruction'
                result.pending={id=b.id,connections=mask or 0,ramp=not not ramp,track=mask~=nil,subtype=b:getSubtype()}
            else result.occupancy='Unknown' end
        elseif occ.building~=0 then
            -- Native construction occupancy rejects non-construction buildings
            -- regardless of their family (a82436..a824b3). Passable workshops
            -- are blocked sites, not unknown facts that poison nearby routes.
            result.occupancy='BlockingBuilding'
        end
    elseif occ.building~=0 then result.occupancy='Unknown' end

    -- Preserve native tile kind independently of any pending replacement job.
    local mask=connections(df.tiletype[tile])
    if mask then
        result.terrain={connections=mask,ramp=shape=='RAMP',
            kind=attrs.material==df.tiletype_material.CONSTRUCTION and 'Constructed' or 'Carved'}
    end
    -- Same native ramp-clearance semantics as track_terrain.h. Unknown dynamic
    -- occupancy deliberately omits the fact instead of claiming clear space.
    local occupancy=occ.building
    if occupancy==3 or occupancy==5 or occupancy==6 then result.clearance_blocked=true
    elseif occupancy~=7 then result.clearance_blocked=false
    elseif b then
        local kind=result.building.kind
        if kind=='Hatch' then
            result.clearance_blocked=b.door_flags.forbidden and b.door_flags.closed and
                b:getBuildStage()>=b:getMaxBuildStage() and b:isSettingOccupancy()
        elseif kind=='GrateFloor' or kind=='BarsFloor' then result.clearance_blocked=b.gate_flags.closed end
    end
    return result
end
