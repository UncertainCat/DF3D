-- Compose stable semantic material terrain facts at a DF safe point. Helpers
-- are injected by the owner; no viewscreens, buildreq or path scratch are read.
-- destination_allowed supplies native surface/occupancy/dynamic support checks.
-- Compose it with environment and geometry; it is not full movement approval.
return function(destination,opening,shapes)
    assert(type(destination)=='function' and type(opening)=='function' and type(shapes)=='function')
    return function(p)
        p={x=p.x,y=p.y,z=p.z}
        local block=dfhack.maps.getTileBlock(p)
        if not block then return {loaded=false} end
        local x,y=p.x%16,p.y%16
        local tile=block.tiletype[x][y]
        local attrs=df.tiletype.attrs[tile]
        local name=df.tiletype[tile]
        local shape=attrs and df.tiletype_shape[attrs.shape] or nil
        local classes=shapes(tile)
        local des=block.designation[x][y]
        -- Shared only within this synchronous tile read. Never retain native
        -- blocks or dynamic occupancy facts across calls or safe points.
        local context={block=block,tile=tile,name=name,attrs=attrs,shape=shape,
            designation=des,occupancy=block.occupancy[x][y].building}
        local result={loaded=true,native_shape=shape,
            liquid_depth=des.flow_size,magma=des.liquid_type,
            temperature=block.temperature_1[x][y],
            destination_allowed=destination(p,context),
            stair_opening=opening(p,'stairs',context),ramp_opening=opening(p,'ramp',context)}
        if classes then
            result.movement_ramp=classes.ramp;result.support=classes.support
            result.open=name=='OpenSpace' or name=='Chasm' or name=='EeriePit'
        end
        -- Lower liquid matters only for nonzero, non-full water. Do not invent
        -- an empty lower tile when its block or opening state is unavailable.
        if des.flow_size>0 and des.flow_size<7 and not des.liquid_type then
            result.open_below=opening(p,'liquid',context)
            if result.open_below and p.z>0 then
                local below=dfhack.maps.getTileBlock{x=p.x,y=p.y,z=p.z-1}
                if below then result.below_liquid_depth=below.designation[x][y].flow_size end
            end
        end
        return result
    end
end
