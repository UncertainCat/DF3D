-- Native material movement classifications (DF53.16 256170 / 2c3560).
-- Raw tile identity is required: normalized rendering shapes lose exceptions.
local excluded_ramps={TreeRootSloping=true,TreeTrunkSloping=true,
    TreeDeadRootSloping=true,TreeDeadTrunkSloping=true}
return function(tile)
    local name,attrs=df.tiletype[tile],df.tiletype.attrs[tile]
    if type(name)~='string' or not attrs then return nil end
    local shape=df.tiletype_shape[attrs.shape]
    if type(shape)~='string' then return nil end
    return {
        ramp=shape=='RAMP' and not excluded_ramps[name],
        support=(shape=='WALL' or shape=='FORTIFICATION') and
            not name:find('Trunk',1,true) and name~='SemiMoltenRock' and name~='GlowingBarrier',
    }
end
