-- Fixed bridge implementation, embedded into the plugin; accepts semantic data only.
-- Native recipes stay in pinned DFHack. No persistent instance is created by preview.
local B = dfhack.buildings
local furniture = {Chair=true,Bed=true,Table=true,Coffin=true,Door=true,Box=true,
    Weaponrack=true,Armorstand=true,Cabinet=true,Statue=true,WindowGlass=true}
local workshops = {Carpenters=true,Masons=true,Craftsdwarfs=true,Jewelers=true,
    Bowyers=true,Mechanics=true,Butchers=true,Leatherworks=true,Tanners=true,
    Clothiers=true,Fishery=true,Still=true,Loom=true,Kitchen=true,Farmers=true}
local pieces = {Wall=true,Floor=true,Ramp=true,UpStair=true,DownStair=true,UpDownStair=true}
local function single_input(filters)
    if not filters or #filters~=1 then return false end
    local native=df.job_item:new();native:assign(filters[1])
    local single=native.quantity==1;native:delete();return single
end
local function definitions()
    local out = {}
    local function add(key,t,st,supported)
        local success,filters = pcall(B.getFiltersByType,{},t,st,-1)
        if not success then filters=nil end
        local _,w,h = B.getCorrectSize(1,1,t,st,-1,0)
        local ok = supported and single_input(filters)
        out[#out+1]={key=key,name=key:gsub(':',' / '),type=t,subtype=st,width=w,height=h,
            supported=not not ok,reason=ok and '' or 'Not yet supported: special placement or input workflow'}
    end
    -- DF enum names live behind a metatable; pairs() exposes metadata only.
    -- Match pinned gui/buildings.lua's explicit numeric enumeration.
    for t=0,df.building_type._last_item do
        local name=df.building_type[t]
        if type(name)=='string' and type(t)=='number' and t>=0 then
            if name=='Workshop' then
                for s=0,df.workshop_type._last_item do
                    local n=df.workshop_type[s]
                    if type(n)=='string' and type(s)=='number' and s>=0 then add('Workshop:'..n,t,s,workshops[n]) end
                end
            elseif name=='Construction' then
                for s=0,df.construction_type._last_item do
                    local n=df.construction_type[s]
                    if type(n)=='string' and type(s)=='number' and s>=0 then add('Construction:'..n,t,s,pieces[n]) end
                end
            else add(name,t,-1,furniture[name]) end
        end
    end
    table.sort(out,function(a,b)return a.key<b.key end)
    return out
end
local function visible(pos)
    if not pos or not dfhack.maps.isValidTilePos(pos) then return false end
    local d = dfhack.maps.getTileFlags(pos)
    return d and not d.hidden
end
local function site(r,d)
    if r.direction~=0 or r.width~=d.width or r.height~=d.height then return false,'This definition has fixed dimensions and orientation' end
    for x=r.x,r.x+r.width-1 do for y=r.y,r.y+r.height-1 do
        local p={x=x,y=y,z=r.z}
        if not visible(p) then return false,'Site is hidden, unloaded or outside the map' end
        local tile=dfhack.maps.getTileType(p)
        local shape=df.tiletype.attrs[tile].shape
        if shape~=df.tiletype_shape.FLOOR and shape~=df.tiletype_shape.BOULDER and
            shape~=df.tiletype_shape.PEBBLES and shape~=df.tiletype_shape.TWIG and
            shape~=df.tiletype_shape.SAPLING and shape~=df.tiletype_shape.SHRUB then
            return false,'This construction workflow requires a supported floor at every footprint tile'
        end
        local flags,occ=dfhack.maps.getTileFlags(p)
        if occ.building~=0 then return false,'Site is occupied by a building' end
        if flags.flow_size>0 then return false,'Dry floor required' end
        if d.type==df.building_type.Bed and flags.outside then return false,'Bed requires an indoor site' end
    end end
    if d.type==df.building_type.Door then
        local wall=false
        for _,v in ipairs{{-1,0},{1,0},{0,-1},{0,1}} do
            local p={x=r.x+v[1],y=r.y+v[2],z=r.z}
            local t=visible(p) and dfhack.maps.getTileType(p)
            if t and (df.tiletype.attrs[t].shape==df.tiletype_shape.WALL or
                df.tiletype.attrs[t].shape==df.tiletype_shape.FORTIFICATION) then wall=true end
        end
        if not wall then return false,'Door requires an adjacent wall' end
    end
    if not B.hasSupport({x=r.x,y=r.y,z=r.z},{x=r.width,y=r.height}) then return false,'Site has no terrain support' end
    local b=B.allocInstance({x=r.x,y=r.y,z=r.z},d.type,d.subtype,-1)
    if not b then return false,'Native building allocation failed' end
    return dfhack.with_finalize(function()
        if b.room.extents then df.delete(b.room.extents);b.room.extents=nil end
        df.delete(b)
    end,function()
        if not B.setSize(b,r.width,r.height,r.direction) then return false,'Native placement check rejected this site' end
        return true,''
    end)
end
local function eligible(item,j)
    local f=item.flags
    if f.forbid or f.in_job or f.in_building or f.removed or f.garbage_collect or f.dump or
        f.hostile or f.on_fire or f.artifact or f.trader or f.owned or not f.on_ground then return false end
    if not visible(item.pos) then return false end
    if j.item_type>=0 and j.item_type~=item:getType() then return false end
    if j.item_subtype>=0 and j.item_subtype~=item:getSubtype() then return false end
    if j.flags2.building_material and not item:isBuildMat() then return false end
    if j.flags1.empty and (dfhack.items.getGeneralRef(item,df.general_ref_type.CONTAINS_ITEM) or
        dfhack.items.getGeneralRef(item,df.general_ref_type.CONTAINS_UNIT)) then return false end
    return dfhack.job.isSuitableItem(j,item:getType(),item:getSubtype()) and
        dfhack.job.isSuitableMaterial(j,item:getMaterial(),item:getMaterialIndex(),item:getType())
end
local function inspect(b)
    return {ok=true,building_id=b.id,build_stage=b:getBuildStage(),max_stage=b:getMaxBuildStage(),
        removing=B.markedForRemoval(b),jobs=#b.jobs,message=dfhack.df2utf(B.getName(b))}
end
local catalog=definitions()
local catalog_error
for _,key in ipairs{'Chair','Workshop:Carpenters','Construction:Wall'} do
    local found=false
    for _,definition in ipairs(catalog) do
        if definition.key==key and definition.supported then found=true;break end
    end
    if not found then catalog_error='Native construction catalog is incomplete: '..key;break end
end
return function(r)
    if catalog_error then return {ok=false,message=catalog_error} end
    if r.action==0 then return {ok=true,catalog=catalog,message='Construction catalog ready'} end
    if r.action==6 then
        local p={x=r.x,y=r.y,z=r.z}
        if not visible(p) then return {ok=false,message='Construction tile is hidden or outside the map'} end
        local c=dfhack.constructions.findAtTile(p)
        if not c or c.flags.top_of_wall then return {ok=false,message='No removable completed construction at this tile'} end
        local ok=dfhack.constructions.designateRemove(p)
        return {ok=ok,terrain_construction=true,build_stage=1,max_stage=1,removing=ok,
            message=ok and 'Native construction removal designated' or 'Native construction removal rejected'}
    end
    if r.action==3 or r.action==4 or r.action==5 then
        local b
        if r.action==5 then
            local p={x=r.x,y=r.y,z=r.z}
            if not visible(p) then return {ok=false,message='Inspection tile is hidden or outside the map'} end
            b=B.findAtTile(p)
            if not b then
                local c=dfhack.constructions.findAtTile(p)
                if c and not c.flags.top_of_wall then
                    local f=dfhack.maps.getTileFlags(p)
                    return {ok=true,terrain_construction=true,build_stage=1,max_stage=1,
                        removing=f.dig~=df.tile_dig_designation.No,message='Completed terrain construction'}
                end
            end
        else b=df.building.find(r.building_id) end
        if not b or not visible({x=b.centerx,y=b.centery,z=b.z}) then return {ok=false,message='Building is no longer available'} end
        if r.action~=4 then return inspect(b) end
        local allowed=false
        for _,d in ipairs(catalog) do if d.supported and d.type==b:getType() and d.subtype==b:getSubtype() then allowed=true end end
        if not allowed then return {ok=false,message='Removal for this building type is not yet supported'} end
        local gone=B.deconstruct(b)
        if gone then return {ok=true,building_id=r.building_id,removing=true,message='Unbuilt construction cancelled'} end
        local result=inspect(b); result.message='Native deconstruction queued';return result
    end
    local d
    for _,entry in ipairs(catalog) do if entry.key==r.definition then d=entry;break end end
    if not d or not d.supported then return {ok=false,message='Building definition is not supported'} end
    local valid,reason=site(r,d)
    if not valid then return {ok=false,message=reason} end
    local recipe=B.getFiltersByType({},d.type,d.subtype,-1)
    if not single_input(recipe) then return {ok=false,message='Native recipe changed; refresh catalog'} end
    local filter=df.job_item:new(); filter:assign(recipe[1])
    return dfhack.with_finalize(function()filter:delete()end,function()
        if r.action==2 then
            if #r.items~=1 then return {ok=false,message='Select exactly one eligible construction input'} end
            local item=df.item.find(r.items[1])
            if not item or not eligible(item,filter) then return {ok=false,message='Selected material moved, became reserved, or is no longer eligible'} end
            local building,err=B.constructBuilding{type=d.type,subtype=d.subtype,custom=-1,
                pos={x=r.x,y=r.y,z=r.z},width=r.width,height=r.height,direction=0,
                full_rectangle=true,items={item}}
            if not building then return {ok=false,message=err or 'Native construction rejected'} end
            local result=inspect(building);result.message='Native construction job queued';return result
        end
        local inputs={}
        local all=df.global.world.items.all
        local cursor=r.cursor
        local stop=math.min(#all,cursor+512)
        while cursor<stop and #inputs<r.limit do
            local item=all[cursor];cursor=cursor+1
            if eligible(item,filter) then inputs[#inputs+1]={id=item.id,description=dfhack.df2utf(dfhack.items.getDescription(item,0,true)),quantity=item:getStackSize()} end
        end
        return {ok=true,placement_valid=true,required=1,inputs=inputs,
            next_cursor=cursor<#all and cursor or 0,message='Select one construction input'}
    end)
end
