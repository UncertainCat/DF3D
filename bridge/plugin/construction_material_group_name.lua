-- Native generic material labels. Evidence: material_candidates.json
-- group_copy_capture (ordinary groups, singletons and seven-item stacks).
-- Ordinary individual descriptions use mode0, including native stack suffixes.
-- Furniture singular/plural and standalone improved/artifact names:
-- furniture_material_copy.json. Anvils: magma_placement.json.
-- Missing evidence returns nil, never substitute visible text.
return function(group,individual_id,history)
    if type(group)~='table' or type(group.individual)~='boolean' or type(group.ids)~='table' or #group.ids==0 then return nil end
    local supported=false
    for _,kind in ipairs{'SMALLGEM','BAR','BLOCKS','BOULDER','WOOD','BED','CHAIR','TABLE','ANVIL','COFFIN','CABINET','BOX','SLAB','STATUE','TRACTION_BENCH','TOOL','INSTRUMENT','DOOR','HATCH_COVER','CAGE','CHAIN','ARMORSTAND','WEAPONRACK','GRATE','FLOODGATE','QUERN','ANIMALTRAP','WINDOW','TRAPPARTS','BUCKET','BARREL','MILLSTONE','BALLISTAPARTS','CATAPULTPARTS','BOLT_THROWER_PARTS','BIN','PIPE_SECTION','TRAPCOMP','WEAPON'} do
        if df.item_type[kind]~=nil and group.item_type==df.item_type[kind] then supported=true;break end
    end
    if not supported then return nil end
    local item=df.item.find(individual_id or group.ids[1])
    if not item or
        item:getType()~=group.item_type or item:getSubtype()~=group.item_subtype or
        item:getMaterial()~=group.mat_type or item:getMaterialIndex()~=group.mat_index then return nil end
    if history then
        -- single_item_special_last_reference and artifact_last_reference: Last
        -- names the undecorated plural class even for a standalone special item.
        -- It does not automatically select those standalone rows again.
        if group.item_type==df.item_type.STATUE then
            local material=dfhack.matinfo.decode(item)
            local prefix=material and material:toString()
            return type(prefix)=='string' and prefix~='' and dfhack.df2utf(prefix..' statues') or nil
        end
        local text=dfhack.items.getDescription(item,2,false)
        return type(text)=='string' and text~='' and dfhack.df2utf(text) or nil
    end
    if item.flags.artifact then
        -- Native artifact_reference: the untranslated artifact name, not the
        -- readable description's translated name/type or decorated material.
        if not group.individual or #group.ids~=1 or (individual_id and individual_id~=group.ids[1]) then return nil end
        local ref=dfhack.items.getGeneralRef(item,df.general_ref_type.IS_ARTIFACT)
        local artifact=ref and ref:getArtifact()
        if not artifact or not artifact.name.has_name then return nil end
        local text=dfhack.translation.translateName(artifact.name,false)
        return type(text)=='string' and text~='' and dfhack.df2utf(text:lower()) or nil
    end
    if group.individual then
        -- Native special_item_reference: decorated furniture remains a separate
        -- Specific row, including improvement quality and statue subject text.
        local verified=false
        for _,kind in ipairs{'ANVIL','BED','CHAIR','TABLE','COFFIN','CABINET','BOX','SLAB','STATUE','TRACTION_BENCH','TOOL','INSTRUMENT','DOOR','HATCH_COVER','CAGE','CHAIN','ARMORSTAND','WEAPONRACK','GRATE','FLOODGATE','QUERN','ANIMALTRAP','WINDOW','TRAPPARTS','BUCKET','BARREL','MILLSTONE','BALLISTAPARTS','CATAPULTPARTS','BOLT_THROWER_PARTS','BIN','PIPE_SECTION','TRAPCOMP','WEAPON'} do
            if df.item_type[kind]~=nil and group.item_type==df.item_type[kind] then verified=true;break end
        end
        if not verified or not item:isImproved() or #group.ids~=1 or (individual_id and individual_id~=group.ids[1]) then return nil end
        local text=dfhack.items.getDescription(item,0,true)
        return type(text)=='string' and text~='' and dfhack.df2utf(text) or nil
    end
    if item:isImproved() then return nil end
    if not individual_id and group.item_type==df.item_type.STATUE then
        -- furniture_material_copy.statue_copy: the group omits the depicted
        -- subject. The noun is copied from native wood/stone/iron groups.
        local material=dfhack.matinfo.decode(item)
        local prefix=material and material:toString()
        if type(prefix)~='string' or prefix=='' then return nil end
        return dfhack.df2utf(prefix..' statues')
    end
    -- Building-material singletons use singular; furniture groups retain plural
    -- even with one eligible candidate. Generic modes omit stack counts.
    local furniture=group.item_type==df.item_type.BED or group.item_type==df.item_type.CHAIR or group.item_type==df.item_type.TABLE or group.item_type==df.item_type.ANVIL or group.item_type==df.item_type.COFFIN or group.item_type==df.item_type.CABINET or group.item_type==df.item_type.BOX or group.item_type==df.item_type.SLAB
    for _,kind in ipairs{'TRACTION_BENCH','TOOL','INSTRUMENT','DOOR','HATCH_COVER','CAGE','CHAIN','ARMORSTAND','WEAPONRACK','GRATE','FLOODGATE','QUERN','ANIMALTRAP','WINDOW','TRAPPARTS','BUCKET','BARREL','MILLSTONE','BALLISTAPARTS','CATAPULTPARTS','BOLT_THROWER_PARTS','BIN','PIPE_SECTION','TRAPCOMP','WEAPON'} do
        if df.item_type[kind]~=nil and group.item_type==df.item_type[kind] then furniture=true;break end
    end
    local mode=individual_id and 0 or ((furniture or #group.ids>=2) and 2 or 1)
    local text=dfhack.items.getDescription(item,mode,individual_id~=nil)
    if type(text)~='string' or text=='' then return nil end
    return dfhack.df2utf(text)
end
