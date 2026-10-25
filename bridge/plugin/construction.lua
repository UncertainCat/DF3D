-- Semantic construction adapter; closure lifetime owns all cached state.
-- The embedded native site reader is injected with this closure's lifetime;
-- standalone adapter tests may omit it while Track remains unavailable.
local track_site_reader,track_material_candidates,material_order,track_placement_plan,track_commit,material_group_name,site_support,bed_facts=...
local function clipped_utf8(text,cap)
    if #text<=cap then return text end
    while cap>0 and (text:byte(cap+1) & 0xc0)==0x80 do cap=cap-1 end
    return text:sub(1,cap)
end
-- Native evidence and current limitations are maintained in ENGINEERING.md and
-- fixtures/construction. Generated specs never override native behavior/copy.
-- Installed material-bearing families require owned native candidate collection
-- and native distance calculation. Unknown custom recipes remain unavailable;
-- they have no verified material-ordering service. Track requires its complete
-- semantic services and uses the two narrowly approved stable-route/fresh-cost
-- exceptions documented in AGENT_INSTRUCTIONS.md.
local B=dfhack.buildings
local function fail(message) return {ok=false,message=message} end
-- Native Pressure Plate examples are selected from raw facts, never buildreq.
-- DF53.16 uses raw aggregate size/frequency and these trait bonuses. Preserve
-- first-raw ties and the final size bucket's native search ceiling. See the
-- pressure_plate fixture for independent native-input comparisons and limits.
local pressure_positive={'HAS_ANY_INTELLIGENT_SPEAKS','HAS_ANY_INTELLIGENT_LEARNS','HAS_ANY_UTTERANCES','HAS_ANY_CANNOT_BREATHE_WATER'}
local pressure_negative={'HAS_ANY_CANNOT_BREATHE_AIR','SAVAGE','EVIL','GOOD'}
local function pressure_creatures()
    local rows,scores={},{}
    for i=1,200 do rows[i]={size=i*1000,race_id=-1,name=''};scores[i]=-1 end
    local preferred=df.global.gamemode==df.game_mode.DWARF and df.global.plotinfo.race_id or -1
    for id,raw in ipairs(df.global.world.raws.creatures.all) do
        local f,size=raw.flags,raw.adultsize
        if not (f.EQUIPMENT or f.GENERATED or f.DOES_NOT_EXIST) and size>=1000 and size<=200000999 then
            local score=raw.frequency
            if id==preferred then score=score+100000
            elseif f.OCCURS_AS_ENTITY_RACE then
                score=score+((f.BIOME_SUBTERRANEAN_CHASM or f.BIOME_SUBTERRANEAN_WATER) and 30000 or f.BIOME_SUBTERRANEAN_LAVA and 20000 or 50000)
            end
            if f.HAS_ANY_MEGABEAST then score=score+1000 end
            if f.HAS_ANY_COMMON_DOMESTIC then score=score+100 end
            for _,flag in ipairs(pressure_positive) do
                if f[flag] then score=score+50 end
            end
            for _,flag in ipairs(pressure_negative) do
                if not f[flag] then score=score+50 end
            end
            local index=math.min(200,size//1000)
            if score>scores[index] then
                scores[index]=score;rows[index].race_id=id;rows[index].name=dfhack.df2utf(raw.name[0])
            end
        end
    end
    return {ok=true,pressure_creatures=rows}
end
local function filter_call(raw,fn)
    local j=df.job_item:new();j:assign(raw)
    local ok,value=pcall(fn,j);j:delete();if not ok then error(value) end;return value
end
local function hash(h,s,step)
    for i=1,#s do h=(h ~ s:byte(i))*0x100000001b3;if step then step() end end;return h
end
local function revision(h) h=h & 0x7fffffffffffffff;return h==0 and 1 or h end
local function tick() return df.global.cur_year*403200+df.global.cur_year_tick end
local function custom(d)
    if d.custom_code=='' then return -1 end
    for _,v in ipairs(df.global.world.raws.buildings.all) do if v.code==d.custom_code then return v.id end end;return -1
end
local function permitted(v)
    local civ=df.historical_entity.find(df.global.plotinfo.civ_id)
    if civ then for _,id in ipairs(civ.entity_raw.workshops.permitted_building_id) do if id==v.id then return true end end end;return false
end
local function recipe(d)
    local inputs=B.getFiltersByType({},d.type,d.subtype,custom(d))
    -- Native 53.16 requests parts, mechanisms, chains, then bins. DFHack's
    -- helper puts bins second; preserve native picker and job-item order.
    if d.key=='SiegeEngine:BoltThrower' and inputs and #inputs==4 then
        return {inputs[1],inputs[3],inputs[4],inputs[2]}
    end
    return inputs
end
local function filter_row(raw,index)
    return filter_call(raw,function(j)
        local token=''
        if j.vector_id and j.vector_id>df.job_item_vector_id.IN_PLAY then token=df.job_item_vector_id[j.vector_id] or '' end
        if j.has_tool_use and j.has_tool_use>df.tool_uses.NONE then token=df.tool_uses[j.has_tool_use] or token end
        if token=='' and j.flags2 then
            local names={};for k,v in pairs(j.flags2) do if type(k)=='string' and v==true then names[#names+1]=k end end
            table.sort(names);token=table.concat(names,',')
        end
        return {index=index,item_type=j.item_type or -1,item_subtype=j.item_subtype or -1,caption='',requirement=token:sub(1,64),quantity=j.quantity}
    end)
end
local magma_buildings={['Workshop:MagmaForge']=true,['Furnace:MagmaSmelter']=true,
    ['Furnace:MagmaGlassFurnace']=true,['Furnace:MagmaKiln']=true}
local sized={FarmPlot=true,Bridge=true,RoadDirt=true,RoadPaved=true,AxleHorizontal=true,Rollers=true}
local extent_shaped={FarmPlot=true,RoadDirt=true,RoadPaved=true}
local machines={ScrewPump=true,WaterWheel=true,GearAssembly=true,AxleHorizontal=true,AxleVertical=true,Rollers=true}
local function uses_machine_support(d) return machines[d.family] or d.family=='Windmill' or d.key=='Workshop:Millstone' end
local function footprint(d,w,h,dir)
    local _,x,y,cx,cy=B.getCorrectSize(w,h,d.type,d.subtype,custom(d),dir)
    -- Native pointer anchor is the output tile, unlike the helper's anchor.
    -- All four directions are recorded in machinery_directions.json.
    if d.family=='ScrewPump' then cx=dir==3 and 1 or 0;cy=dir==0 and 1 or 0 end
    return {direction=dir<0 and 4 or dir,width=x,height=y,center_x=cx or -1,center_y=cy or -1}
end
local function definitions()
    local out,seen={},{}
    local function add(family,subtype,t,st,raw,synthetic)
        local key=family..(subtype~='' and ':'..subtype or '')..(raw and ':'..raw.code or '')
        if seen[key] then error('Duplicate construction catalog key: '..key) end;seen[key]=true
        local d={key=key,name=key:gsub(':',' / '),type=t,subtype=st,family=family,subtype_key=subtype,
            custom_code=raw and raw.code or '',native_name=raw and clipped_utf8(dfhack.df2utf(raw.name),128) or '',
            area_mode=family=='Construction' and (synthetic=='Stairs' and 4 or 3) or (sized[family] and 2 or 1),
            orientations=1,max_depth=synthetic=='Stairs' and 256 or 1,filters={},footprints={}}
        if family=='SiegeEngine' then d.orientations=255
        elseif family=='ScrewPump' or family=='Rollers' then d.orientations=15
        elseif family=='WaterWheel' or family=='AxleHorizontal' then d.orientations=3
        elseif family=='Bridge' then d.orientations=31 end
        local success,inputs=pcall(recipe,d);local reason=''
        if not success or not inputs then reason='Building has no recipe'
        elseif #inputs>8 then reason='Recipe has more than 8 inputs'
        else for i,v in ipairs(inputs) do d.filters[i]=filter_row(v,i-1) end end
        if family=='Stockpile' or family=='Civzone' then reason='Placed from the stockpile and zone menus'
        elseif (subtype:find('Magma') and not magma_buildings[key]) or (raw and raw.needs_magma) then reason='Magma placement rule not captured'
        elseif synthetic=='Track' and (type(track_site_reader)~='function' or
            type(track_material_candidates)~='function' or type(material_order)~='function' or
            type(track_placement_plan)~='function' or type(track_commit)~='function' or type(material_group_name)~='function') then
            reason='Track semantic services unavailable'
        end
        if raw and not permitted(raw) then reason='Not permitted for this civilization' end
        for dir=0,7 do if d.orientations & (1<<dir)~=0 then
            local ok,f=pcall(footprint,d,1,1,family=='Bridge' and dir==4 and -1 or dir)
            if ok and f.width and f.height and f.width>=1 and f.height>=1 and f.width<=31 and f.height<=31 then d.footprints[#d.footprints+1]=f
            else reason='Native placement check rejected this site' end
        end end
        local f=d.footprints[1];d.width=f and f.width or 1;d.height=f and f.height or 1
        d.max_width=d.area_mode==1 and d.width or 31;d.max_height=d.area_mode==1 and d.height or 31
        for _,v in ipairs(d.footprints) do d.max_width=math.max(d.max_width,v.width);d.max_height=math.max(d.max_height,v.height) end
        d.supported=reason=='';d.reason=reason;out[#out+1]=d
    end
    local enums={Workshop=df.workshop_type,Furnace=df.furnace_type,Trap=df.trap_type,SiegeEngine=df.siegeengine_type,Construction=df.construction_type}
    for t=0,df.building_type._last_item do local name=df.building_type[t]
        if type(name)=='string' and name~='Nest' and name~='Wagon' and name~='Shop' then
            local e=enums[name]
            if e then for st=0,e._last_item do local n=e[st]
                if type(n)=='string' and n~='Custom' and not (name=='Construction' and (n:match('^Track') or n=='UpStair' or n=='DownStair' or n=='UpDownStair')) then add(name,n,t,st) end
            end else add(name,'',t,-1) end
        end
    end
    if df.global and df.global.world then for _,v in ipairs(df.global.world.raws.buildings.all) do
        local furnace=df.building_def_furnacest:is_instance(v)
        add(furnace and 'Furnace' or 'Workshop','Custom',furnace and df.building_type.Furnace or df.building_type.Workshop,
            furnace and df.furnace_type.Custom or df.workshop_type.Custom,v)
    end end
    if df.building_type.Construction then
        add('Construction','Stairs',df.building_type.Construction,df.construction_type.UpDownStair,nil,'Stairs')
        add('Construction','Track',df.building_type.Construction,df.construction_type.TrackNSEW,nil,'Track')
    end
    table.sort(out,function(a,b) return a.key<b.key end);return out
end
local catalog=definitions()
local by_key={};for _,d in ipairs(catalog) do by_key[d.key]=d end
local catalog_error
for _,key in ipairs{'Chair','Workshop:Carpenters','Construction:Wall','Trap:Lever','Construction:Stairs'} do
    if not by_key[key] or not by_key[key].supported then catalog_error='Native construction catalog is incomplete: '..key;break end
end
local function visible(p)
    if not p or not dfhack.maps.isValidTilePos(p) then return false end
    local f=dfhack.maps.getTileFlags(p);return f and not f.hidden
end
-- Native ordinary terrain branch verified against furniture placement.
local native_opening_tile={Support=true,Well=true,Hatch=true,GrateFloor=true,BarsFloor=true,AnimalTrap=true}
local native_furniture_tile={Bed=true,Chair=true,Door=true,Statue=true,Cage=true,Weaponrack=true,Table=true,Box=true,Cabinet=true,Coffin=true,Slab=true,TractionBench=true,Bookcase=true,DisplayFurniture=true,OfferingPlace=true,Instrument=true,GrateWall=true,BarsVertical=true,WindowGlass=true,WindowGem=true}
local native_ordinary_tile={
    ["ArcheryTarget"]=true,
    ["Armorstand"]=true,
    ["Chain"]=true,
    ["Floodgate"]=true,
    ["Furnace:GlassFurnace"]=true,
    ["Furnace:Kiln"]=true,
    ["Furnace:Smelter"]=true,
    ["Furnace:WoodFurnace"]=true,
    ["Hive"]=true,
    ["NestBox"]=true,
    ["SiegeEngine:Ballista"]=true,
    ["SiegeEngine:BoltThrower"]=true,
    ["SiegeEngine:Catapult"]=true,
    ["TradeDepot"]=true,
    ["Trap:CageTrap"]=true,
    ["Trap:Lever"]=true,
    ["Trap:PressurePlate"]=true,
    ["Trap:StoneFallTrap"]=true,
    ["Trap:TrackStop"]=true,
    ["Trap:WeaponTrap"]=true,
    ["Weapon"]=true,
    ["Workshop:Ashery"]=true,
    ["Workshop:Bowyers"]=true,
    ["Workshop:Butchers"]=true,
    ["Workshop:Carpenters"]=true,
    ["Workshop:Clothiers"]=true,
    ["Workshop:Craftsdwarfs"]=true,
    ["Workshop:Custom:SCREW_PRESS"]=true,
    ["Workshop:Custom:SOAP_MAKER"]=true,
    ["Workshop:Dyers"]=true,
    ["Workshop:Farmers"]=true,
    ["Workshop:Fishery"]=true,
    ["Workshop:Jewelers"]=true,
    ["Workshop:Kennels"]=true,
    ["Workshop:Kitchen"]=true,
    ["Workshop:Leatherworks"]=true,
    ["Workshop:Loom"]=true,
    ["Workshop:Masons"]=true,
    ["Workshop:Mechanics"]=true,
    ["Workshop:MetalsmithsForge"]=true,
    ["Workshop:Quern"]=true,
    ["Workshop:Siege"]=true,
    ["Workshop:Still"]=true,
    ["Workshop:Tanners"]=true,
}
local function attrs(p) local tt=dfhack.maps.getTileType(p);return tt and df.tiletype.attrs[tt] end
local function bridge_perimeter(r)
    if not site_support then return false,'' end
    return site_support({x=r.x,y=r.y,z=r.z},'BridgePerimeter',r.width,r.height)
end
local function stair_piece(r,p)
    -- Native stairs_placement: preserve the existing connection beyond each
    -- endpoint. Carved down stairs at the bottom and up stairs at the top must
    -- become up/down rather than losing the existing half of the staircase.
    local a=attrs(p);local shape=a and df.tiletype_shape[a.shape]
    local b=B.findAtTile(p)
    local queued=b and b:getType()==df.building_type.Construction and b:getBuildStage()==0 and not B.markedForRemoval(b) and b.type
    -- Native also preserves the connection from an unfinished stair job,
    -- even when the underlying terrain has no stair connection yet.
    if p.z==r.z then return (shape=='STAIR_DOWN' or shape=='STAIR_UPDOWN' or queued==df.construction_type.DownStair or queued==df.construction_type.UpDownStair) and 3 or 1 end
    if p.z==r.z+r.depth-1 then return (shape=='STAIR_UP' or shape=='STAIR_UPDOWN' or queued==df.construction_type.UpStair or queued==df.construction_type.UpDownStair) and 3 or 2 end
    return 3
end
local piece_names={'UpStair','DownStair','UpDownStair'}
local function machine_connection(r,d)
    -- DF owns the hookup coordinates/direction masks and connection decisions.
    -- The output vectors belong to this safe-point query; no buildreq is used.
    local buildings=df.global.world.buildings
    local info=df.machine_tile_set:new()
    return dfhack.with_finalize(function()info:delete()end,function()
        buildings:get_machine_hookup_list(info,d.type,d.subtype,
            r.x,r.y,r.x+r.width-1,r.y+r.height-1,r.z,r.direction>0)
        -- Match evaluate_buildability's scan, including planned machines and
        -- corner connections that a hand-built neighbor shortlist can miss.
        for i=#buildings.all-1,0,-1 do
            if buildings.all[i]:canConnectToMachine(info) then return true,#info.tiles.x>0 end
        end
        return false,#info.tiles.x>0
    end)
end
local queued_replacement={Wall=true,Floor=true,Ramp=true,Fortification=true,ReinforcedWall=true,Stairs=true}
local function queued_existing(d,p)
    if d.family~='Construction' or not queued_replacement[d.subtype_key] then return end
    local b=B.findAtTile(p)
    if b and b:getType()==df.building_type.Construction and b:getBuildStage()==0 and not B.markedForRemoval(b) then return b end
end
local function tile_rule(r,d,p,piece,machine_supported,terrain)
    -- Loaded hidden terrain is a native gameplay refusal. Missing map data is
    -- a separate diagnostic and must never be presented as a hidden tile.
    if not dfhack.maps.isValidTilePos(p) then return false,'Site is unloaded or outside the map',extent_shaped[d.family] end
    local f,occ=dfhack.maps.getTileFlags(p)
    if not f or not occ or (extent_shaped[d.family] and not dfhack.maps.getTileBlock(p)) then
        return false,'Site is unloaded or outside the map',extent_shaped[d.family]
    end
    -- Native farm/road placement admits hidden terrain, including anchors.
    if f.hidden and not extent_shaped[d.family] then return false,'Hidden, cannot build at this location' end
    local family=d.family
    if family=='Construction' then
        if type(site_support)~='function' then return false,'',true end
        -- Validate the selected recipe, not the endpoint job subtype. Native
        -- Stairs uses UpDownStair eligibility even when it creates Up/Down jobs.
        local ok,reason=site_support(p,'ConstructionTerrain',r.width,r.height,d.subtype,r.x,r.y)
        if not ok then return false,reason,reason=='' end
        -- Native terrain eligibility exempts construction jobs. Supported paint
        -- recipes reuse the queued job and its input instead of reserving again.
        if occ.building~=0 then
            if queued_existing(d,p) then return false,'Existing construction job' end
            return false,'Building present'
        end
        return true
    end
    if extent_shaped[family] then
        if type(site_support)~='function' then return false,'',true end
        local ok,reason,verified,raw=site_support(p,family..'Tile')
        if not verified or type(raw)~='boolean' then return false,'',true end
        if terrain then terrain.accepted=raw end
        return ok,reason,false
    end
    if native_opening_tile[family] or native_furniture_tile[family] or native_ordinary_tile[d.key] then
        if type(site_support)~='function' then return false,'',true end
        local query=native_opening_tile[family] and family..'OpeningTile' or native_ordinary_tile[d.key] and d.key..'OrdinaryTile' or family..'FurnitureTile'
        local ok,reason,verified=site_support(p,query)
        if not verified then return false,'',true end
        return ok,reason,false
    end
    if uses_machine_support(d) or magma_buildings[d.key] then
        if type(site_support)~='function' then return false,'',true end
        local open=machine_supported==true
        if magma_buildings[d.key] then open=not (p.x==r.x+1 and p.y==r.y+1) end
        local ok,reason,verified=site_support(p,d.key..'SpecialTile',1,1,open)
        if not verified then return false,'',true end
        return ok,reason,false
    end
    if family=='Bridge' then
        if type(site_support)~='function' then return false,'',true end
        local e=df.building_bridgest.T_direction
        local anchor=not r.retracting and ((r.direction==e.Up and p.y==r.y) or (r.direction==e.Down and p.y==r.y+r.height-1) or
            (r.direction==e.Left and p.x==r.x) or (r.direction==e.Right and p.x==r.x+r.width-1))
        local ok,reason,verified=site_support(p,'BridgeTile',1,1,anchor)
        if not verified then return false,'',true end
        return ok,reason,false
    end
    -- New families/custom raws require a verified native validation route.
    -- Never substitute local terrain, liquid or occupancy approximations.
    return false,'',true
end
local function area_connected(r,d)
    if type(site_support)~='function' then return false,'' end
    return site_support({x=r.x,y=r.y,z=r.z},d.family..'Connectivity',r.width,r.height)
end
local function farm_room(p,w,h,mask)
    local partial=false
    for _,v in ipairs(mask) do if v==0 then partial=true;break end end
    if not partial then return nil end
    local extents=df.reinterpret_cast(df.building_extents_type,df.new('uint8_t',w*h))
    for i=0,w*h-1 do extents[i]=mask[i+1] end
    return {x=p.x,y=p.y,width=w,height=h,extents=extents}
end
local function native_site(d,p,w,h,dir,mask)
    local b=B.allocInstance(p,d.type,d.subtype,custom(d))
    if not b then return false,'Native building allocation failed' end
    return dfhack.with_finalize(function()
        if b.room.extents then df.delete(b.room.extents);b.room.extents=nil end;df.delete(b)
    end,function()
        if extent_shaped[d.family] and mask then
            local room=farm_room(p,w,h,mask)
            if room then for k,v in pairs(room) do b.room[k]=v end end
        end
        if not B.setSize(b,w,h,dir) then return false,'Native placement check rejected this site' end;return true
    end)
end
local function raw_walkable_group(p)
    local block=dfhack.maps.getTileBlock(p)
    return block and block.walkable and block.walkable[p.x%16][p.y%16] or 0
end
local native_material_families={Bed=true,Chair=true,Table=true,Coffin=true,Cabinet=true,Box=true,Statue=true,Slab=true,Cage=true,Chain=true,Door=true,Hatch=true,GrateWall=true,GrateFloor=true,Floodgate=true,Armorstand=true,Weaponrack=true,TractionBench=true,Bookcase=true,DisplayFurniture=true,OfferingPlace=true,Instrument=true,NestBox=true,Hive=true,AnimalTrap=true,WindowGlass=true,Well=true,ScrewPump=true,WaterWheel=true,Windmill=true,GearAssembly=true,AxleVertical=true,AxleHorizontal=true,Rollers=true,BarsVertical=true,BarsFloor=true,WindowGem=true,Support=true,ArcheryTarget=true,TradeDepot=true,Weapon=true,Bridge=true,RoadPaved=true,Construction=true}
local native_workshops={Carpenters=true,Farmers=true,Masons=true,Craftsdwarfs=true,Jewelers=true,MetalsmithsForge=true,MagmaForge=true,Bowyers=true,Mechanics=true,Siege=true,Butchers=true,Leatherworks=true,Tanners=true,Clothiers=true,Fishery=true,Still=true,Loom=true,Quern=true,Kennels=true,Kitchen=true,Ashery=true,Dyers=true,Millstone=true}
local native_furnaces={WoodFurnace=true,Smelter=true,GlassFurnace=true,Kiln=true,MagmaSmelter=true,MagmaGlassFurnace=true,MagmaKiln=true}
local native_traps={Lever=true,PressurePlate=true,CageTrap=true,StoneFallTrap=true,WeaponTrap=true,TrackStop=true}
local native_siege_engines={Catapult=true,Ballista=true,BoltThrower=true}
local function native_material_family(d)
    return native_material_families[d.family]==true or
        (d.family=='Workshop' and (native_workshops[d.subtype_key]==true or
            (d.subtype_key=='Custom' and (d.custom_code=='SCREW_PRESS' or d.custom_code=='SOAP_MAKER')))) or
        (d.family=='Furnace' and native_furnaces[d.subtype_key]==true) or
        (d.family=='Trap' and native_traps[d.subtype_key]==true) or
        (d.family=='SiegeEngine' and native_siege_engines[d.subtype_key]==true)
end
local function native_candidates(fn,t,st,custom_id)
    local result=fn(t,st,custom_id or -1)
    if type(result)~='table' or result.status~=0 or type(result.candidates)~='table' then return nil end
    local sets={}
    for i,ids in ipairs(result.candidates) do
        if type(ids)~='table' then return nil end
        if #ids>65536 then return nil,nil,'list exceeds cap' end
        local set={};for _,id in ipairs(ids) do if math.type(id)~='integer' or id<0 then return nil end;set[id]=true end
        sets[i]=set
    end
    return sets,result.candidates
end
local function native_admitted(item,groups,ids)
    if not item or not ids[item.id] then return false end
    local p=xyz2pos(dfhack.items.getPosition(item))
    -- Collection owns flags, containment, suitability and material constraints.
    -- Placement connectivity is a separate stage from the native item collector.
    return p and groups[raw_walkable_group(p)]==true
end
local function key(v) return table.concat({v.item_type,v.item_subtype,v.mat_type,v.mat_index,v.individual_id or -1},':') end
local function standalone(item) return item.flags.artifact or (item.isImproved and item:isImproved()) or false end
local function item_key(item,exact) return key{item_type=item:getType(),item_subtype=item:getSubtype(),mat_type=item:getMaterial(),mat_index=item:getMaterialIndex(),individual_id=exact and standalone(item) and item.id or -1} end
local function item_row(item)
    local mi=dfhack.matinfo.decode(item);if not mi then return end
    local name=mi:toString();if not name or name=='' then return end
    return {item_type=item:getType(),item_subtype=item:getSubtype(),mat_type=item:getMaterial(),mat_index=item:getMaterialIndex(),name=clipped_utf8(dfhack.df2utf(name),128),caption='',count=0,ids={},individual=standalone(item),individual_id=standalone(item) and item.id or -1}
end
-- Cache identity includes the exact Materials origin (rectangle minimum corner,
-- bottom level). Place must reuse that origin and its revision. Moving the origin
-- scans anew; the four-slot LRU retains other sites but never serves their ordering
-- for the new site. Same-site replacement keeps its previous snapshot for Place.
local single_furniture={Bed=true,Chair=true,Table=true,Coffin=true,Cabinet=true,Box=true,Statue=true,Slab=true}
local additional_single_items={TractionBench=true,Bookcase=true,DisplayFurniture=true,OfferingPlace=true,Instrument=true,
    Door=true,Hatch=true,Cage=true,Chain=true,Armorstand=true,Weaponrack=true,GrateWall=true,GrateFloor=true,Floodgate=true,NestBox=true,Hive=true,['Workshop:Quern']=true,AnimalTrap=true,WindowGlass=true,['Trap:PressurePlate']=true}
for family in pairs(additional_single_items)do single_furniture[family]=true end
local neighbor_single_items={AnimalTrap=true,Statue=true,Hatch=true,GrateWall=true,GrateFloor=true,Floodgate=true}
local terrain_materials={['Construction:ReinforcedWall']=true,['Construction:Wall']=true,['Construction:Floor']=true,['Construction:Ramp']=true,['Construction:Fortification']=true,['Construction:Stairs']=true}
local fixed_material_recipes={['Workshop:Carpenters']=3,['Workshop:Masons']=3,['Workshop:Craftsdwarfs']=3,['Workshop:Mechanics']=3,['Workshop:Bowyers']=3,['Workshop:Jewelers']=3,['Workshop:Siege']=5,['Workshop:Ashery']=3,['Workshop:MetalsmithsForge']=3,['Workshop:Leatherworks']=3,['Workshop:Loom']=3,['Workshop:Clothiers']=3,['Workshop:Dyers']=3,['Workshop:Butchers']=3,['Workshop:Tanners']=3,['Workshop:Fishery']=3,['Workshop:Kitchen']=3,['Workshop:Farmers']=3,['Workshop:Still']=3,['Workshop:Kennels']=5,['Furnace:WoodFurnace']=3,['Furnace:Smelter']=3,['Furnace:GlassFurnace']=3,['Furnace:Kiln']=3}
for family,size in pairs({['Support']=1,['ArcheryTarget']=1,['BarsVertical']=1,['BarsFloor']=1,['WindowGem']=1,['TradeDepot']=5,['Trap:Lever']=1,['Trap:StoneFallTrap']=1,['Trap:CageTrap']=1,['GearAssembly']=1,['AxleVertical']=1,['Workshop:Millstone']=1,['Trap:TrackStop']=1})do fixed_material_recipes[family]=size end
for family,size in pairs({Well=1,ScrewPump=0,WaterWheel=0,Windmill=3,['SiegeEngine:Ballista']=3,['SiegeEngine:Catapult']=3,['SiegeEngine:BoltThrower']=1})do fixed_material_recipes[family]=size end
for family,size in pairs({['Workshop:Custom:SCREW_PRESS']=1,['Workshop:Custom:SOAP_MAKER']=3,['Workshop:MagmaForge']=3,['Furnace:MagmaSmelter']=3,['Furnace:MagmaGlassFurnace']=3,['Furnace:MagmaKiln']=3})do fixed_material_recipes[family]=size end
for _,family in ipairs{'RoadPaved','AxleHorizontal','Rollers'}do fixed_material_recipes[family]=0 end
fixed_material_recipes.Weapon=1;fixed_material_recipes['Trap:WeaponTrap']=1
local neighbor_fixed_recipes={Well=true,['BarsVertical']=true,['BarsFloor']=true,['GearAssembly']=true,['AxleVertical']=true,['Workshop:Millstone']=true}
local function material_footprint(family,width,height)
    if family=='ScrewPump' then return {width=1,height=1} end
    if family=='WaterWheel' or family=='RoadPaved' or family=='AxleHorizontal' or family=='Rollers' then return {width=width,height=height} end
    if fixed_material_recipes[family] then return {width=fixed_material_recipes[family],height=fixed_material_recipes[family]} end
    if family=='Bridge' or terrain_materials[family] then return {width=width,height=height} end
    if family=='Windmill' or magma_buildings[family] then return {width=3,height=3} end
end
local function signature(raw,site,family,width,height,depth,anchor,direction,native_filter)
    return filter_call(raw,function(j)
        local out={}
        for _,k in ipairs{'item_type','item_subtype','mat_type','mat_index','vector_id','has_tool_use','metal_ore','min_dimension','reaction_class','has_material_reaction_product','flags4','flags5'} do out[#out+1]=tostring(j[k]) end
        for _,k in ipairs{'flags1','flags2','flags3'} do out[#out+1]=tostring(j[k].whole) end
        local footprint=material_footprint(family,width,height)
        return table.concat(out,'|')..(native_filter and '|Native:'..family..':'..native_filter or '')..(family=='ScrewPump' and '|Direction:'..tostring(direction or 0) or '')..'|'..site.x..':'..site.y..':'..site.z..(footprint and '|Footprint:'..family..':'..footprint.width..':'..footprint.height or '')..(terrain_materials[family] and '|Volume:'..family..':'..width..':'..height..':'..(depth or 1)..'|Anchor:'..(anchor or site).x..':'..(anchor or site).y..':'..(anchor or site).z or '')
    end)
end
local function vectors(raw)
    return filter_call(raw,function(j)
        if j.vector_id>df.job_item_vector_id.IN_PLAY then return {j.vector_id} end
        if j.flags2.building_material then return {df.job_item_vector_id.BLOCKS,df.job_item_vector_id.BOULDER,df.job_item_vector_id.WOOD,df.job_item_vector_id.BAR} end
        return {df.job_item_vector_id.IN_PLAY}
    end)
end
local cache,clock={},0
local operation
local function generations(e) return math.max(1,(e.rows and 1 or 0)+(e.job and 1 or 0)) end
local function active_kinds() for _,e in ipairs(cache) do if e.job then return 8 end end;return 0 end
local function stats(result)
    local ids,entries=0,0;for _,e in ipairs(cache) do ids=ids+(e.ids or 0)+(e.build_ids or 0);entries=entries+generations(e) end
    result.active_kinds=active_kinds();result.active=result.active_kinds~=0;result.cache_entries=entries;result.cache_ids=ids
    return result
end
local function material_item_appearance(id)
    local item=df.item.find(id)
    if not item then return nil end
    local material=dfhack.matinfo.decode(item:getMaterial(),item:getMaterialIndex())
    if not material then return nil end
    local subtype=dfhack.items.getSubtypeDef(item:getType(),item:getSubtype())
    local color=item:getColorWhetherDyedOrNot();local colors=df.global.world.raws.descriptors.colors
    if color < -1 or color>=#colors then return nil end
    local a={material_token=dfhack.df2utf(material:getToken()),subtype_raw=subtype and dfhack.df2utf(subtype.id) or '',
        color_token=color>=0 and dfhack.df2utf(colors[color].id) or '',stack=item:getStackSize(),
        flags=(item.flags.artifact and 32 or 0)|(item.flags.spider_web and 64 or 0)}
    if a.material_token=='' or #a.material_token>256 or #a.subtype_raw>128 or #a.color_token>128 or
        math.type(a.stack)~='integer' or a.stack<1 or a.stack>0x7fffffff then return nil end
    if item:getType()==df.item_type.INSTRUMENT and subtype then
        local families={[df.job_skill.PLAY_KEYBOARD_INSTRUMENT]=0,[df.job_skill.PLAY_STRINGED_INSTRUMENT]=1,
            [df.job_skill.PLAY_WIND_INSTRUMENT]=2,[df.job_skill.PLAY_PERCUSSION_INSTRUMENT]=3}
        a.instrument_family=families[subtype.music_skill]
        if a.instrument_family~=nil then a.instrument_placed=subtype.flags.PLACED_AS_BUILDING and 1 or 0 end
    end
    if item:getType()==df.item_type.SMALLGEM then
        local shapes=df.global.world.raws.descriptors.shapes
        local shape=item.shape>=0 and item.shape<#shapes and shapes[item.shape] or nil
        if shape and #shape.id<=128 then a.gem_shape_raw=dfhack.df2utf(shape.id) end
    end
    if item:getType()==df.item_type.SLAB then
        local engraving=item.engraving_type
        if math.type(engraving)=='integer' and engraving>=-1 and engraving<=26 then a.slab_engraving=engraving end
    end
    if type(bed_facts)=='function' then a.bedding=bed_facts(id) end
    return a
end
local function appearance_extra_bytes(a)
    local b=a.bedding
    return (a.gem_shape_raw and (16+#a.gem_shape_raw) or 0)+(b and (64+#b.base_color+#b.sheet_color) or 0)+(a.instrument_family~=nil and 16 or 0)+(a.slab_engraving~=nil and 8 or 0)
end
local function appearance_extra_hash(h,a)
    local b=a.bedding
    if a.gem_shape_raw then h=hash(h,':gem:'..#a.gem_shape_raw..':'..a.gem_shape_raw) end
    if a.slab_engraving~=nil then h=hash(h,':slab:'..a.slab_engraving) end
    if a.instrument_family~=nil then h=hash(h,':instrument:'..a.instrument_family..':'..a.instrument_placed) end
    if b then h=hash(h,':'..b.sheet..':'..b.pillow..':'..#b.base_color..':'..b.base_color..':'..#b.sheet_color..':'..b.sheet_color) end
    return h
end
local function queue(e)
    -- A replacement and its readable predecessor each consume one of the four
    -- 65,536-id slots. Evict another signature before allocating a replacement.
    local slots=e.rows and 1 or 0
    for _,v in ipairs(cache) do slots=slots+generations(v) end
    while slots>4 do
        local oldest
        for i,v in ipairs(cache) do if v~=e and (not oldest or v.used<cache[oldest].used) then oldest=i end end
        slots=slots-generations(cache[oldest]);table.remove(cache,oldest)
    end
    e.phase=1;e.done=0;e.total=0;e.build_ids=0;e.error=nil;e.native_message=nil;e.error_reported=false;e.retry_requested=nil
    local vids=vectors(e.raw)
    for _,vid in ipairs(vids) do e.total=e.total+#df.global.world.items.other[df.job_item_vector_id.attrs[vid].other] end
    e.total=e.total+#df.global.world.units.active;e.started=tick()
    -- Opt-in diagnostics only; absent during ordinary play. Retain scalar timings,
    -- never native objects, and do not add these overlapping intervals together.
    e.profile=nil
    if type(dfhack.df3d_construction_profile)=='table' then
        e.profile={family=e.family,started_ms=dfhack.getTickCount(),active_ms=0,slices=0,max_slice_ms=0}
        table.insert(dfhack.df3d_construction_profile,e.profile)
    end
    local reservation_version=e.reservation_version or 0
    e.job=coroutine.create(function()
        local function step() e.done=e.done+1;e.total=math.max(e.total,e.done);coroutine.yield() end
        local groups={}
        local furniture=single_furniture[e.family] or false
        if e.family=='Construction:ReinforcedWall' then
            -- Native reinforced_admission: minimum corner plus outer perimeter,
            -- not the ordinary terrain volume/last-corner admission rule.
            local function add(p)local g=raw_walkable_group(p);if g~=0 then groups[g]=true end;step()end
            add(e.site)
            for dx=0,e.width-1 do add{x=e.site.x+dx,y=e.site.y-1,z=e.site.z};add{x=e.site.x+dx,y=e.site.y+e.height,z=e.site.z}end
            for dy=0,e.height-1 do add{x=e.site.x-1,y=e.site.y+dy,z=e.site.z};add{x=e.site.x+e.width,y=e.site.y+dy,z=e.site.z}end
        elseif terrain_materials[e.family] then
            -- Native stairs_placement.material_admission_reference: every
            -- selected tile contributes cardinal neighbors; only the last
            -- selected corner contributes its center (including reverse stairs).
            local function add(p)local g=raw_walkable_group(p);if g~=0 then groups[g]=true end;step()end
            add(e.anchor)
            for dz=0,e.depth-1 do for dy=0,e.height-1 do for dx=0,e.width-1 do
                local x,y,z=e.site.x+dx,e.site.y+dy,e.site.z+dz
                for _,delta in ipairs{{-1,0},{1,0},{0,-1},{0,1}}do add{x=x+delta[1],y=y+delta[2],z=z}end
            end end end
        elseif e.family=='RoadPaved' then
            for dy=0,e.height-1 do for dx=0,e.width-1 do
                local g=raw_walkable_group{x=e.site.x+dx,y=e.site.y+dy,z=e.site.z}
                if g~=0 then groups[g]=true end;step()
            end end
        elseif e.family=='ScrewPump' then
            local g=raw_walkable_group{x=e.site.x+(e.direction==1 and 1 or 0),y=e.site.y+(e.direction==2 and 1 or 0),z=e.site.z}
            if g~=0 then groups[g]=true end;step()
        elseif e.family=='Bridge' or e.family=='WaterWheel' or e.family=='Windmill' or e.family=='AxleHorizontal' or e.family=='Rollers' then
            -- Native bridge_placement.material_groups: only cardinal perimeter
            -- tags admit materials, independent of citizen and interior tags.
            -- Read full-width IDs; neither visibility nor occupancy filters
            -- are applied to this raw-group collection by the native picker.
            local function add(x,y)
                local g=raw_walkable_group{x=x,y=y,z=e.site.z}
                if g~=0 then groups[g]=true end
                step()
            end
            for x=e.site.x,e.site.x+e.footprint.width-1 do add(x,e.site.y-1);add(x,e.site.y+e.footprint.height) end
            for y=e.site.y,e.site.y+e.footprint.height-1 do add(e.site.x-1,y);add(e.site.x+e.footprint.width,y) end
        elseif neighbor_single_items[e.family] or neighbor_fixed_recipes[e.family] or (df.item_type.STATUE~=nil and e.raw.item_type==df.item_type.STATUE) then
            -- Native furniture_material_copy admission fixtures: Statue,
            -- Hatch, both grates and Floodgate admit cardinal neighbor groups.
            for _,delta in ipairs{{-1,0},{1,0},{0,-1},{0,1}} do
                local g=raw_walkable_group{x=e.site.x+delta[1],y=e.site.y+delta[2],z=e.site.z}
                if g~=0 then groups[g]=true end
                step()
            end
        elseif fixed_material_recipes[e.family] and not neighbor_fixed_recipes[e.family] then
            -- workshop_admission_reference: the native center admits materials;
            -- navigation costs separately start from the entire footprint.
            local half=fixed_material_recipes[e.family]//2
            local g=raw_walkable_group{x=e.site.x+half,y=e.site.y+half,z=e.site.z}
            if g~=0 then groups[g]=true end
            step()
        elseif furniture then
            -- Native single-tile furniture eligibility follows the placement
            -- site, not current citizen positions (furniture_material_copy).
            -- DFHack's convenience reader truncates group IDs to uint16.
            local g=raw_walkable_group(e.site)
            if g~=0 then groups[g]=true end
            step()
        else
            for i=0,#df.global.world.units.active-1 do
                local u=i<#df.global.world.units.active and df.global.world.units.active[i] or nil
                if u and not dfhack.units.isDead(u) and dfhack.units.isActive(u) and (dfhack.units.isCitizen(u) or dfhack.units.isResident(u)) then local g=dfhack.maps.getWalkableGroup(xyz2pos(dfhack.units.getPosition(u)));if g~=0 then groups[g]=true end end
                u=nil;step()
            end
        end
        local rows,grouped,seen,candidates={},{},{},{}
        local native_sets,native_lists,native_error=native_candidates(e.native_query,e.native_type,e.native_subtype,e.native_custom)
        if not native_sets or not native_sets[e.native_filter] then
            e.error=native_error or 'native material collection unavailable'
            if not native_error then e.native_message='' end
            e.phase=3;return
        end
        local native_ids=native_lists[e.native_filter]
        for i=1,#native_ids do
            local item=df.item.find(native_ids[i])
            if item and not seen[item.id] and native_admitted(item,groups,native_sets[e.native_filter]) then
                local row=item_row(item)
                if row then
                    -- Legacy aggregate families have no exact-item payload yet.
                    -- Preserve their existing grouping until that migration;
                    -- never emit a standalone identity without its candidate.
                    if not furniture and not e.footprint then row.individual=false;row.individual_id=-1 end
                    if e.build_ids>=65536 then e.error='list exceeds cap';e.phase=3;item=nil;step();return end
                    local k=key(row);local g=grouped[k]
                    if not g then g=row;grouped[k]=g;rows[#rows+1]=g end
                    local p=xyz2pos(dfhack.items.getPosition(item))
                    g.ids[#g.ids+1]=item.id;g.count=g.count+1;seen[item.id]=true;e.build_ids=e.build_ids+1
                    if furniture or e.footprint then candidates[#candidates+1]={id=item.id,position=p,enabled=true} end
                end
            end
            item=nil;step()
        end
        -- Use verbatim item descriptions for independently verified families.
        -- This corrects labels only; generic eligibility/grouping/order below
        -- retain their separately documented unfinished behavior.
        if material_group_name then
            for _,row in ipairs(rows) do
                local name=material_group_name(row)
                if name then row.name=clipped_utf8(name,128) end
                local last=material_group_name(row,nil,true)
                row.last_name=last and #last<=128 and last or ''
            end
        end
        if e.profile then e.profile.scan_elapsed_ms=dfhack.getTickCount()-e.profile.started_ms end
        e.phase=2
        if furniture or e.footprint then
            -- Native material navigation uses the semantic placement footprint.
            -- The callback owns a fresh native computation at this safe point.
            -- Unknown/capped searches cannot publish a geometric fallback.
            if not material_order or not e.material_distances then
                e.error='material navigation unavailable';e.phase=3;return
            end
            for _,row in ipairs(rows) do table.sort(row.ids) end
            table.sort(rows,function(a,b)
                if a.individual~=b.individual then return not a.individual end
                return a.ids[1]<b.ids[1]
            end)
            local seeds
            if e.footprint then
                -- Native Windmill, magma and Bridge costs start from the whole
                -- footprint. Bridge dimensions also belong to cache identity.
                seeds={}
                local seed_z=terrain_materials[e.family] and (e.site.z+e.depth-1-(e.anchor.z-e.site.z)) or e.site.z
                for dx=0,e.footprint.width-1 do for dy=0,e.footprint.height-1 do seeds[#seeds+1]={x=e.site.x+dx,y=e.site.y+dy,z=seed_z} end end
            end
            if e.family=='ScrewPump' then seeds={{x=e.site.x+(e.direction==1 and 1 or 0),y=e.site.y+(e.direction==2 and 1 or 0),z=e.site.z}} end
            -- Native stairs add their own vertical search seeds. Other recipes
            -- use the semantic footprint already selected above.
            local subtype=terrain_materials[e.family] and df.construction_type[e.family=='Construction:Stairs' and 'UpDownStair' or e.family:match(':(.+)$')] or nil
            local function search(starts,targets)
                return e.material_distances(starts,targets,subtype)
            end
            local navigation_started=e.profile and dfhack.getTickCount()
            local ordered=material_order({status=0,candidates=candidates,initial_groups=rows},e.site,
                search,seeds)
            if e.profile then e.profile.navigation_ms=dfhack.getTickCount()-navigation_started end
            local details_started=e.profile and dfhack.getTickCount()
            if ordered.status~=0 then e.native_message=ordered.native_message;e.error=ordered.native_message or ('material navigation unavailable: '..(ordered.reason or tostring(ordered.status)));e.phase=3;return end
            local costs={}
            for _,row in ipairs(ordered.candidate_distances) do costs[row.id]=row.distance end
            rows=ordered.groups
            for _,row in ipairs(rows) do
                -- Native group clicks choose nearest, with highest-ID ties.
                -- Reserve that order; expanded display order is a separate UI fact.
                table.sort(row.ids,function(a,b)return costs[a]<costs[b] or (costs[a]==costs[b] and a>b) end)
                row.costs=costs;grouped[key(row)]=row
                if e.footprint or single_furniture[e.family] then
                    row.candidates={};row.wire_bytes=512+#row.name+#(row.last_name or '')
                    for _,id in ipairs(row.expanded_ids) do
                        local name=material_group_name and material_group_name(row,id)
                        local appearance=material_item_appearance(id)
                        if not name or name=='' or #name>128 or not appearance then
                            e.error='material details unavailable';e.phase=3;return
                        end
                        row.candidates[#row.candidates+1]={id=id,name=name,distance=costs[id],appearance=appearance}
                        row.wire_bytes=row.wire_bytes+192+#name+#appearance.material_token+#appearance.subtype_raw+#appearance.color_token+appearance_extra_bytes(appearance)
                    end
                    if #row.candidates>16384 or row.wire_bytes>380*1024 then
                        e.error='list exceeds cap';e.phase=3;return
                    end
                end
            end
            if e.profile then e.profile.details_ms=dfhack.getTickCount()-details_started end
        else
            -- Unknown recipes cannot publish an invented geometric ordering.
            e.native_message='';e.error='material navigation unavailable';e.phase=3;return
        end
        local h=hash(0xcbf29ce484222325,tostring(e.epoch)..'|'..e.signature,step)
        -- A numeric identity tuple is at most 42 bytes; each tuple/id hash is one bounded step.
        for _,row in ipairs(rows) do h=hash(h,'|'..key(row));step()
            h=hash(h,':'..#(row.last_name or '')..':'..(row.last_name or ''))
            for _,id in ipairs(row.ids) do
                h=hash(h,':'..tostring(id)..(row.costs and ':'..row.costs[id] or ''));step()
            end
            for _,item in ipairs(row.candidates or {}) do
                h=hash(h,':'..#item.name..':'..item.name)
                for _,field in ipairs{'material_token','subtype_raw','color_token'} do
                    local value=item.appearance[field];h=hash(h,':'..#value..':'..value)
                end
                h=hash(h,':'..item.appearance.stack..':'..item.appearance.flags);h=appearance_extra_hash(h,item.appearance);step()
            end
        end
        if e.profile then e.profile.elapsed_ms=dfhack.getTickCount()-e.profile.started_ms;e.profile.items=e.build_ids;e.profile.groups=#rows end
        e.rows=rows;e.by_key=grouped;e.groups=groups;e.revision=revision(h);e.ids=e.build_ids;e.build_ids=0;e.dirty=(e.reservation_version or 0)~=reservation_version;e.scan_tick=e.started;e.phase=0;e.total=e.done
    end)
end
local function entry(epoch,raw,site,material_distances,family,width,height,depth,anchor,direction,native_query,native_type,native_subtype,native_filter,native_custom)
    local sig=signature(raw,site,family,width,height,depth,anchor,direction,native_query and native_filter or nil);clock=clock+1
    for _,e in ipairs(cache) do if e.epoch==epoch and e.signature==sig then e.used=clock;return e end end
    if #cache==4 then local oldest=1;for i=2,4 do if cache[i].used<cache[oldest].used then oldest=i end end;table.remove(cache,oldest) end
    local e={epoch=epoch,signature=sig,raw=raw,site=site,direction=direction or 0,family=family,width=width,height=height,depth=depth or 1,anchor=anchor or site,used=clock,material_distances=material_distances,native_query=native_query,native_type=native_type,native_subtype=native_subtype,native_filter=native_filter,native_custom=native_custom,footprint=material_footprint(family,width,height)};cache[#cache+1]=e;queue(e);return e
end
local function build(budget)
    local steps=0
    local slice_started
    local profiles={}
    while steps<budget do
        local e;for _,v in ipairs(cache) do if v.job then e=v;break end end;if not e then break end
        local started=e.profile and dfhack.getTickCount()
        if e.profile then profiles[e.profile]=true;slice_started=slice_started or started end
        local ok,err=coroutine.resume(e.job)
        if e.profile then e.profile.active_ms=e.profile.active_ms+dfhack.getTickCount()-started end
        if not ok then e.error=tostring(err);e.phase=3;e.job=nil;e.build_ids=0
        elseif coroutine.status(e.job)=='dead' then e.job=nil;e.build_ids=0
        else steps=steps+1 end
    end
    for p in pairs(profiles) do p.slices=p.slices+1;p.max_slice_ms=math.max(p.max_slice_ms,dfhack.getTickCount()-slice_started) end
    return stats{ok=true,message='',steps=steps}
end
local function materials(r,d)
    if not native_material_family(d) or type(r.native_material_candidates)~='function' then
        return {ok=false,message='',build_phase=3}
    end
    local inputs=recipe(d);local raw=inputs and inputs[(r.filter or -1)+1]
    if not raw then return fail('Building has no recipe') end
    local e=entry(r.epoch,raw,{x=r.x,y=r.y,z=r.z},r.material_distances,d.key,r.width,r.height,r.depth,r.material_anchor,r.direction,r.native_material_candidates,d.type,d.subtype,(r.filter or -1)+1,custom(d))
    if e.error then
        -- A deterministic cap error stays stopped across Materials polls. A
        -- first-page Catalog refresh explicitly arms one retry. Other errors
        -- retain their existing report-once, subsequent-request retry behavior.
        if not e.retry_requested and (e.error=='list exceeds cap' or not e.error_reported) then
            e.error_reported=true
            return {ok=false,message=e.native_message or ('Materials list unavailable: '..e.error),build_phase=3,
                build_done=e.done,build_total=e.total}
        end
        e.retry_requested=nil;queue(e)
    elseif not e.job and e.rows and (e.dirty or tick()-e.scan_tick>1200 or tick()<e.scan_tick) then queue(e) end
    local result={ok=true,building_key=d.key,filter=r.filter,filters=d.filters,estimated=true,materials={},total=e.ids or 0,
        build_phase=e.phase,build_done=e.done,build_total=e.total,list_revision=e.revision or 0,message=''}
    if e.job then return result end
    if (r.expected_list_revision or 0)~=0 and r.expected_list_revision~=e.revision then return fail('List changed; refresh') end
    local cursor=r.cursor or 0
    local bytes,candidates,next_cursor=4096,0,cursor
    while next_cursor<#e.rows and #result.materials<128 do
        local row=e.rows[next_cursor+1];local count=row.candidates and #row.candidates or 0
        if bytes+(row.wire_bytes or 512)>384*1024 or candidates+count>16384 then break end
        bytes=bytes+(row.wire_bytes or 512);candidates=candidates+count
        result.materials[#result.materials+1]=row;next_cursor=next_cursor+1
    end
    if next_cursor==cursor and cursor<#e.rows then return fail('Materials list unavailable') end
    result.next_cursor=next_cursor<#e.rows and next_cursor or 0;result.total=#e.rows;return result
end
-- Stable ordered geometry and pending/terrain expectations belong to the material
-- snapshot identity, even when endpoints and the number of new pieces agree.
local function track_plan_identity(plan)
    if type(plan.pieces)~='table' or #plan.pieces<2 or #plan.pieces>16384 then return nil end
    local parts={tostring(plan.new_count)};local owned={}
    local integers={'x','y','z','action','building_id','connections','expected_connections',
        'expected_terrain_connections','expected_terrain_kind'}
    local booleans={'ramp','expected_job_ramp','expected_terrain_ramp'}
    for _,piece in ipairs(plan.pieces) do
        local copy={}
        local expected_subtype=piece.expected_subtype or -1
        if math.type(expected_subtype)~='integer' or expected_subtype< -1 then return nil end
        copy.expected_subtype=expected_subtype;parts[#parts+1]=tostring(expected_subtype)
        for _,field in ipairs(integers) do
            local value=piece[field]
            if math.type(value)~='integer' then return nil end
            parts[#parts+1]=tostring(value);copy[field]=value
        end
        for _,field in ipairs(booleans) do
            local value=piece[field]
            if type(value)~='boolean' then return nil end
            parts[#parts+1]=value and '1' or '0';copy[field]=value
        end
        owned[#owned+1]=copy
    end
    return table.concat(parts,':'),owned
end
local function track_snapshot_signature(r)
    if not r.connected_track_destination or not track_site_reader or
        not track_material_candidates or not material_order or type(r.route_track)~='function' or
        type(r.plan_track)~='function' or type(r.material_distances)~='function' then return nil end
    local d=r.connected_track_destination
    return table.concat({'track-materials',r.epoch or 0,r.x,r.y,r.z,d.x,d.y,d.z},':')
end
local function fresh_track_snapshot(r,signature)
    local start={x=r.x,y=r.y,z=r.z};local destination=r.connected_track_destination
    local x,y,z=dfhack.maps.getTileSize();local maximum={x=x-1,y=y-1,z=z-1}
    local route=r.route_track(track_site_reader,start,destination,maximum)
    if route.status~=0 then return nil end
    local plan=r.plan_track(track_site_reader,route.path)
    if not plan.verified then return nil end
    local plan_key,pieces=track_plan_identity(plan)
    if not plan_key then return nil end
    local snapshot,ordered
    if plan.new_count==0 then
        -- Reusing every job needs no material search or picker. Unrelated stock
        -- and navigation failures cannot prevent an input-free conversion.
        snapshot={candidates={}};ordered={groups={},candidate_distances={}}
    else
        local definition=by_key['Construction:Track']
        snapshot=track_material_candidates(route.path,65536,r.native_material_candidates,definition.type,definition.subtype)
        if snapshot.status~=0 then return nil end
        ordered=material_order(snapshot,destination,r.material_distances)
        if ordered.status~=0 then return nil end
    end
    local by_id,costs={},{}
    for _,item in ipairs(snapshot.candidates) do by_id[item.id]=item end
    for _,item in ipairs(ordered.candidate_distances) do costs[item.id]=item.distance end
    local rows={};local h=hash(0xcbf29ce484222325,signature..':'..plan_key)
    for _,group in ipairs(ordered.groups) do
        if group.individual or type(group.name)~='string' or group.name=='' or #group.name>128 then return nil end
        local row={item_type=group.item_type,item_subtype=group.item_subtype,mat_type=group.mat_type,
            mat_index=group.mat_index,name=group.name,caption='',count=#group.ids,candidates={}}
        local last=material_group_name and material_group_name(group,nil,true)
        row.last_name=last and #last<=128 and last or ''
        local bytes=512+#row.name+#row.last_name
        h=hash(h,key(row)..':'..#row.name..':'..row.name..':'..#row.last_name..':'..row.last_name)
        for _,id in ipairs(group.expanded_ids) do
            local item=by_id[id]
            if not item or type(item.name)~='string' or item.name=='' or #item.name>128 or costs[id]==nil then return nil end
            local appearance=material_item_appearance(id)
            if not appearance then return nil end
            row.candidates[#row.candidates+1]={id=id,name=item.name,distance=costs[id],appearance=appearance}
            bytes=bytes+192+#item.name+#appearance.material_token+#appearance.subtype_raw+#appearance.color_token+appearance_extra_bytes(appearance)
            h=hash(h,table.concat({id,costs[id],item.position.x,item.position.y,item.position.z},':')..':'..#item.name..':'..item.name)
            for _,field in ipairs{'material_token','subtype_raw','color_token'}do
                local value=appearance[field];h=hash(h,':'..#value..':'..value)
            end
            h=hash(h,':'..appearance.stack..':'..appearance.flags);h=appearance_extra_hash(h,appearance)
        end
        -- Conservative wire accounting leaves room in the 512KiB envelope;
        -- never truncate one group's complete candidate vector.
        if bytes>384*1024 then return nil end
        row.wire_bytes=bytes;rows[#rows+1]=row
    end
    local raw=recipe(by_key['Construction:Track']);local filters={};local required=0
    for i,v in ipairs(raw or {}) do
        local f=filter_row(v,i-1);f.quantity=(f.quantity==-1 and 1 or f.quantity)*plan.new_count
        required=required+f.quantity;filters[#filters+1]=f
    end
    if #filters~=1 or required>65535 then return nil end
    return {signature=signature,epoch=r.epoch,plan_key=plan_key,pieces=pieces,rows=rows,
        ids=#ordered.candidate_distances,revision=revision(h),filters=filters,required=required}
end
local function retained_track_snapshot(r,signature)
    for _,entry in ipairs(cache) do
        if entry.signature==signature and entry.epoch==r.epoch then return entry end
    end
end
local function prepare_track_placement(r)
    if not track_placement_plan then return nil end
    local signature=track_snapshot_signature(r)
    if not signature then return nil end
    local retained=retained_track_snapshot(r,signature)
    -- Capture separately: a refused Place must not replace the selection's cache.
    local fresh=fresh_track_snapshot(r,signature)
    if not fresh then return nil end
    if fresh.required==0 and #(r.selections or {})==0 then retained=fresh end
    if not retained then return nil end
    return track_placement_plan(retained,fresh,r.selections or {})
end
local function commit_track_placement(r,prepared)
    local function refused() return {ok=false,message='',construction_outcome=2,placement_valid=prepared~=nil} end
    if not prepared or not track_commit then return refused() end
    local subtypes,items,pending={},{},{}
    local function subtype(mask,ramp)
        local name=ramp and 'TrackRamp' or 'Track'
        for bit,letter in ipairs{'N','S','E','W'}do
            if mask & (1 << (bit-1))~=0 then name=name..letter end
        end
        return df.construction_type[name]
    end
    for _,piece in ipairs(prepared.pieces) do
        subtypes[piece]=subtype(piece.connections,piece.ramp)
        if not subtypes[piece] then return refused() end
        if piece.action==0 then
            local item=df.item.find(piece.item_id)
            if not item or item.flags.in_job then return refused() end
            items[piece]=item
        else
            local b=df.building.find(piece.building_id)
            if not b or b:getType()~=df.building_type.Construction or b:getBuildStage()~=0 or B.markedForRemoval(b) or
                b.x1~=piece.x or b.y1~=piece.y or b.z~=piece.z or
                b:getSubtype()~=((piece.expected_subtype or -1)>=0 and piece.expected_subtype or subtype(piece.expected_connections,piece.expected_job_ramp)) or
                #b.jobs~=1 or b.jobs[0].job_type~=df.job_type.ConstructBuilding then return refused() end
            pending[piece]=b
        end
    end
    -- Fresh facts and commit run synchronously at the same safe point. Never
    -- retain native item references in the cache or yield between these steps.
    local result=track_commit(prepared,function(piece)
        if piece.action==1 then
            -- Native pending crossing preserves job/items/flags and changes only
            -- construction subtype; see pending_update_capture.
            local b=pending[piece];b.type=subtypes[piece]
            return {outcome='applied',building_id=b.id}
        end
        local b=B.constructBuilding{type=df.building_type.Construction,subtype=subtypes[piece],
            pos={x=piece.x,y=piece.y,z=piece.z},width=1,height=1,full_rectangle=true,items={items[piece]}}
        if not b then return {outcome='rejected'} end
        return {outcome='applied',building_id=b.id}
    end)
    -- Consumed/uncertain intent cannot reuse the retained selection snapshot.
    local signature=track_snapshot_signature(r)
    for index=#cache,1,-1 do if cache[index].signature==signature then table.remove(cache,index)end end
    if not result then return {ok=false,message='',construction_outcome=4} end
    local outcomes={complete=1,rejected=2,partial=3,unknown=4}
    local changed=result.completed
    if result.outcome=='unknown' then changed=prepared.pieces end
    return {ok=result.outcome=='complete',message='',building_key='Construction:Track',
        construction_outcome=outcomes[result.outcome],placed=result.created,updated=result.updated,
        first_building=result.first_building,failed_index=result.failed_index or -1,
        required=prepared.required,placement_valid=true,changed_tiles=changed}
end
local function track_materials(r)
    local function unavailable() return {ok=false,message='',build_phase=3} end
    local signature=track_snapshot_signature(r)
    if r.filter~=0 or not signature then return unavailable() end
    local expected=r.expected_list_revision or 0;local cursor=r.cursor or 0
    local e=retained_track_snapshot(r,signature)
    if expected~=0 then
        if not e or e.revision~=expected then return unavailable() end
    else
        if cursor~=0 then return unavailable() end
        local fresh=fresh_track_snapshot(r,signature)
        if not fresh then return unavailable() end
        if e then
            for index,entry in ipairs(cache) do if entry==e then cache[index]=fresh;break end end
        else
            if #cache==4 then local oldest=1;for i=2,#cache do if cache[i].used<cache[oldest].used then oldest=i end end;table.remove(cache,oldest) end
            cache[#cache+1]=fresh
        end
        e=fresh
    end
    clock=clock+1;e.used=clock
    if cursor<0 or cursor>#e.rows then return unavailable() end
    local result={ok=true,message='',building_key='Construction:Track',filter=0,filters=e.filters,
        required=e.required,estimated=false,materials={},total=#e.rows,list_revision=e.revision,build_phase=0}
    local bytes,next_cursor=4096,cursor
    while next_cursor<#e.rows and #result.materials<128 do
        local row=e.rows[next_cursor+1]
        if bytes+row.wire_bytes>384*1024 then break end
        bytes=bytes+row.wire_bytes;result.materials[#result.materials+1]=row;next_cursor=next_cursor+1
    end
    if next_cursor==cursor and cursor<#e.rows then return unavailable() end
    result.next_cursor=next_cursor<#e.rows and next_cursor or 0
    return result
end
local function building_key(b)
    local family=df.building_type[b:getType()]
    if family=='Workshop' or family=='Furnace' then
        local e=family=='Workshop' and df.workshop_type or df.furnace_type
        if e[b:getSubtype()]=='Custom' then local v=df.building_def.find(b:getCustomType());return family..':Custom:'..(v and v.code or '') end
        return family..':'..e[b:getSubtype()]
    end
    local enums={Trap=df.trap_type,SiegeEngine=df.siegeengine_type,Construction=df.construction_type}
    return family..(enums[family] and ':'..enums[family][b:getSubtype()] or '')
end
local function inspect(b)
    return {ok=true,building_id=b.id,building_key=building_key(b),build_stage=b:getBuildStage(),max_stage=b:getMaxBuildStage(),
        removing=B.markedForRemoval(b),jobs=#b.jobs,message=dfhack.df2utf(B.getName(b))}
end
local function position(r,index) return {x=r.x+index%r.width,y=r.y+(index//r.width)%r.height,z=r.z+index//(r.width*r.height)} end
local function placement(r,d)
    if r.action==2 and native_material_family(d) and type(r.native_material_candidates)~='function' then return fail('') end
    local native_sets
    local function eligible(item,groups,index)
        if not native_material_family(d) then return false end
        if not native_sets then native_sets=native_candidates(r.native_material_candidates,d.type,d.subtype,custom(d)) end
        return native_sets and native_sets[index] and native_admitted(item,groups,native_sets[index]) or false
    end
    local pp=r.pressure_plate
    if d.family=='Trap' and d.subtype_key=='PressurePlate' then
        if type(pp)~='table' then return fail('Invalid pressure plate intent') end
        for _,key in ipairs{'units','water','magma','citizens','resets','track'} do
            if type(pp[key])~='boolean' then return fail('Invalid pressure plate intent') end
        end
        local function integer(v,lo,hi) return type(v)=='number' and v%1==0 and v>=lo and v<=hi end
        local function weight(v) return integer(v,1,2000) and (v==1 or v%50==0) end
        if not integer(pp.unit_min,1000,200000) or pp.unit_min%1000~=0 or
           not integer(pp.unit_max,pp.unit_min,200999) or (pp.unit_max~=200000 and pp.unit_max%1000~=999) or
           not integer(pp.water_min,0,7) or not integer(pp.water_max,pp.water_min,7) or
           not integer(pp.magma_min,0,7) or not integer(pp.magma_max,pp.magma_min,7) or
           not weight(pp.track_min) or not weight(pp.track_max) or pp.track_min>pp.track_max then
            return fail('Invalid pressure plate intent')
        end
    elseif pp then return fail('Unexpected pressure plate intent') end
    local ts=r.track_stop
    if d.family=='Trap' and d.subtype_key=='TrackStop' then
        if type(ts)~='table' or not ({[10]=true,[50]=true,[500]=true,[10000]=true,[50000]=true})[ts.friction] or
           type(ts.dump_direction)~='number' or ts.dump_direction%1~=0 or ts.dump_direction<0 or ts.dump_direction>4 then return fail('Invalid track stop intent') end
    elseif ts then return fail('Unexpected track stop intent') end
    if (r.roller_speed or 0)~=0 and (d.family~='Rollers' or r.roller_speed<10000 or r.roller_speed>50000 or r.roller_speed%10000~=0) then return fail('Invalid roller speed intent') end
    if d.area_mode==4 and r.depth==1 then return fail('Must span multiple elevations') end
    local dir=r.retracting and -1 or r.direction
    if (r.direction>3 and d.family~='SiegeEngine') or (r.retracting and d.family~='Bridge') or d.orientations & (1<<(r.retracting and 4 or dir))==0 then return fail('Orientation not available for this building') end
    if r.depth>1 and d.area_mode~=4 then return fail('Depth applies to stairs only') end
    local mw,mh=d.max_width,d.max_height
    if d.family=='AxleHorizontal' then mw=dir==1 and 1 or 31;mh=dir==1 and 31 or 1
    elseif d.family=='Rollers' then mw=dir%2==0 and 1 or 31;mh=dir%2==0 and 31 or 1 end
    if r.width>mw or r.height>mh or r.depth>d.max_depth then return fail("Size exceeds this building's limits") end
    local fp=footprint(d,r.width,r.height,dir)
    if d.area_mode==1 and (r.width~=fp.width or r.height~=fp.height) then return fail('This building has a fixed size') end
    local function pressure_trigger()
        if not pp then return true,'',true end
        if type(site_support)~='function' then return false,'',false end
        return site_support({x=r.x,y=r.y,z=r.z},'PressurePlateTrigger',1,1,pp)
    end
    local trigger_ok,trigger_reason,trigger_verified=pressure_trigger()
    if not trigger_verified then return fail('') end
    if not operation or operation.seq~=r.seq then
        local raw=recipe(d);local quantities
        -- Area/route recipes receive their final quantities in a later native
        -- stage. Fixed recipes use initial counts, including Pressure Plate's
        -- default one mechanism before its trigger controls are configured.
        local later_quantity=d.family=='Construction' or d.family=='Bridge' or d.family=='RoadPaved' or d.family=='AxleHorizontal' or d.family=='Rollers'
        if native_material_family(d) and not later_quantity then
            if type(r.native_material_recipe)~='function' then return fail('') end
            local native=r.native_material_recipe(d.type,d.subtype,custom(d))
            if type(native)~='table' or native.status~=0 or type(native.recipes)~='table' or type(raw)~='table' or #native.recipes~=#raw then return fail('') end
            quantities={}
            for i,v in ipairs(native.recipes) do
                local q=type(v)=='table' and v.count_required
                if math.type(q)~='integer' or q<1 or q>32767 then return fail('') end
                quantities[i]=q
            end
        end
        operation={seq=r.seq,index=0,phase='tiles',mask={},pieces={},filters={},placed=0,skipped=0,first=-1,raw=raw,quantities=quantities,reserved={},used={},selection=1,scan=1,create=0,entries={},reused=0}
        if uses_machine_support(d) then operation.machine_supported,operation.machine_hookups=machine_connection(r,d) end
    end
    local o=operation;local aggregate=(d.area_mode<=2 and not extent_shaped[d.family]) or d.family=='Construction'
    o.refusals=o.refusals or {};o.extent_terrain=o.extent_terrain or {}
    local steps,chunk,attempts=0,0,0;local budget=math.min(r.step_budget or 1536,1536);local volume=r.width*r.height*r.depth
    local function reply(message,ok,pending)
        if not ok and o.placed>0 and d.area_mode>=3 then message='Painted '..o.placed..' of '..volume..'; '..message end
        local out={ok=ok,pending=pending,message=message,steps=steps,placed=o.placed,skipped=o.skipped,first_building=o.first,chunk_placed=chunk,
            warnings=o.warnings or '',building_key=d.key,filters=o.filters,valid_mask=o.mask,pieces=o.pieces,footprint=fp,placement_valid=o.phase~='tiles',required=o.required or 0,inputs={}}
        if not pending then operation=nil end;return out
    end
    if not trigger_ok and o.phase~='tiles' then return reply(trigger_reason,false,false) end
    while o.phase=='tiles' and o.index<volume and steps<budget do
        local p=position(r,o.index);local piece=d.area_mode==4 and stair_piece(r,p) or nil
        local terrain=extent_shaped[d.family] and {} or nil
        local ok,reason,fatal=tile_rule(r,d,p,piece,o.machine_supported,terrain);steps=steps+1
        local order=(p.z-r.z)*r.width*r.height+(p.x-r.x)*r.height+(p.y-r.y)+1
        if terrain then o.extent_terrain[order]=terrain.accepted;o.any_extent_terrain=o.any_extent_terrain or terrain.accepted end
        if reason=='Existing construction job' then o.reused=o.reused+1
        elseif not ok and not o.first_refusal then o.first_refusal=reason end
        -- Complete known farm/road refusals so native area ordering and warning
        -- aggregation see the whole rectangle. Unknown results fail immediately.
        if fatal then return reply(reason,false,false) end
        if (aggregate or terrain) and not ok and reason~='Existing construction job' then
            -- Native 3c1930 scans x then y and deduplicates tile results.
            -- Preserve that ordering independently of the incremental scan.
            o.refusals[order]=reason
        end
        o.mask[#o.mask+1]=ok and 1 or 0;if piece then o.pieces[#o.pieces+1]=piece end;o.index=o.index+1
    end
    if o.phase=='tiles' and o.index==volume then
        if d.family=='FarmPlot' and type(site_support)=='function' then
            -- The native warning accumulator scans x-major; placement masks are y-major.
            local eligible={}
            for x=0,r.width-1 do for y=0,r.height-1 do eligible[#eligible+1]=o.mask[y*r.width+x+1] end end
            local _,warning,verified=site_support({x=r.x,y=r.y,z=r.z},'FarmPlotWarning',r.width,r.height,eligible)
            o.warnings=verified and warning or ''
        end
        if aggregate or extent_shaped[d.family] then
            local lines,seen={},{}
            if not trigger_ok then lines[#lines+1]=trigger_reason;seen[trigger_reason]=true end
            if extent_shaped[d.family] then
                local connected,reason=area_connected(r,d)
                if not connected then
                    if reason=='' then return reply('',false,false) end
                    lines[#lines+1]=reason;seen[reason]=true
                end
            end
            -- Native3c1618 checks perimeter in the accepted final-tile branch,
            -- before collecting earlier tile errors in x-major order.
            if d.family=='Bridge' and o.mask[volume]==1 then
                local ok,reason,verified=bridge_perimeter(r)
                if not verified then return reply('',false,false) end
                if not ok then lines[#lines+1]=reason;seen[reason]=true end
            end
            for i=1,volume do
                local reason=o.refusals[i]
                -- Native outer terrain gate marks raw-invalid cells SKIP when any
                -- terrain qualifies; later water/occupancy errors remain fatal.
                if reason and not seen[reason] and (not extent_shaped[d.family] or not o.any_extent_terrain or o.extent_terrain[i]) then lines[#lines+1]=reason;seen[reason]=true end
            end
            if #lines>0 then
                -- Native 3c1c4e appends this when the native hookup list is
                -- nonempty and a tile error exists, even with a connection.
                if o.machine_hookups then lines[#lines+1]='Needs ground or near machine' end
                return reply(table.concat(lines,'\n'),false,false)
            end
        end
        if extent_shaped[d.family] then
            local any=false;for _,v in ipairs(o.mask) do if v==1 then any=true;break end end
            if not any then return reply(o.first_refusal or 'Native placement check rejected this site',false,false) end
        end
        if d.family=='AnimalTrap' then
            local ok,reason,verified=site_support({x=r.x,y=r.y,z=r.z},'SinglePerimeter')
            if not verified or not ok then return reply(verified and reason or '',false,false) end
        end
        if d.area_mode<=2 then
            if steps+volume>budget then return reply('',true,true) end
            local ok,reason=native_site(d,{x=r.x,y=r.y,z=r.z},r.width,r.height,dir,o.mask);steps=steps+volume
            if not ok then return reply(reason,false,false) end
        end
        local count=0;for _,v in ipairs(o.mask) do count=count+v end
        -- An empty terrain mask cannot open a material picker or claim valid
        -- placement. Queued construction replacements reuse existing jobs.
        if count==0 and d.area_mode>=3 and o.reused==0 then
            return reply(o.first_refusal or '',false,false)
        end
        if d.family=='RoadPaved' then
            -- Native road quantity uses accepted tiles, not the rectangle area.
            -- Recompute per operation, including commit after terrain changes.
            if type(r.native_material_recipe)~='function' then return reply('',false,false) end
            local native=r.native_material_recipe(d.type,d.subtype,custom(d),count)
            if type(native)~='table' or native.status~=0 or type(native.recipes)~='table' or #native.recipes~=1 or #o.raw~=1 then return reply('',false,false) end
            local row=native.recipes[1];local quantity=type(row)=='table' and row.count_required
            if math.type(quantity)~='integer' or quantity<1 or quantity>32767 then return reply('',false,false) end
            o.quantities={quantity}
        end
        o.required=0;o.per={}
        if count==0 and o.reused>0 then o.raw={} end
        for i,raw in ipairs(o.raw) do local f=filter_row(raw,i-1)
            if o.quantities then f.quantity=o.quantities[i] end
            f.quantity=f.quantity==-1 and ((d.area_mode>=3 and 1 or r.width*r.height)//4+1) or f.quantity
            if d.family=='Weapon' or (d.subtype_key=='WeaponTrap' and i==2) then f.quantity=1 end
            o.per[i]=f.quantity
            if d.area_mode>=3 then f.quantity=f.quantity*count end
            o.filters[i]=f;o.required=o.required+f.quantity
        end
        -- The completed recipe/site check is no longer in the pending tile
        -- phase. Consumers gate material selection on placement_valid.
        if r.action==1 then
            -- A newly checked placement opens a fresh native material picker.
            -- Paused edits (forbid, movement, reachability) must not wait for
            -- simulation-time cache expiry. Retain old snapshots for in-flight
            -- owners, but rebuild matching recipes before serving this opening.
            for i,raw in ipairs(o.raw) do
                local sig=signature(raw,{x=r.x,y=r.y,z=r.z},d.key,r.width,r.height,r.depth,r.material_anchor,r.direction,native_material_family(d) and r.native_material_candidates and i or nil)
                for _,e in ipairs(cache) do
                    if e.epoch==r.epoch and e.signature==sig then
                        e.dirty=true;e.reservation_version=(e.reservation_version or 0)+1
                    end
                end
            end
            o.phase='preview';return reply('',true,false)
        end
        local sums={};for _,s in ipairs(r.selections or {}) do
            local count=s.count or 1
            if math.type(count)~='integer' or count<1 then return reply('Selections do not cover the recipe',false,false) end
            sums[s.filter]=(sums[s.filter] or 0)+count
        end
        for _,f in ipairs(o.filters) do
            if d.family=='Weapon' or (d.subtype_key=='WeaponTrap' and f.index==1) then
                local count=sums[f.index] or 0
                if count<1 or count>10 then return reply('Weapon count must be between 1 and 10',false,false) end
                o.required=o.required-f.quantity+count;f.quantity=count;o.per[f.index+1]=count
            end
        end
        for _,f in ipairs(o.filters) do if (sums[f.index] or 0)~=f.quantity then return reply('Selections do not cover the recipe',false,false) end;sums[f.index]=nil end
        if next(sums) then return reply('Selections do not cover the recipe',false,false) end
        -- Validate every selection before reserving any ids or dirtying any entry.
        -- Pin each filter's snapshot for the entire pending Place operation.
        for _,s in ipairs(r.selections or {}) do
            local e=o.entries[s.filter+1]
            if not e then
                local sig=signature(o.raw[s.filter+1],{x=r.x,y=r.y,z=r.z},d.key,r.width,r.height,r.depth,r.material_anchor,r.direction,native_material_family(d) and r.native_material_candidates and s.filter+1 or nil)
                for _,v in ipairs(cache) do if v.epoch==r.epoch and v.signature==sig then e=v;break end end
                if e and e.rows then
                    e={rows=e.rows,by_key=e.by_key,groups=e.groups,revision=e.revision,owner=e}
                    o.entries[s.filter+1]=e
                end
            end
            if not e or not e.rows or e.revision~=s.expected_list_revision then
                local out=reply('List changed; refresh',false,false);out.filter=s.filter;return out
            end
            if (s.individual_id or -1)>=0 and (s.count~=1 or type(s.item_ids)~='table' or #s.item_ids~=1 or s.item_ids[1]~=s.individual_id) then return reply('',false,false) end
            if s.item_ids~=nil then
                local group=e.by_key[key(s)];local members={}
                if (d.family~='Windmill' and d.family~='Bridge' and not magma_buildings[d.key] and not single_furniture[d.key] and not fixed_material_recipes[d.key] and not terrain_materials[d.key]) or not group or not group.candidates or
                    type(s.item_ids)~='table' or #s.item_ids~=s.count then return reply('',false,false) end
                for _,item in ipairs(group.candidates) do members[item.id]=true end
                for _,id in ipairs(s.item_ids) do
                    if not members[id] then return reply('',false,false) end
                    members[id]=nil
                end
            end
        end
        o.phase='reserve'
    end
    local selections=r.selections or {}
    while o.phase=='reserve' and o.selection<=#selections and steps<budget do
        local s=selections[o.selection];local e=o.entries[s.filter+1]
        if not o.group then o.group=e.by_key[key(s)];o.taken=0;o.scan=1 end
        local ids=s.item_ids or (o.group and o.group.ids)
        if not ids or o.scan>#ids then return reply('Selected material no longer available; refresh materials',false,false) end
        local id=ids[o.scan];o.scan=o.scan+1;steps=steps+1
        local item=df.item.find(id)
        if not o.used[id] and item and item_key(item,o.group and o.group.candidates~=nil)==key(s) and eligible(item,e.groups,s.filter+1) then
            o.used[id]=true;o.reserved[s.filter+1]=o.reserved[s.filter+1] or {};table.insert(o.reserved[s.filter+1],id);o.taken=o.taken+1
        elseif s.item_ids then
            return reply('Selected material no longer available; refresh materials',false,false)
        end
        e.owner.dirty=true;e.owner.reservation_version=(e.owner.reservation_version or 0)+1
        if o.taken==(s.count or 1) then o.selection=o.selection+1;o.group=nil end
    end
    if o.phase=='reserve' and o.selection>#selections then
        -- Native terrain construction and Bridge assign the selected set by ascending item
        -- ID, independently of group clicks or explicit selection order.
        if terrain_materials[d.key] or d.family=='Bridge' or fixed_material_recipes[d.key] then for _,ids in pairs(o.reserved)do table.sort(ids)end end
        o.phase='create';o.offsets={}
    end
    if o.phase=='create' and d.family=='Construction' then
        -- Reservations may span safe points. Recheck every remaining tile before
        -- this batch creates jobs; a stale rectangle must not become partial paint.
        for i=o.create,volume-1 do
            local idx=(i//(r.width*r.height))*(r.width*r.height)+(i%r.height)*r.width+(i//r.height)%r.width
            local good,reason=tile_rule(r,d,position(r,idx))
            if not good and reason~='Existing construction job' then return reply(reason,false,false) end
        end
    end
    while o.phase=='create' and o.create<(d.area_mode>=3 and volume or 1) and attempts<128 do
        local idx=o.create
        if terrain_materials[d.key] then
            -- Visit z, then x, then y. Wire masks remain x-fast; only native
            -- job creation/material assignment uses this traversal.
            idx=(o.create//(r.width*r.height))*(r.width*r.height)+(o.create%r.height)*r.width+(o.create//r.height)%r.width
        end
        local p=position(r,idx);local piece=d.area_mode==4 and stair_piece(r,p) or o.pieces[idx+1];local ok=true
        if piece then o.pieces[idx+1]=piece end
        local perimeter_cost=d.family=='Bridge' and 2*(r.width+r.height) or 0
        local tile_cost=(d.area_mode>=3 and 1 or volume)+perimeter_cost
        local needed=0;for _,n in ipairs(o.per) do needed=needed+n end
        if steps+tile_cost+needed+1>budget then break end
        local trigger,reason,verified=pressure_trigger()
        if not verified or not trigger then return reply(verified and reason or '',false,false) end
        if d.area_mode>=3 then ok=tile_rule(r,d,p,piece);steps=steps+1
        else
            if uses_machine_support(d) then o.machine_supported=machine_connection(r,d) end
            for i=0,volume-1 do
                local terrain=extent_shaped[d.family] and {} or nil
                local good,_,fatal=tile_rule(r,d,position(r,i),nil,o.machine_supported,terrain);steps=steps+1
                if extent_shaped[d.family] then
                    if fatal or (not good and terrain.accepted) or (good and 1 or 0)~=o.mask[i+1] then ok=false end
                elseif not good then ok=false end
            end
            if d.family=='AnimalTrap' then
                local good,reason,verified=site_support(p,'SinglePerimeter')
                if not verified or not good then return reply(verified and reason or '',false,false) end
            end
            if extent_shaped[d.family] and not area_connected(r,d) then ok=false end
            if d.family=='Bridge' then
                steps=steps+perimeter_cost
                if not bridge_perimeter(r) then ok=false end
            end
        end
        local existing=o.mask[idx+1]==0 and queued_existing(d,p)
        if existing then
            local good,reason=tile_rule(r,d,p,piece)
            if not good and reason~='Existing construction job' then existing=nil end
        end
        if existing then
            -- Native changes the queued construction subtype in place, retaining
            -- its job and original input; it does not reserve a second recipe.
            existing.type=piece and df.construction_type[piece_names[piece]] or d.subtype;o.create=o.create+1;o.placed=o.placed+1;chunk=chunk+1
            if o.first<0 then o.first=existing.id end
        elseif not ok or (o.mask[idx+1]==0 and not extent_shaped[d.family]) then
            o.skipped=o.skipped+1;o.create=o.create+1
            if d.area_mode<=2 or d.key=='Construction:ReinforcedWall' then return reply('Native construction rejected',false,false) end
        else
            local items,advances={},{}
            for i,per in ipairs(o.per) do
                local offset=o.offsets[i] or 0;advances[i]=offset+per
                for j=1,per do
                    local id=o.reserved[i] and o.reserved[i][offset+j];local item=id and df.item.find(id);steps=steps+1
                    local e=o.entries[i]
                    if not item or not eligible(item,e.groups,i) then return reply('Selected material was taken during placement',false,false) end
                    items[#items+1]=item
                end
            end
            local fields=d.family=='SiegeEngine' and {facing=r.direction,resting_orientation=r.direction} or {}
            if d.family=='Rollers' then fields.speed=(r.roller_speed or 0)>0 and r.roller_speed or 50000 end
            if d.family=='Trap' and d.subtype_key=='TrackStop' then
                local ts=r.track_stop;local shifts={{0,0},{0,-1},{1,0},{0,1},{-1,0}};local offset=shifts[ts.dump_direction+1]
                fields.track_stop_info={friction=ts.friction,track_flags={use_dump=ts.dump_direction~=0},dump_x_shift=offset[1],dump_y_shift=offset[2]}
            end
            if d.family=='Trap' and d.subtype_key=='PressurePlate' then
                fields.plate_info={unit_min=pp.unit_min,unit_max=pp.unit_max,water_min=pp.water_min,water_max=pp.water_max,
                    magma_min=pp.magma_min,magma_max=pp.magma_max,track_min=pp.track_min,track_max=pp.track_max,
                    flags={units=pp.units,water=pp.water,magma=pp.magma,citizens=pp.citizens,resets=pp.resets,track=pp.track}}
            end
            if extent_shaped[d.family] then fields.room=farm_room(p,r.width,r.height,o.mask) end
            local b=B.constructBuilding{type=d.type,subtype=piece and df.construction_type[piece_names[piece]] or d.subtype,custom=custom(d),pos=p,
                width=d.area_mode>=3 and 1 or r.width,height=d.area_mode>=3 and 1 or r.height,direction=dir,full_rectangle=not extent_shaped[d.family],items=items,fields=fields}
            steps=steps+1;o.create=o.create+1;attempts=attempts+1
            if b then o.offsets=advances;o.placed=o.placed+1;chunk=chunk+1;if o.first<0 then o.first=b.id end
            else
                o.skipped=o.skipped+1
                if d.area_mode<=2 or d.key=='Construction:ReinforcedWall' then return reply('Native construction rejected',false,false) end
            end
        end
    end
    if o.phase=='create' and o.create==(d.area_mode>=3 and volume or 1) then
        if o.placed==0 then return reply('Native construction rejected',false,false) end
        if d.area_mode>=3 then return reply('Painted '..o.placed..' of '..volume,true,false) end
        return reply('Native construction job queued',true,false)
    end
    return reply('',true,true)
end
return function(r)
    if r.track_material_candidates_query then
        if not track_site_reader or not track_material_candidates or type(r.route_track)~='function' then return {status=2} end
        local x,y,z=dfhack.maps.getTileSize()
        local route=r.route_track(track_site_reader,r.start,r.destination,{x=x-1,y=y-1,z=z-1})
        if route.status~=0 then return {status=2,route_status=route.status,reason=route.reason} end
        local definition=by_key['Construction:Track']
        local result=track_material_candidates(route.path,r.maximum_candidates,r.native_material_candidates,definition.type,definition.subtype)
        result.path=route.path
        if r.material_order_query and result.status==0 then
            if not material_order then return {status=2} end
            local ordered=material_order(result,r.destination,r.material_distances)
            result.order_status=ordered.status
            result.groups=ordered.groups
            result.candidate_distances=ordered.candidate_distances
        end
        return result
    end
    -- Internal read-only diagnostic uses the production native callback without
    -- disturbing pending adapter work.
    if r.material_distance_query then
        if type(r.material_distances)~='function' then return {status=2,distances={}} end
        return r.material_distances(r.seeds,r.targets)
    end
    if r.connected_track_destination then r.track_site_reader=track_site_reader end
    if r.cancel_builders then cache={};operation=nil;return stats{ok=true,message='',steps=0} end
    if r.action==63 and r.definition=='Construction:Track' then return stats(track_materials(r)) end
    if r.pressure_creatures then return pressure_creatures() end
    if r.step then return build(r.step) end
    if operation and operation.seq~=r.seq then operation=nil end
    if catalog_error then return stats(fail(catalog_error)) end
    r.depth=r.depth or 1;r.direction=r.direction or 0;r.width=r.width or 1;r.height=r.height or 1
    if r.action==1 and r.definition=='Construction:Track' then
        if not track_site_reader or not r.route_track or not r.plan_track or not r.connected_track_destination then return stats{ok=false,message=''} end
        local x,y,z=dfhack.maps.getTileSize()
        local route=r.route_track(track_site_reader,{x=r.x,y=r.y,z=r.z},r.connected_track_destination,{x=x-1,y=y-1,z=z-1})
        -- Bound transport, not the native search; never truncate a found path.
        if #route.path>16384 then route={status=5,path={}} end
        local filters,required={},0
        if route.status==0 then
            local plan=r.plan_track(track_site_reader,route.path)
            if not plan.verified then route={status=4,path={}}
            else
                local raw=recipe(by_key[r.definition])
                for i,v in ipairs(raw or {}) do
                    local f=filter_row(v,i-1)
                    local per=f.quantity==-1 and 1 or f.quantity
                    f.quantity=per*plan.new_count;required=required+f.quantity
                    filters[#filters+1]=f
                end
                if #filters==0 or required>65535 then route={status=4,path={}};filters={};required=0
                elseif required==0 then filters={} end
            end
        end
        return stats{ok=true,building_key=r.definition,track_preview=route,filters=filters,
            required=required,placement_valid=route.status==0,message=''}
    end
    local result
    if r.action==2 and r.definition=='Construction:Track' then
        local prepared=prepare_track_placement(r)
        return stats(commit_track_placement(r,prepared))
    end
    -- Exact IDs must never fall through to the aggregate reservation queue.
    if r.action==2 and r.definition~='Windmill' and r.definition~='Bridge' and not magma_buildings[r.definition] and not single_furniture[r.definition] and not fixed_material_recipes[r.definition] and not terrain_materials[r.definition] then
        for _,selection in ipairs(r.selections or {}) do
            if selection.item_ids~=nil then return stats{ok=false,message=''} end
        end
    end
    if r.action==2 and r.items and #r.items>0 then return stats(fail('selected inputs are retired; use selections')) end
    if r.action==0 then
        local rev=revision(hash(0xcbf29ce484222325,tostring(r.epoch or 0)..'|1|'..#catalog))
        if (r.expected_list_revision or 0)~=0 and r.expected_list_revision~=rev then result=fail('List changed; refresh')
        else local page={};local cursor=r.cursor or 0
            if cursor==0 and (r.expected_list_revision or 0)==0 then
                for _,e in ipairs(cache) do if e.error then e.retry_requested=true end end
            end
            for i=cursor+1,math.min(cursor+128,#catalog) do page[#page+1]=catalog[i] end
            result={ok=true,catalog=page,total=#catalog,list_revision=rev,next_cursor=cursor+128<#catalog and cursor+128 or 0,message='Construction catalog ready'}
            if cursor==0 then result.pressure_creatures=pressure_creatures().pressure_creatures end
        end
    elseif r.action==6 then
        local p={x=r.x,y=r.y,z=r.z}
        if not visible(p) then result=fail('Construction tile is hidden or outside the map')
        else local c=dfhack.constructions.findAtTile(p)
            if not c or c.flags.top_of_wall then result=fail('No removable completed construction at this tile')
            else local ok=dfhack.constructions.designateRemove(p)
                result={ok=ok,terrain_construction=true,build_stage=1,max_stage=1,removing=ok,message=ok and 'Native construction removal designated' or 'Native construction removal rejected'}
            end
        end
    elseif r.action==3 or r.action==4 or r.action==5 then
        local b
        if r.action==5 then local p={x=r.x,y=r.y,z=r.z}
            if not visible(p) then return stats(fail('Inspection tile is hidden or outside the map')) end
            b=B.findAtTile(p)
            if not b then local c=dfhack.constructions.findAtTile(p)
                if c and not c.flags.top_of_wall then local f=dfhack.maps.getTileFlags(p)
                    return stats{ok=true,terrain_construction=true,build_stage=1,max_stage=1,removing=f.dig~=df.tile_dig_designation.No,message='Completed terrain construction'}
                end
            end
        else b=df.building.find(r.building_id) end
        if not b or not visible({x=b.centerx,y=b.centery,z=b.z}) then result=fail('Building is no longer available')
        elseif r.action~=4 then result=inspect(b)
        elseif b:getType()==df.building_type.Stockpile or b:getType()==df.building_type.Civzone then result=fail('Placed from the stockpile and zone menus')
        elseif r.definition~=building_key(b) then result=fail('Building changed; inspect again')
        elseif r.cancel_removal then
            -- Explicit cancellation cannot accidentally reissue removal. Native
            -- job cancellation unlinks its holder/worker references as well.
            local target
            for _,job in ipairs(b.jobs) do if job.job_type==df.job_type.DestroyBuilding then target=job;break end end
            if target then dfhack.job.removeJob(target) end
            result=inspect(b)
        elseif B.markedForRemoval(b) then result=fail('Already marked for removal')
        elseif B.deconstruct(b) then result={ok=true,building_id=r.building_id,building_key=r.definition,removing=true,message='Unbuilt construction cancelled'}
        else result=inspect(b);result.message='Native deconstruction queued' end
    else local d=by_key[r.definition]
        if not d or not d.supported then result=fail(d and d.reason or 'Building definition is not supported')
        elseif r.action==63 then result=materials(r,d)
        else result=placement(r,d) end
    end
    return stats(result)
end
