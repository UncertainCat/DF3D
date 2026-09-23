-- Reusable development-only combat staging. No saves, no fabricated actions.
local source=debug.getinfo(1,'S').source:sub(2)
local directory=source:match('^(.*[/\\])')
local scenarios=assert(loadfile(directory..'arena_scenarios.lua'))()
local spawner=assert(loadfile(directory..'arena_native_spawn.lua'))()
local json=require('json')
local utils=require('utils')
local hill=assert(loadfile(directory..'arena_hill.lua'))()
local platform=assert(loadfile(directory..'arena_platform.lua'))()
local function geometry(config) return config.layout=='hill' and hill or config.layout=='platform' and platform or nil end
local function species(u) return df.global.world.raws.creatures.all[u.race].creature_id end
local function snapshot(u)
    local x,y,z=dfhack.units.getPosition(u)
    return {tick=df.global.world.frame_counter,pos={x=x,y=y,z=z},dead=dfhack.units.isDead(u),
        blood=u.body.blood_count,wounds=#u.body.wounds,inventory=#u.inventory,
        unconscious=u.counters.unconscious,stunned=u.counters.stunned,exhaustion=u.counters2.exhaustion}
end
local function retained(token,count)
    local out,seen={},{}
    for _,list in ipairs({df.global.world.units.active,df.global.world.units.all}) do
        for _,u in ipairs(list) do
            if not seen[u.id] and species(u)==token and u.status.current_soul and dfhack.units.isAdult(u)
                and not u.flags3.scuttle and not u.flags3.ghostly and not u.flags1.caged and not u.flags1.chained
                and (token~='DWARF' or (dfhack.units.isCitizen(u) and not dfhack.units.isDead(u)
                    and #u.body.wounds==0 and u.military.squad_id>=0
                    and u.status2.limbs_grasp_count>=2 and u.status2.limbs_stand_count>=2)) then
                out[#out+1]=u;seen[u.id]=true;if #out==count then return out end
            end
        end
    end
    return out
end
local function terrain(config)
    local sx,sy,sz=dfhack.maps.getTileSize()
    local native_arena=dfhack.world.isArena()
    local z=native_arena and math.max(0,math.min(df.global.window_z,sz-1)) or math.min(128,sz-2)
    local hx=config.width//2;local hy=config.height//2
    local function clear(cx,cy)
        for dz=0,(geometry(config) and geometry(config).height or 0) do
        for x=cx-hx,cx+hx do for y=cy-hy,cy+hy do
            local b=dfhack.maps.getTileBlock{x=x,y=y,z=z+dz};if not b then return false end
            local o=b.occupancy[x%16][y%16];local d=b.designation[x%16][y%16]
            local a=df.tiletype.attrs[b.tiletype[x%16][y%16]]
            if o.building~=0 or o.unit or o.unit_grounded or o.item or d.flow_size>0
                or (a.shape~=df.tiletype_shape.WALL and a.shape~=df.tiletype_shape.FLOOR)
                or a.material==df.tiletype_material.CONSTRUCTION or a.material==df.tiletype_material.TREE
                or a.material==df.tiletype_material.PLANT then return false end
        end end end
        return true
    end
    local focus
    if native_arena then focus={x=sx//2,y=sy//2,z=z} else
        local first_z=math.min(z,sz-(geometry(config) and geometry(config).height or 0)-2)
        local last_z=geometry(config) and math.max(1,first_z-96) or first_z
        for candidate_z=first_z,last_z,-4 do
            z=candidate_z
            for x=hx+8,sx-hx-9,8 do
                for y=hy+8,sy-hy-9,8 do if clear(x,y) then focus={x=x,y=y,z=z};break end end
                if focus then break end
            end
            if focus then break end
        end
    end
    assert(focus,'No clear stone patch for arena')
    -- Native Small arena includes structures above its floor. Replacing only
    -- that floor can detach those structures and cause a tick-one cave-in.
    -- This owned sandbox uses an open ceiling so combat evidence is not mixed
    -- with falling arena masonry. Never apply this to a loaded fortress.
    if native_arena then
        for above=z+1,sz-1 do for x=0,sx-1 do for y=0,sy-1 do
            local b=dfhack.maps.getTileBlock{x=x,y=y,z=above}
            if b then
                b.tiletype[x%16][y%16]=df.tiletype.OpenSpace
                local d=b.designation[x%16][y%16]
                d.hidden=false;d.dig=df.tile_dig_designation.No;d.flow_size=0
                d.outside=false;d.light=false;d.subterranean=true
            end
        end end end
    end
    for dz=0,(geometry(config) and geometry(config).height or 0) do
    for dx=-hx,hx do for dy=-hy,hy do
        local x,y=focus.x+dx,focus.y+dy;local b=dfhack.maps.getTileBlock{x=x,y=y,z=z+dz}
        local wall=math.abs(dx)==hx or math.abs(dy)==hy
        if config.layout=='gate' and dx==0 and math.abs(dy)>1 then wall=true end
        if config.layout=='cover' and dx==-3 and (dy==-5 or dy==0 or dy==5) then wall=true end
        b.tiletype[x%16][y%16]=wall and df.tiletype.StoneWall or
            (geometry(config) and assert(df.tiletype[geometry(config).tile(dx,dy,dz)]) or df.tiletype.StoneFloorSmooth)
        local d=b.designation[x%16][y%16];d.hidden=false;d.dig=df.tile_dig_designation.No
        d.flow_size=0;d.outside=false;d.light=false;d.subterranean=true;b.flags.designated=true
    end end end
    df.global.world.reindex_pathfinding=true
    return focus
end
local function open_headroom(config,focus)
    if geometry(config) then return geometry(config).height end
    local _,_,sz=dfhack.maps.getTileSize()
    -- Only include levels that cannot cover the fighting floor. Do not excavate
    -- a loaded fortress just to accommodate a recording camera.
    for dz=1,math.min(16,sz-focus.z-1) do
        for x=focus.x-config.width//2+1,focus.x+config.width//2-1 do
            for y=focus.y-config.height//2+1,focus.y+config.height//2-1 do
                local b=dfhack.maps.getTileBlock{x=x,y=y,z=focus.z+dz}
                if not b or b.tiletype[x%16][y%16]~=df.tiletype.OpenSpace then return dz-1 end
            end
        end
    end
    return math.min(16,sz-focus.z-1)
end
local function position(config,focus,left,index)
    if geometry(config) then
        local x,y,z=geometry(config).position(left,index)
        return {x=focus.x+x,y=focus.y+y,z=focus.z+z}
    end
    local count=(left and config.left or config.right).count
    local dx,dy
    if config.layout=='gate' then
        dx=left and -2 or (4+((index-1)//5)*2)
        dy=left and index-2 or ((index-1)%5-2)*3
    elseif config.layout=='cover' then
        dx=left and -10 or 10;dy=left and ((index-1)*3-7) or 0
    else
        dx=left and -4 or 5;dy=count==1 and 0 or ((index-1)%5-(math.min(count,5)-1)/2)*2
        if not left then dx=dx+((index-1)//5)*2 end
    end
    return {x=focus.x+dx,y=focus.y+math.floor(dy),z=focus.z}
end
local function subtype(kind,token)
    if token==nil then return -1 end
    for i=0,dfhack.items.getSubtypeCount(kind)-1 do
        if dfhack.items.getSubtypeDef(kind,i).id==token then return i end
    end
    error('Missing item definition '..token)
end
local function part(u,flag,n)
    local count=0
    for i,p in ipairs(u.body.body_plan.body_parts) do
        if p.flags[flag] then count=count+1;if count==(n or 1) then return i end end
    end
    error('Missing body part '..flag)
end
local function create(u,kind,token,material)
    local items=dfhack.items.createItem(u,kind,subtype(kind,token),material.type,material.index)
    assert(#items>0,'Cannot create arena equipment')
    for i=2,#items do dfhack.items.remove(items[i]) end
    local item=items[1];item:setQuality(0)
    if df.item_crafted:is_instance(item) then item.maker_race=u.race end
    return item
end
local armor={
    {'ARMOR','ITEM_ARMOR_BREASTPLATE','UPPERBODY',1}, {'HELM','ITEM_HELM_HELM','HEAD',1},
    {'PANTS','ITEM_PANTS_GREAVES','LOWERBODY',1}, {'GLOVES','ITEM_GLOVES_GAUNTLETS','GRASP',1},
    {'GLOVES','ITEM_GLOVES_GAUNTLETS','GRASP',2}, {'SHOES','ITEM_SHOES_BOOTS','STANCE',1},
    {'SHOES','ITEM_SHOES_BOOTS','STANCE',2},
}
local function equip(u,team,focus)
    local prior={};for _,e in ipairs(u.inventory) do prior[#prior+1]=e.item end
    for _,item in ipairs(prior) do assert(dfhack.items.moveToGround(item,{x=focus.x-17,y=focus.y,z=focus.z})) end
    local ammunition={}
    if team.weapon then
        local material=assert(dfhack.matinfo.find('INORGANIC:'..team.material))
        local weapon=create(u,df.item_type.WEAPON,'ITEM_WEAPON_'..team.weapon,material)
        assert(dfhack.items.moveToInventory(weapon,u,df.inv_item_role_type.Weapon,part(u,'GRASP',1)))
        dfhack.items.setOwner(weapon,u)
        if not team.ranged then
            local shield=create(u,df.item_type.SHIELD,'ITEM_SHIELD_SHIELD',material)
            assert(dfhack.items.moveToInventory(shield,u,df.inv_item_role_type.Weapon,part(u,'GRASP',2)))
            dfhack.items.setOwner(shield,u)
        end
        for i,e in ipairs(armor) do
            if team.armor=='full' or (team.armor=='medium' and i<=3) or (team.armor=='light' and i==2) then
                local item=create(u,df.item_type[e[1]],e[2],material)
                if e[1]=='GLOVES' then item:setGloveHandedness(e[4]) end
                assert(dfhack.items.moveToInventory(item,u,df.inv_item_role_type.Worn,part(u,e[3],e[4])))
                dfhack.items.setOwner(item,u)
            end
        end
        if team.ranged then
            local leather=assert(dfhack.matinfo.find('CREATURE:COW:LEATHER'))
            local quiver=create(u,df.item_type.QUIVER,nil,leather)
            assert(dfhack.items.moveToInventory(quiver,u,df.inv_item_role_type.Worn,part(u,'UPPERBODY')))
            dfhack.items.setOwner(quiver,u)
            local bolts=create(u,df.item_type.AMMO,'ITEM_AMMO_'..(team.ammo or 'BOLTS'),material);bolts:setStackSize(30)
            assert(dfhack.items.moveToContainer(bolts,quiver));ammunition[#ammunition+1]=bolts.id
            local squad=df.squad.find(u.military.squad_id)
            if squad then
            local spec=df.squad_ammo_spec:new();spec.item_type=df.item_type.AMMO
            spec.item_subtype=subtype(df.item_type.AMMO,'ITEM_AMMO_'..(team.ammo or 'BOLTS'))
            spec.mattype=material.type;spec.matindex=material.index;spec.amount=30
            spec.flags.use_combat=true;spec.flags.use_training=true;spec.assigned:insert('#',bolts.id)
            squad.ammo.ammunition:insert('#',spec)
            squad.ammo.ammo_items:insert('#',bolts.id);squad.ammo.ammo_units:insert('#',u.id)
            utils.insert_sorted(df.global.plotinfo.equipment.items_assigned.AMMO,bolts.id)
            end
        end
    end
    for _,uniform in ipairs(u.uniform.uniforms) do
        uniform:resize(0);for _,e in ipairs(u.inventory) do uniform:insert('#',e.item.id) end
        for _,id in ipairs(ammunition) do uniform:insert('#',id) end
    end
    u.uniform.uniform_drop:resize(0);u.uniform.uniform_pickup:resize(0);u.uniform.pickup_flags.update=false
    u.flags2.calculated_inventory=false
    return ammunition
end
local function skills(u,team)
    local names={'SHIELD','ARMOR','DODGING','MELEE_COMBAT','WRESTLING','DISCIPLINE','CLIMBING'}
    if team.skill then names[#names+1]=team.skill end
    if team.ranged then names[#names+1]='RANGED_COMBAT' end
    for _,name in ipairs(names) do
        local id=assert(df.job_skill[name]);local skill
        for _,s in ipairs(u.status.current_soul.skills) do if s.id==id then skill=s;break end end
        if not skill then skill=df.unit_skill:new();skill.id=id;utils.insert_sorted(u.status.current_soul.skills,skill,'id') end
        skill.rating=team.level;skill.experience=0;skill.rusty=0
    end
end
local function kill_order(u,targets)
    local squad=assert(df.squad.find(u.military.squad_id),'Arena dwarf needs military position')
    local slot=assert(squad.positions[u.military.squad_position])
    for _,old in ipairs(slot.orders) do old:delete() end;slot.orders:resize(0)
    local order=df.squad_order_kill_listst:new();order.issuer_hf=-1;order.recipient_hf=u.hist_figure_id
    order.year=df.global.cur_year;order.year_tick=df.global.cur_year_tick;order.origin_army_controller=-1
    order.title='Arena opponents'
    for _,target in ipairs(targets) do order.units:insert('#',target.id);order.histfigs:insert('#',target.hist_figure_id) end
    slot.orders:insert('#',order)
end
local function station_order(u,pos)
    local squad=assert(df.squad.find(u.military.squad_id),'Hill defender needs military position')
    local slot=assert(squad.positions[u.military.squad_position])
    for _,old in ipairs(slot.orders) do old:delete() end;slot.orders:resize(0)
    local order=df.squad_order_movest:new();order.issuer_hf=-1;order.recipient_hf=u.hist_figure_id
    order.year=df.global.cur_year;order.year_tick=df.global.cur_year_tick;order.origin_army_controller=-1
    order.pos:assign(pos);order.point_id=-1;slot.orders:insert('#',order)
end
return function(output,name,diagnostics_path,population_scale)
    assert(output and dfhack.isMapLoaded());df.global.pause_state=true;dfhack.run_script('setfps','60')
    name=name or 'skirmish';if name=='duel' then name='skirmish' end
    local config=copyall(assert(scenarios[name],'Unknown arena scenario'))
    if config.layout=='platform' then platform.scale(config,population_scale)
    else assert(not population_scale or tonumber(population_scale)==1,'Population scaling is only supported for platform') end
    -- Reject missing raw before any staging modifications.
    for _,team in ipairs({config.left,config.right}) do
        local loaded=false;for _,r in ipairs(df.global.world.raws.creatures.all) do if r.creature_id==team.race then loaded=true;break end end
        assert(loaded,'Creature raw not loaded: '..team.race)
        for _,role in pairs(team.roles or {}) do if role.race then
            local found=false;for _,r in ipairs(df.global.world.raws.creatures.all) do if r.creature_id==role.race then found=true;break end end
            assert(found,'Creature raw not loaded: '..role.race)
        end end
    end
    -- Fail before excavating if this loaded fort cannot supply the defenders.
    if config.left.race=='DWARF' and config.layout~='platform' then
        assert(#retained('DWARF',config.left.count)==config.left.count,'Not enough healthy military dwarves')
    end
    local focus=terrain(config);local units,sides={},{};local spawn_session
    local data={arena=true,native_arena=dfhack.world.isArena(),scenario=name,focus=focus,units={},actions={},shots={},projectiles={},climbs={},combatants={},
        title=config.title,equipment_note=config.equipment_note,team_labels=config.team_labels,population_scale=config.population_scale,
        capture_width=config.capture_width,capture_height=config.capture_height,camera_pitch=config.camera_pitch,camera_distance=config.camera_distance,capture_seconds=config.capture_seconds,simulation_fps=60,
        orbit_seconds=config.orbit_seconds,orbit_close_distance=config.orbit_close_distance,camera_focus_height=config.camera_focus_height,show_fps=config.show_fps,fps_path=output..'.fps.json',
        terrain_width=config.width,terrain_height=config.height,hill_height=geometry(config) and geometry(config).height or 0,
        open_headroom=open_headroom(config,focus)}
    local ok,err=xpcall(function()
        for side,team in ipairs({config.left,config.right}) do
            local roster=(config.layout=='platform' and side==2) and {} or retained(team.race,team.count)
            assert(team.race~='DWARF' or config.layout=='platform' or #roster==team.count,'Not enough healthy military dwarves')
            for i=1,team.count do
                local outfit=copyall(team)
                if team.roles then for k,v in pairs(team.roles[i] or {}) do outfit[k]=v end end
                if team.varied_weapons and not (team.roles and team.roles[i]) then
                    local weapon=team.varied_weapons[(i-1)%#team.varied_weapons+1]
                    outfit.weapon,outfit.skill=weapon[1],weapon[2]
                    if i%3~=0 then outfit.armor='none' end
                end
                local pos=position(config,focus,side==1,i);local u=roster[i];local spawned=false
                if not u then
                    spawn_session=spawn_session or spawner.begin()
                    u=spawner.spawn(spawn_session,outfit.race,pos,side);spawned=true
                end
                if u.job.current_job then dfhack.job.removeJob(u.job.current_job) end
                if not dfhack.maps.getTileBlock(u.pos) then u.pos:assign(pos) end
                assert(dfhack.units.teleport(u,pos))
                local restored=dfhack.units.isDead(u);if restored then reqscript('full-heal').heal(u,true,false) end
                u.flags1.inactive=false;u.flags1.incoming=false;u.flags1.left=false;u.flags1.move_state=true
                u.flags3.wait_until_reveal=false;u.flags1.hidden_in_ambush=false;u.flags1.hidden_ambusher=false
                if not utils.linear_index(df.global.world.units.active,u.id,'id') then df.global.world.units.active:insert('#',u) end
                u.mood=df.mood_type.None;u.enemy.combat_side_id=side
                u.flags1.marauder=side==2;u.flags1.active_invader=side==2;u.flags1.invades=side==2
                u.flags1.coward=false;u.flags4.invader_waits_for_parley=false
                u.enemy.army_controller_id=-1;u.enemy.army_controller=nil;u.relationship_ids.GroupLeader=-1
                local ammo=equip(u,outfit,focus);skills(u,outfit)
                if outfit.weapon then
                    u.profession=df.profession[outfit.ranged and 'CROSSBOWMAN' or outfit.skill=='AXE' and 'AXEMAN' or outfit.skill=='SPEAR' and 'SPEARMAN' or 'SWORDSMAN']
                    u.profession2=u.profession
                end
                units[#units+1]=u;sides[u.id]=side;data.units[#data.units+1]=u.id
                data.combatants[#data.combatants+1]={id=u.id,race=outfit.race,team=side==1 and 'left' or 'right',
                    restored=restored,spawned=spawned,ammunition=ammo,adult=dfhack.units.isAdult(u),
                    age=dfhack.units.getAge(u),body_size=u.body.size_info.size_cur,
                    weapon=outfit.weapon,ranged=outfit.ranged or false,initial=snapshot(u),latest=snapshot(u),samples={}}
            end
        end
    end,debug.traceback)
    if spawn_session then spawner.finish(spawn_session) end
    assert(ok,err)
    local targets={};for _,u in ipairs(units) do if sides[u.id]==2 then targets[#targets+1]=u end end
    for _,u in ipairs(units) do if sides[u.id]==1 and species(u)=='DWARF' and u.military.squad_id>=0 then
        if geometry(config) then station_order(u,u.pos) else kill_order(u,targets) end
    end end
    local last_fps_ms=0
    local function save_fps()
        local f=assert(io.open(data.fps_path,'w'))
        f:write(json.encode({fps=df.global.enabler.calculated_fps,gfps=df.global.enabler.calculated_gfps,
            tick=df.global.world.frame_counter,source='df.global.enabler.calculated_fps',paused=df.global.pause_state}))
        f:close()
        last_fps_ms=dfhack.getTickCount()
    end
    local function save() local f=assert(io.open(output,'w'));f:write(json.encode(data));f:close() end
    _G.df3d_arena_capture_state=data
    local diagnostics
    if diagnostics_path and diagnostics_path~='' then
        _G.df3d_arena_diagnostics_error=nil
        diagnostics=assert(loadfile(directory..'arena_diagnostics.lua'))().start(diagnostics_path,
            {unit_ids=data.units,focus=focus,width=config.width,height=config.height,scenario=name})
        data.diagnostics_path=diagnostics_path
        data.diagnostics_error=diagnostics.error
    end
    _G.df3d_arena_capture_flush=function()
        for i,u in ipairs(units) do data.combatants[i].latest=snapshot(u) end
        if diagnostics then diagnostics:sample();diagnostics:flush();data.diagnostics_error=diagnostics.error end
        save()
    end
    _G.df3d_arena_capture_finish=function()
        _G.df3d_arena_capture_flush()
        if diagnostics then
            diagnostics:finish('capture_finished');data.diagnostics_error=diagnostics.error;save()
            assert(not diagnostics.error,diagnostics.error)
        end
    end
    save();save_fps();local seen,projectiles={},{};local remaining=3600
    local function sample()
        if not dfhack.isMapLoaded() or _G.df3d_arena_capture_state~=data then
            if diagnostics then diagnostics:finish('map_unloaded_or_capture_replaced') end
            return
        end
        -- Refresh by elapsed time, not every 30 simulation ticks: a struggling
        -- simulation must not display its old pre-combat FPS for half a minute.
        if dfhack.getTickCount()-last_fps_ms>=500 then save_fps() end
        if diagnostics then diagnostics:sample();data.diagnostics_error=diagnostics.error end
        for _,u in ipairs(units) do
        for _,a in ipairs(u.actions) do
            local key=u.id..':'..a.id
            if a.type==df.unit_action_type.Climb and not seen[key..':'..u.pos.x..','..u.pos.y..','..u.pos.z] then
                seen[key..':'..u.pos.x..','..u.pos.y..','..u.pos.z]=true
                local v=a.data.climb
                data.climbs[#data.climbs+1]={id=u.id,action=a.id,tick=df.global.world.frame_counter,pos={x=u.pos.x,y=u.pos.y,z=u.pos.z},start={x=v.x1,y=v.y1,z=v.z1},goal={x=v.x2,y=v.y2,z=v.z2},hold={x=v.x3,y=v.y3,z=v.z3},timer=v.timer,timer_init=v.timer_init}
            elseif not seen[key] and a.type==df.unit_action_type.Attack then
                seen[key]=true;local v=a.data.attack
                data.actions[#data.actions+1]={attacker=u.id,action=a.id,target=v.target_unit_id,weapon=v.attack_item_id,
                    skill=df.job_skill[v.attack_skill],timer1=v.timer1,timer2=v.timer2,tick=df.global.world.frame_counter}
            elseif not seen[key] and a.type==df.unit_action_type.ShootRangedWeapon then
                seen[key]=true;local v=a.data.shootrangedweapon
                data.shots[#data.shots+1]={attacker=u.id,action=a.id,target=v.target_unid,weapon=v.shooter_itid,
                    ammo=v.ammo_itid,tick=df.global.world.frame_counter}
            end
        end end
        local link=df.global.world.projectiles.all.next
        while link do local p=link.item
            if p and df.proj_itemst:is_instance(p) and p.item and p.item:getType()==df.item_type.AMMO
                and p.firer and sides[p.firer.id] and not projectiles[p.id] then
                projectiles[p.id]=true;data.projectiles[#data.projectiles+1]={id=p.id,attacker=p.firer.id,
                    weapon=p.bow_id,ammo=df.proj_itemst:is_instance(p) and p.item.id or -1,tick=df.global.world.frame_counter}
            end
            link=link.next
        end
        if remaining%30==0 then
            for i,u in ipairs(units) do local s=snapshot(u);data.combatants[i].latest=s;data.combatants[i].samples[#data.combatants[i].samples+1]=s end
        end
        -- Sampling buffers events; keep disk/JSON cost out of each attack tick.
        if remaining%30==0 then save() end
        remaining=remaining-1
        if remaining>0 then dfhack.timeout(1,'ticks',sample)
        elseif diagnostics then diagnostics:finish('sample_limit');save() end
    end
    dfhack.timeout(1,'ticks',sample)
    print('ATTACK_DEMO_SETUP '..json.encode({units=data.units,focus=focus,arena=true,scenario=name}))
end
