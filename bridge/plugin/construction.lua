-- Semantic construction adapter; closure lifetime owns all cached state.
local B=dfhack.buildings
local function fail(message) return {ok=false,message=message} end
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
local function recipe(d) return B.getFiltersByType({},d.type,d.subtype,custom(d)) end
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
local sized={FarmPlot=true,Bridge=true,RoadDirt=true,RoadPaved=true,AxleHorizontal=true,Rollers=true}
local machines={ScrewPump=true,WaterWheel=true,GearAssembly=true,AxleHorizontal=true,AxleVertical=true,Rollers=true}
local function footprint(d,w,h,dir)
    local _,x,y,cx,cy=B.getCorrectSize(w,h,d.type,d.subtype,custom(d),dir)
    return {direction=dir<0 and 4 or dir,width=x,height=y,center_x=cx or -1,center_y=cy or -1}
end
local function definitions()
    local out,seen={},{}
    local function add(family,subtype,t,st,raw,synthetic)
        local key=family..(subtype~='' and ':'..subtype or '')..(raw and ':'..raw.code or '')
        if seen[key] then error('Duplicate construction catalog key: '..key) end;seen[key]=true
        local d={key=key,name=key:gsub(':',' / '),type=t,subtype=st,family=family,subtype_key=subtype,
            custom_code=raw and raw.code or '',native_name=raw and dfhack.df2utf(raw.name) or '',
            area_mode=family=='Construction' and (synthetic=='Stairs' and 4 or 3) or (sized[family] and 2 or 1),
            orientations=1,max_depth=synthetic=='Stairs' and 256 or 1,filters={},footprints={}}
        if family=='ScrewPump' or family=='Rollers' or family=='SiegeEngine' then d.orientations=15
        elseif family=='WaterWheel' or family=='AxleHorizontal' then d.orientations=3
        elseif family=='Bridge' then d.orientations=31 end
        local success,inputs=pcall(recipe,d);local reason=''
        if not success or not inputs then reason='Building has no recipe'
        elseif #inputs>8 then reason='Recipe has more than 8 inputs'
        else for i,v in ipairs(inputs) do d.filters[i]=filter_row(v,i-1) end end
        if family=='Stockpile' or family=='Civzone' then reason='Placed from the stockpile and zone menus'
        elseif subtype:find('Magma') or (raw and raw.needs_magma) then reason='Magma placement rule not captured'
        elseif family=='Windmill' then reason='Windmill placement rule not captured'
        elseif subtype=='PressurePlate' then reason='Pressure plate options not captured'
        elseif subtype=='TrackStop' then reason='Track stop options not captured'
        elseif synthetic=='Track' then reason='Track piece selection not captured' end
        if raw and not permitted(raw) then reason='Not permitted for this civilization' end
        for dir=0,4 do if d.orientations & (1<<dir)~=0 then
            local ok,f=pcall(footprint,d,1,1,dir==4 and -1 or dir)
            if ok and f.width and f.height and f.width>=1 and f.height>=1 and f.width<=31 and f.height<=31 then d.footprints[#d.footprints+1]=f
            else reason='Building has no recipe' end
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
                if type(n)=='string' and n~='Custom' and not (name=='Construction' and n:match('^Track')) then add(name,n,t,st) end
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
local floors={FLOOR=true,BOULDER=true,PEBBLES=true,TWIG=true,SAPLING=true,SHRUB=true}
local spaces={EMPTY=true,FLOOR=true,BOULDER=true,PEBBLES=true,RAMP_TOP=true,BROOK_TOP=true,TWIG=true,SAPLING=true,SHRUB=true}
local stairs={STAIR_UP=true,STAIR_DOWN=true,STAIR_UPDOWN=true}
local function attrs(p) local tt=dfhack.maps.getTileType(p);return tt and df.tiletype.attrs[tt] end
local function adjacent(p,predicate)
    for _,v in ipairs{{-1,0},{1,0},{0,-1},{0,1}} do local q={x=p.x+v[1],y=p.y+v[2],z=p.z}
        if visible(q) and predicate(attrs(q)) then return true end
    end;return false
end
local function basic_floor(a) return a and df.tiletype_shape.attrs[a.shape].basic_shape==df.tiletype_shape_basic.Floor end
local function stair_piece(r,p)
    if r.depth==1 then return 1 end
    local a=attrs(p);local shape=a and df.tiletype_shape[a.shape]
    if p.z==r.z then return (shape=='STAIR_DOWN' or shape=='STAIR_UPDOWN') and 3 or 1 end
    if p.z==r.z+r.depth-1 then return (shape=='STAIR_UP' or shape=='STAIR_UPDOWN') and 3 or 2 end;return 3
end
local piece_names={'UpStair','DownStair','UpDownStair'}
local function tile_rule(r,d,p,piece)
    if not visible(p) then return false,'Site is hidden, unloaded or outside the map' end
    local f,occ=dfhack.maps.getTileFlags(p)
    if occ.building~=0 then return false,'Site is occupied by a building' end
    if f.flow_size>1 or (f.flow_size>0 and (f.liquid_type==true or f.liquid_type==df.tile_liquid.Magma)) then return false,'Site has magma or deep water' end
    local a=attrs(p);local s=df.tiletype_shape[a.shape];local family=d.family
    if family=='Construction' then
        local target=piece and piece_names[piece] or d.subtype_key
        local shapes={Wall='WALL',Floor='FLOOR',Ramp='RAMP',UpStair='STAIR_UP',DownStair='STAIR_DOWN',UpDownStair='STAIR_UPDOWN',Fortification='FORTIFICATION'}
        if a.material==df.tiletype_material.CONSTRUCTION and shapes[target]==s then return false,'Construction already present' end
        local one=r.width*r.height*r.depth==1
        if not (spaces[s] or s=='RAMP' or (piece and stairs[s])) or
            (not one and a.material==df.tiletype_material.CONSTRUCTION and df.construction.find(p)) then return false,'Site needs open space or a ramp' end
        if not B.checkFreeTiles(p,{x=1,y=1}) then return false,'Native placement check rejected this site' end
    elseif family=='FarmPlot' or family=='RoadDirt' then
        local mat=df.tiletype_material[a.material]
        local dirt=({SOIL=true,GRASS_LIGHT=true,GRASS_DARK=true,GRASS_DRY=true,GRASS_DEAD=true,PLANT=true})[mat]
        local good=dirt and floors[s] and s~='BOULDER' and s~='PEBBLES'
        if not good and family=='FarmPlot' and basic_floor(a) then
            for _,e in ipairs(dfhack.maps.getTileBlock(p).block_events) do
                if e:getType()==df.block_square_event_type.material_spatter and e.mat_type==df.builtin_mats.MUD and e.mat_state==df.matter_state.Solid then good=true;break end
            end
        end
        if not good then return false,'Site needs soil' end
    elseif family=='Well' then
        if not (s=='EMPTY' or s=='RAMP_TOP') or not adjacent(p,basic_floor) then return false,'Well needs open space with an adjacent floor' end
    elseif family=='Support' then
        if not spaces[s] then return false,'Site needs open space' end
    elseif machines[family] or family=='Bridge' then
        local anchor=false
        if family=='Bridge' and not r.retracting then local e=df.building_bridgest.T_direction
            anchor=(r.direction==e.Up and p.y==r.y) or (r.direction==e.Down and p.y==r.y+r.height-1) or
                (r.direction==e.Left and p.x==r.x) or (r.direction==e.Right and p.x==r.x+r.width-1)
        end
        if not (spaces[s] or (not anchor and (s=='RAMP' or stairs[s]))) then return false,'Site needs open space, a ramp or stairs' end
    elseif family=='Hatch' or family=='GrateFloor' or family=='BarsFloor' then
        if not (s=='FLOOR' or s=='EMPTY' or s=='RAMP_TOP' or stairs[s]) then return false,'Site needs a floor, open space, a ramp top or stairs' end
    else
        if not floors[s] then return false,'Site needs a floor' end
        if family=='Bed' and f.outside then return false,'Bed requires an indoor site' end
        if family=='Door' and not adjacent(p,function(v) return v.shape==df.tiletype_shape.WALL or v.shape==df.tiletype_shape.FORTIFICATION end) then return false,'Door requires an adjacent wall' end
    end;return true
end
local function native_site(d,p,w,h,dir)
    local b=B.allocInstance(p,d.type,d.subtype,custom(d))
    if not b then return false,'Native building allocation failed' end
    return dfhack.with_finalize(function()
        if b.room.extents then df.delete(b.room.extents);b.room.extents=nil end;df.delete(b)
    end,function()
        if not B.setSize(b,w,h,dir) then return false,'Native placement check rejected this site' end;return true
    end)
end
local bad_flags={'dump','forbid','garbage_collect','hostile','on_fire','rotten','trader','in_building','construction','in_job','owned','removed','encased','spider_web'}
local function screen(item,j,groups)
    if not item then return false end
    for _,name in ipairs(bad_flags) do if item.flags[name] then return false end end
    if item:isAssignedToStockpile() then return false end
    local container=dfhack.items.getContainer(item)
    if container and container:getType()==df.item_type.TOOL and container:hasToolUse(df.tool_uses.HEAVY_OBJECT_HAULING) then return false end
    local p=dfhack.items.getPosition(item)
    if not visible(p) or not groups[dfhack.maps.getWalkableGroup(p)] then return false end
    local ground=container or item
    -- Containers are traversed with a fixed cap; malformed containment is ineligible.
    for _=1,16 do if not container then break end;ground=container;container=dfhack.items.getContainer(container) end
    if container or not ground.flags.on_ground then return false end
    for _,name in ipairs(bad_flags) do if ground.flags[name] then return false end end
    if j.item_type>=0 and j.item_type~=item:getType() then return false end
    if j.item_subtype>=0 and j.item_subtype~=item:getSubtype() then return false end
    if j.flags2.building_material and not item:isBuildMat() then return false end
    if j.has_tool_use>=0 and not item:hasToolUse(j.has_tool_use) then return false end
    if j.metal_ore>=0 and not item:isMetalOre(j.metal_ore) then return false end
    local contained=dfhack.items.getGeneralRef(item,df.general_ref_type.CONTAINS_ITEM)
    if j.flags1.empty and (contained or dfhack.items.getGeneralRef(item,df.general_ref_type.CONTAINS_UNIT)) then return false end
    if contained and j.flags2.lye_milk_free then
        local mi=dfhack.matinfo.decode(contained:getItem());if not mi or mi:getToken()~='WATER' then return false end
    end
    if item:getType()==df.item_type.BAR then
        local mi=dfhack.matinfo.decode(item);local token=mi and mi:getToken() or ''
        if token:match('^COAL:') or token=='ASH' or (mi and mi.material.flags.SOAP) then return false end
    end
    return dfhack.job.isSuitableItem(j,item:getType(),item:getSubtype()) and dfhack.job.isSuitableMaterial(j,item:getMaterial(),item:getMaterialIndex(),item:getType())
end
local function key(v) return table.concat({v.item_type,v.item_subtype,v.mat_type,v.mat_index},':') end
local function item_key(item) return key{item_type=item:getType(),item_subtype=item:getSubtype(),mat_type=item:getMaterial(),mat_index=item:getMaterialIndex()} end
local function clipped_utf8(text,cap)
    if #text<=cap then return text end
    while cap>0 and (text:byte(cap+1) & 0xc0)==0x80 do cap=cap-1 end
    return text:sub(1,cap)
end
local function item_row(item)
    local mi=dfhack.matinfo.decode(item);if not mi then return end
    local name=mi:toString();if not name or name=='' then return end
    return {item_type=item:getType(),item_subtype=item:getSubtype(),mat_type=item:getMaterial(),mat_index=item:getMaterialIndex(),name=clipped_utf8(dfhack.df2utf(name),128),caption='',count=0,ids={}}
end
local function signature(raw)
    return filter_call(raw,function(j)
        local out={}
        for _,k in ipairs{'item_type','item_subtype','mat_type','mat_index','vector_id','has_tool_use','metal_ore','min_dimension','reaction_class','has_material_reaction_product','flags4','flags5'} do out[#out+1]=tostring(j[k]) end
        for _,k in ipairs{'flags1','flags2','flags3'} do out[#out+1]=tostring(j[k].whole) end
        return table.concat(out,'|')
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
    e.phase=1;e.done=0;e.total=0;e.build_ids=0;e.error=nil
    local vids=vectors(e.raw)
    for _,vid in ipairs(vids) do e.total=e.total+#df.global.world.items.other[df.job_item_vector_id.attrs[vid].other] end
    e.total=e.total+#df.global.world.units.active;e.started=tick()
    local reservation_version=e.reservation_version or 0
    e.job=coroutine.create(function()
        local function step() e.done=e.done+1;e.total=math.max(e.total,e.done);coroutine.yield() end
        local groups={}
        for i=0,#df.global.world.units.active-1 do
            local u=i<#df.global.world.units.active and df.global.world.units.active[i] or nil
            if u and not dfhack.units.isDead(u) and dfhack.units.isActive(u) and (dfhack.units.isCitizen(u) or dfhack.units.isResident(u)) then local g=dfhack.maps.getWalkableGroup(dfhack.units.getPosition(u));if g~=0 then groups[g]=true end end
            u=nil;step()
        end
        local rows,grouped,seen={},{},{}
        for _,vid in ipairs(vids) do
            local n=#df.global.world.items.other[df.job_item_vector_id.attrs[vid].other]
            for i=0,n-1 do
                local all=df.global.world.items.other[df.job_item_vector_id.attrs[vid].other]
                local item=i<#all and all[i] or nil;all=nil
                if item and not seen[item.id] and filter_call(e.raw,function(j) return screen(item,j,groups) end) then
                    local row=item_row(item)
                    if row then
                        if e.build_ids>=65536 then e.error='list exceeds cap';item=nil;step();return end
                        local k=key(row);local g=grouped[k]
                        if not g then g=row;grouped[k]=g;rows[#rows+1]=g end
                        g.ids[#g.ids+1]=item.id;g.count=g.count+1;seen[item.id]=true;e.build_ids=e.build_ids+1
                    end
                end
                item=nil;step()
            end
        end
        e.phase=2
        local width=1
        local function less(a,b) return a.name<b.name or (a.name==b.name and key(a)<key(b)) end
        while width<#rows do
            local merged={}
            for start=1,#rows,2*width do
                local a,b=start,math.min(start+width,#rows+1);local ae,be=b,math.min(start+2*width,#rows+1)
                while a<ae or b<be do
                    if b>=be or (a<ae and less(rows[a],rows[b])) then merged[#merged+1]=rows[a];a=a+1 else merged[#merged+1]=rows[b];b=b+1 end
                    step()
                end
            end
            rows=merged;width=width*2
        end
        local h=hash(0xcbf29ce484222325,tostring(e.epoch)..'|'..e.signature,step)
        -- A numeric identity tuple is at most 42 bytes; each tuple/id hash is one bounded step.
        for _,row in ipairs(rows) do h=hash(h,'|'..key(row));step()
            for _,id in ipairs(row.ids) do h=hash(h,':'..tostring(id));step() end
        end
        e.rows=rows;e.by_key=grouped;e.groups=groups;e.revision=revision(h);e.ids=e.build_ids;e.build_ids=0;e.dirty=(e.reservation_version or 0)~=reservation_version;e.scan_tick=e.started;e.phase=0;e.total=e.done
    end)
end
local function entry(epoch,raw)
    local sig=signature(raw);clock=clock+1
    for _,e in ipairs(cache) do if e.epoch==epoch and e.signature==sig then e.used=clock;return e end end
    if #cache==4 then local oldest=1;for i=2,4 do if cache[i].used<cache[oldest].used then oldest=i end end;table.remove(cache,oldest) end
    local e={epoch=epoch,signature=sig,raw=raw,used=clock};cache[#cache+1]=e;queue(e);return e
end
local function build(budget)
    local steps=0
    while steps<budget do
        local e;for _,v in ipairs(cache) do if v.job then e=v;break end end;if not e then break end
        local ok,err=coroutine.resume(e.job)
        if not ok then e.error=tostring(err);e.job=nil;e.build_ids=0
        elseif coroutine.status(e.job)=='dead' then e.job=nil;e.build_ids=0
        else steps=steps+1 end
    end
    return stats{ok=true,message='',steps=steps}
end
local function materials(r,d)
    local inputs=recipe(d);local raw=inputs and inputs[(r.filter or -1)+1]
    if not raw then return fail('Building has no recipe') end
    local e=entry(r.epoch,raw)
    if e.rows and not e.job and (e.dirty or tick()-e.scan_tick>1200 or tick()<e.scan_tick) then queue(e) end
    if e.error then return fail(e.error) end
    local result={ok=true,building_key=d.key,filter=r.filter,filters=d.filters,estimated=true,materials={},total=e.ids or 0,
        build_phase=e.phase,build_done=e.done,build_total=e.total,list_revision=e.revision or 0,message='DF3D estimate: '..tostring(e.ids or 0)..' accessible'}
    if e.job then return result end
    if (r.expected_list_revision or 0)~=0 and r.expected_list_revision~=e.revision then return fail('List changed; refresh') end
    local cursor=r.cursor or 0
    for i=cursor+1,math.min(cursor+128,#e.rows) do result.materials[#result.materials+1]=e.rows[i] end
    result.next_cursor=cursor+128<#e.rows and cursor+128 or 0;result.total=#e.rows;return result
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
    local dir=r.retracting and -1 or r.direction
    if d.orientations & (1<<(r.retracting and 4 or dir))==0 then return fail('Orientation not available for this building') end
    if r.depth>1 and d.area_mode~=4 then return fail('Depth applies to stairs only') end
    local mw,mh=d.max_width,d.max_height
    if d.family=='AxleHorizontal' then mw=dir==1 and 1 or 31;mh=dir==1 and 31 or 1
    elseif d.family=='Rollers' then mw=dir%2==0 and 1 or 31;mh=dir%2==0 and 31 or 1 end
    if r.width>mw or r.height>mh or r.depth>d.max_depth then return fail("Size exceeds this building's limits") end
    local fp=footprint(d,r.width,r.height,dir)
    if d.area_mode==1 and (r.width~=fp.width or r.height~=fp.height) then return fail('This building has a fixed size') end
    if not operation or operation.seq~=r.seq then
        operation={seq=r.seq,index=0,phase='tiles',mask={},pieces={},filters={},placed=0,skipped=0,first=-1,raw=recipe(d),reserved={},used={},selection=1,scan=1,create=0,entries={}}
    end
    local o=operation;local steps,chunk,attempts=0,0,0;local budget=math.min(r.step_budget or 1536,1536);local volume=r.width*r.height*r.depth
    local function reply(message,ok,pending)
        local out={ok=ok,pending=pending,message=message,steps=steps,placed=o.placed,skipped=o.skipped,first_building=o.first,chunk_placed=chunk,
            building_key=d.key,filters=o.filters,valid_mask=o.mask,pieces=o.pieces,footprint=fp,placement_valid=o.phase~='tiles',required=o.required or 0,inputs={}}
        if not pending then operation=nil end;return out
    end
    while o.phase=='tiles' and o.index<volume and steps<budget do
        local p=position(r,o.index);local piece=d.area_mode==4 and stair_piece(r,p) or nil
        local ok,reason=tile_rule(r,d,p,piece);steps=steps+1
        if not ok and d.area_mode<=2 then return reply(reason,false,false) end
        o.mask[#o.mask+1]=ok and 1 or 0;if piece then o.pieces[#o.pieces+1]=piece end;o.index=o.index+1
    end
    if o.phase=='tiles' and o.index==volume then
        if d.area_mode<=2 then
            if steps+volume>budget then return reply('',true,true) end
            local ok,reason=native_site(d,{x=r.x,y=r.y,z=r.z},r.width,r.height,dir);steps=steps+volume
            if not ok then return reply(reason,false,false) end
        end
        local count=0;for _,v in ipairs(o.mask) do count=count+v end
        o.required=0;o.per={}
        for i,raw in ipairs(o.raw) do local f=filter_row(raw,i-1)
            f.quantity=f.quantity==-1 and (r.width*r.height//4+1) or f.quantity
            if d.family=='Weapon' or (d.subtype_key=='WeaponTrap' and i==2) then f.quantity=1 end
            o.per[i]=f.quantity
            if d.area_mode>=3 then f.quantity=f.quantity*count end
            o.filters[i]=f;o.required=o.required+f.quantity
        end
        if r.action==1 then return reply('',true,false) end
        local sums={};for _,s in ipairs(r.selections or {}) do sums[s.filter]=(sums[s.filter] or 0)+s.count end
        for _,f in ipairs(o.filters) do if (sums[f.index] or 0)~=f.quantity then return reply('Selections do not cover the recipe',false,false) end;sums[f.index]=nil end
        if next(sums) then return reply('Selections do not cover the recipe',false,false) end
        -- Validate every selection before reserving any ids or dirtying any entry.
        -- Pin each filter's snapshot for the entire pending Place operation.
        for _,s in ipairs(r.selections or {}) do
            local e=o.entries[s.filter+1]
            if not e then
                local sig=signature(o.raw[s.filter+1])
                for _,v in ipairs(cache) do if v.epoch==r.epoch and v.signature==sig then e=v;break end end
                if e and e.rows then
                    e={rows=e.rows,by_key=e.by_key,groups=e.groups,revision=e.revision,owner=e}
                    o.entries[s.filter+1]=e
                end
            end
            if not e or not e.rows or e.revision~=s.expected_list_revision then
                local out=reply('List changed; refresh',false,false);out.filter=s.filter;return out
            end
        end
        o.phase='reserve'
    end
    local selections=r.selections or {}
    while o.phase=='reserve' and o.selection<=#selections and steps<budget do
        local s=selections[o.selection];local e=o.entries[s.filter+1]
        if not o.group then o.group=e.by_key[key(s)];o.taken=0;o.scan=1 end
        if not o.group or o.scan>#o.group.ids then return reply('Selected material no longer available; refresh materials',false,false) end
        local id=o.group.ids[o.scan];o.scan=o.scan+1;steps=steps+1
        local item=df.item.find(id)
        if not o.used[id] and item and item_key(item)==key(s) and filter_call(o.raw[s.filter+1],function(j) return screen(item,j,e.groups) end) then
            o.used[id]=true;o.reserved[s.filter+1]=o.reserved[s.filter+1] or {};table.insert(o.reserved[s.filter+1],id);o.taken=o.taken+1
        end
        e.owner.dirty=true;e.owner.reservation_version=(e.owner.reservation_version or 0)+1
        if o.taken==s.count then o.selection=o.selection+1;o.group=nil end
    end
    if o.phase=='reserve' and o.selection>#selections then o.phase='create';o.offsets={} end
    while o.phase=='create' and o.create<(d.area_mode>=3 and volume or 1) and attempts<128 do
        local idx=o.create;local p=position(r,idx);local piece=o.pieces[idx+1];local ok=true
        local tile_cost=d.area_mode>=3 and 1 or volume
        local needed=0;for _,n in ipairs(o.per) do needed=needed+n end
        if steps+tile_cost+needed+1>budget then break end
        if d.area_mode>=3 then ok=tile_rule(r,d,p,piece);steps=steps+1
        else for i=0,volume-1 do local good=tile_rule(r,d,position(r,i));steps=steps+1;if not good then ok=false end end end
        if not ok or o.mask[idx+1]==0 then o.skipped=o.skipped+1;o.create=o.create+1
        else
            local items,advances={},{}
            for i,per in ipairs(o.per) do
                local offset=o.offsets[i] or 0;advances[i]=offset+per
                for j=1,per do
                    local id=o.reserved[i] and o.reserved[i][offset+j];local item=id and df.item.find(id);steps=steps+1
                    local e=o.entries[i]
                    if not item or not filter_call(o.raw[i],function(f) return screen(item,f,e.groups) end) then return reply('Selected material was taken during placement',false,false) end
                    items[#items+1]=item
                end
            end
            local fields=d.family=='SiegeEngine' and {facing=r.direction,resting_orientation=r.direction} or {}
            local b=B.constructBuilding{type=d.type,subtype=piece and df.construction_type[piece_names[piece]] or d.subtype,custom=custom(d),pos=p,
                width=d.area_mode>=3 and 1 or r.width,height=d.area_mode>=3 and 1 or r.height,direction=dir,full_rectangle=true,items=items,fields=fields}
            steps=steps+1;o.create=o.create+1;attempts=attempts+1
            if b then o.offsets=advances;o.placed=o.placed+1;chunk=chunk+1;if o.first<0 then o.first=b.id end
            else o.skipped=o.skipped+1 end
        end
    end
    if o.phase=='create' and o.create==(d.area_mode>=3 and volume or 1) then return reply('Native construction job queued',true,false) end
    return reply('',true,true)
end
return function(r)
    if r.cancel_builders then cache={};operation=nil;return stats{ok=true,message='',steps=0} end
    if r.step then return build(r.step) end
    if operation and operation.seq~=r.seq then operation=nil end
    if catalog_error then return stats(fail(catalog_error)) end
    r.depth=r.depth or 1;r.direction=r.direction or 0;r.width=r.width or 1;r.height=r.height or 1
    local result
    if r.action==2 and r.items and #r.items>0 then return stats(fail('selected inputs are retired; use selections')) end
    if r.action==0 then
        local rev=revision(hash(0xcbf29ce484222325,tostring(r.epoch or 0)..'|1|'..#catalog))
        if (r.expected_list_revision or 0)~=0 and r.expected_list_revision~=rev then result=fail('List changed; refresh')
        else local page={};local cursor=r.cursor or 0
            for i=cursor+1,math.min(cursor+128,#catalog) do page[#page+1]=catalog[i] end
            result={ok=true,catalog=page,total=#catalog,list_revision=rev,next_cursor=cursor+128<#catalog and cursor+128 or 0,message='Construction catalog ready'}
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
