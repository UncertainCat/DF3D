-- Material flood destination predicate, derived from DF53.16 RVA5400d0.
-- This is only one predicate used by native movement, not a complete movement
-- edge or candidate eligibility check. No viewscreen/buildreq/search scratch.
local surfaces={FLOOR=true,RAMP=true,STAIR_UP=true,STAIR_DOWN=true,
    STAIR_UPDOWN=true,SHRUB=true,SAPLING=true,BRANCH=true,BROOK_TOP=true,
    BOULDER=true,PEBBLES=true}
local open_names={RampTop=true,OpenSpace=true,Chasm=true,EeriePit=true}
return function(p,context)
    local block=context and context.block or dfhack.maps.getTileBlock(p)
    if not block then return nil end
    local x,y=p.x%16,p.y%16
    local tile=context and context.tile or block.tiletype[x][y]
    local name=context and context.name or df.tiletype[tile]
    local attrs=context and context.attrs or df.tiletype.attrs[tile]
    if type(name)~='string' or not attrs then return nil end
    local shape=context and context.shape or df.tiletype_shape[attrs.shape]
    if type(shape)~='string' then return nil end
    local des,occ=context and context.designation or block.designation[x][y],(context and context.occupancy or block.occupancy[x][y].building)
    if type(des.flow_forbid)~='boolean' then return nil end
    if des.flow_forbid or occ==3 or occ==4 or occ==6 then return false end
    if occ<0 or occ>7 then return nil end
    local walkable=surfaces[shape] or name=='BurningTreeTwigs'
    if name=='Campfire' or name=='TreeTrunkSloping' then walkable=false end
    local open=open_names[name] or false
    if occ==7 then
        local b=dfhack.buildings.findAtTile(p)
        -- Missing dynamic facts are not evidence for passage.
        if not b then return nil end
        local kind=df.building_type[b:getType()]
        if type(kind)~='string' then return nil end
        if kind=='Hatch' then
            if open and b.door_flags.closed then return true end
        elseif kind=='GrateFloor' or kind=='BarsFloor' then
            if open and b.gate_flags.closed then return true end
        elseif kind=='GrateWall' or kind=='BarsVertical' then
            if b.gate_flags.closed then return false end
        end
    end
    return not not (walkable or (occ==5 and open))
end
