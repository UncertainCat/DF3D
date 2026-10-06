-- Vertical-opening modes used by native material navigation: liquid classification
-- (all option flags clear), stair movement, or ramp clearance with 0x901020.
-- Other native flag combinations are not implemented here.
local open_names={RampTop=true,OpenSpace=true,Chasm=true,EeriePit=true}
local movement_shapes={STAIR_DOWN=true,STAIR_UPDOWN=true,BRANCH=true,TWIG=true}
return function(p,mode,context)
    if mode~='liquid' and mode~='stairs' and mode~='ramp' then return nil end
    local movement=mode~='liquid'
    local block=context and context.block or dfhack.maps.getTileBlock(p)
    if not block then return nil end
    local x,y=p.x%16,p.y%16
    local tile=context and context.tile or block.tiletype[x][y]
    local name,attrs=context and context.name or df.tiletype[tile],context and context.attrs or df.tiletype.attrs[tile]
    if type(name)~='string' or not attrs then return nil end
    local shape=context and context.shape or df.tiletype_shape[attrs.shape]
    if type(shape)~='string' then return nil end
    local occ=(context and context.occupancy or block.occupancy[x][y].building)
    if occ==3 or occ==5 or occ==6 then return false end
    if occ<0 or occ>7 then return nil end
    if occ==7 then
        local b=dfhack.buildings.findAtTile(p)
        if not b then return nil end
        local kind=df.building_type[b:getType()]
        if type(kind)~='string' then return nil end
        if kind=='Hatch' then
            if movement then
                if b.door_flags.closed and b.door_flags.forbidden and
                    b:getBuildStage()>=b:getMaxBuildStage() and b:isSettingOccupancy() then return false end
            elseif b.door_flags.closed then return false end
        elseif kind=='GrateFloor' or kind=='BarsFloor' then
            if b.gate_flags.closed then return false end
        end
    end
    -- Ramp clearance passes native allow-stairs=false but keeps movement hatch
    -- semantics. Treating it as either liquid or stair mode changes valid edges.
    return not not (open_names[name] or (mode=='stairs' and movement_shapes[shape]))
end
