-- Opt-in native encounter recorder. Development captures only; no engine hooks.
-- JSONL describes observations, not inferred attacks, impacts, or destruction.
local json=require('json')
local M={}
local function encode(v) return json.encode(v,{pretty=false}) end
local function pos(p) return {x=p.x,y=p.y,z=p.z} end
local function fields(object,names)
    local result={}
    for name in names:gmatch('%S+') do result[name]=object[name] end
    return result
end
local function tick() return df.global.world.frame_counter end

function M.start(path,context)
    local f=assert(io.open(path,'wb'))
    local r={path=path,counts={},caps={},error=nil,closed=false}
    local buffer,bytes,sequence={},0,0
    local started=dfhack.getTickCount()
    local unit_set,unit_cache,item_cache,projectile_cache={},{},{},{}
    local spatter_cache={}
    local tracked_items,item_count={},0
    local projectile_entities={}
    local report_cursor=df.global.world.status.next_report_id
    local report_cache,report_units,report_count={},{},0
    local initial_report=report_cursor
    local first_item=df.global.item_next_id
    local iterations=0
    local total_sample_ms,max_sample_ms=0,0
    local bounds={x1=context.focus.x-context.width//2-2,x2=context.focus.x+context.width//2+2,
        y1=context.focus.y-context.height//2-2,y2=context.focus.y+context.height//2+2,
        z1=math.max(0,context.focus.z-1),z2=context.focus.z+3}
    local sx,sy,sz=dfhack.maps.getTileSize()
    bounds.x1=math.max(0,bounds.x1);bounds.x2=math.min(sx-1,bounds.x2)
    bounds.y1=math.max(0,bounds.y1);bounds.y2=math.min(sy-1,bounds.y2);bounds.z2=math.min(sz-1,bounds.z2)
    if dfhack.world.isArena() then bounds.z2=sz-1 end
    for _,id in ipairs(context.unit_ids) do unit_set[id]=true end
    -- Map block pointers remain valid for this recorder's loaded-map lifetime.
    -- Precompute coordinates once instead of crossing into DFHack per tile/scan.
    local blocks,cells={},{}
    local block_keys={}
    for z=bounds.z1,bounds.z2 do for y=bounds.y1,bounds.y2 do for x=bounds.x1,bounds.x2 do
        if #cells<16384 then
            local key=(z*sy+y//16*16)*sx+x//16*16
            local block=block_keys[key]
            if block==nil then
                block=dfhack.maps.getTileBlock{x=x,y=y,z=z} or false;block_keys[key]=block
                if block then blocks[#blocks+1]=block end
            end
            if block then cells[#cells+1]={x=x,y=y,z=z,lx=x%16,ly=y%16,block=block} end
        end
    end end end
    local function inside(p)
        return p.x>=bounds.x1 and p.x<=bounds.x2 and p.y>=bounds.y1 and p.y<=bounds.y2
            and p.z>=bounds.z1 and p.z<=bounds.z2
    end
    function r:flush()
        if self.closed or #buffer==0 then return end
        assert(f:write(table.concat(buffer)));assert(f:flush())
        buffer={};bytes=0
    end
    local function emit(kind,event)
        event=event or {};sequence=sequence+1
        event.kind=kind;event.tick=tick();event.sequence=sequence;event.wall_ms=dfhack.getTickCount()-started
        local line=encode(event)..'\n';buffer[#buffer+1]=line;bytes=bytes+#line
        r.counts[kind]=(r.counts[kind] or 0)+1
        if bytes>=1048576 then r:flush() end
    end
    local function cap(name,limit)
        r.caps[name]=(r.caps[name] or 0)+1
        if r.caps[name]==1 then emit('cap',{name=name,limit=limit}) end
    end
    local function changed(cache,key,kind,event)
        local serialized=encode(event)
        if cache[key]~=serialized then cache[key]=serialized;emit(kind,event) end
    end
    local function track_item(id)
        if id<0 or tracked_items[id] then return end
        if item_count>=8192 then cap('tracked_items',8192);return end
        tracked_items[id]=true;item_count=item_count+1
    end
    local function actions(u)
        local out={}
        for _,a in ipairs(u.actions) do
            if #out>=128 then cap('unit_actions',128);break end
            if a.type~=df.unit_action_type.None then
                local v={id=a.id,type=df.unit_action_type[a.type]}
                if a.type==df.unit_action_type.Attack then
                    v.data=fields(a.data.attack,'target_unit_id attack_item_id target_body_part_id attack_body_part_id attack_id attack_velocity hit_chance_modifier timer1 timer2')
                elseif a.type==df.unit_action_type.ShootRangedWeapon then
                    v.data=fields(a.data.shootrangedweapon,'target_unid shooter_itid ammo_itid')
                elseif a.type==df.unit_action_type.Move then
                    v.data=fields(a.data.move,'x y z timer timer_init')
                end
                out[#out+1]=v
            end
        end
        return out
    end
    local function wounds(u)
        local out={}
        for _,w in ipairs(u.body.wounds) do
            if #out>=128 then cap('unit_wounds',128);break end
            local v=fields(w,'id attacker_unit_id pain nausea dizziness paralysis numbness fever')
            v.flags=w.flags.whole;v.parts={}
            for _,p in ipairs(w.parts) do
                if #v.parts>=256 then cap('wound_parts',256);break end
                local part=fields(p,'body_part_id layer_idx bleeding pain swelling impaired cur_penetration_perc max_penetration_perc')
                part.flags1=p.flags1.whole;part.flags2=p.flags2.whole
                v.parts[#v.parts+1]=part
            end
            out[#out+1]=v
        end
        return out
    end
    local function units()
        for _,id in ipairs(context.unit_ids) do
            local u=df.unit.find(id)
            if not u then changed(unit_cache,id,'unit',{unit_id=id,missing=true})
            else
                local v={unit_id=id,pos=pos(u.pos),dead=dfhack.units.isDead(u),blood=u.body.blood_count,
                    blood_max=u.body.blood_max,flags1=u.flags1.whole,flags2=u.flags2.whole,
                    flags3=u.flags3.whole,flags4=u.flags4.whole,mood=u.mood,
                    counters=fields(u.counters,'stunned unconscious winded pain nausea dizziness webbed'),
                    counters2=fields(u.counters2,'paralysis exhaustion'),actions=actions(u),wounds=wounds(u),inventory={}}
                for _,entry in ipairs(u.inventory) do
                    if #v.inventory>=256 then cap('unit_inventory',256);break end
                    v.inventory[#v.inventory+1]={item_id=entry.item.id,mode=entry.mode,body_part_id=entry.body_part_id}
                    track_item(entry.item.id)
                end
                changed(unit_cache,id,'unit',v)
                -- Logs associate continuation lines (often without a position) with fighters.
                for _,log in pairs(u.reports.log) do
                    local n=0
                    for i=#log-1,0,-1 do
                        local rid=log[i];if rid<initial_report then break end
                        n=n+1;if n>512 then cap('unit_report_log',512);break end
                        report_units[rid]=report_units[rid] or {};report_units[rid][id]=true
                    end
                end
            end
        end
    end
    local function projectiles()
        local seen,n={},0
        local link=df.global.world.projectiles.all.next
        while link do
            n=n+1;if n>8192 then cap('projectile_scan',8192);break end
            local p=link.item
            if p then
                local item=df.proj_itemst:is_instance(p) and p.item or nil
                local unit=df.proj_unitst:is_instance(p) and p.unit or nil
                local firer=p.firer and p.firer.id or nil
                local body_owner=item and df.item_body_component:is_instance(item) and item.unit_id or nil
                if projectile_cache[p.id] or unit_set[firer] or (unit and unit_set[unit.id])
                    or unit_set[body_owner] or inside(p.cur_pos) or inside(p.origin_pos) then
                    local v={projectile_id=p.id,unit_id=unit and unit.id or firer,item_id=item and item.id or nil,
                        firer_id=firer,body_unit_id=body_owner,pos=pos(p.cur_pos),previous=pos(p.prev_pos),
                        origin=pos(p.origin_pos),target=pos(p.target_pos),flags=p.flags.whole,
                        distance=p.distance_flown,velocity=p.velocity,fall_counter=p.fall_counter,
                        fixed_position={x=p.pos_x,y=p.pos_y,z=p.pos_z},speed={x=p.speed_x,y=p.speed_y,z=p.speed_z}}
                    if item then track_item(item.id);v.item_type=df.item_type[item:getType()] end
                    seen[p.id]=true;changed(projectile_cache,p.id,'projectile',v)
                    projectile_entities[p.id]={projectile_id=p.id,unit_id=v.unit_id,item_id=v.item_id}
                end
            end
            link=link.next
        end
        -- Partial scans cannot establish that a projectile disappeared.
        if not link then for id in pairs(projectile_cache) do
            if not seen[id] then
                local v=projectile_entities[id];v.reason='left_native_projectile_list'
                emit('projectile_removed',v);projectile_cache[id]=nil;projectile_entities[id]=nil
            end
        end end
    end
    local function reports()
        local stop=df.global.world.status.next_report_id
        local count=0
        while report_cursor<stop and count<512 do
            local id=report_cursor;report_cursor=id+1;count=count+1
            local report=df.report.find(id)
            if report and (report_units[id] or unit_set[report.speaker_id] or inside(report.pos) or inside(report.pos2)) then
                if report_count>=4096 then cap('tracked_reports',4096)
                else report_cache[id]='';report_count=report_count+1 end
            end
        end
        if report_cursor<stop then cap('report_scan_per_tick',512) end
        -- Unit logs can attach a continuation after its world report was first seen.
        for id in pairs(report_units) do
            if not report_cache[id] and id>=initial_report and report_count<4096 then
                report_cache[id]='';report_count=report_count+1
            end
        end
        -- Recheck tracked reports for repeat counts and appended native text.
        for id in pairs(report_cache) do
            local report=(report_cache[id]=='' or iterations%5==0) and df.report.find(id) or nil
            if report then
                local ids={};for uid in pairs(report_units[id] or {}) do ids[#ids+1]=uid end;table.sort(ids)
                changed(report_cache,id,'report',{report_id=id,unit_id=ids[1],unit_ids=ids,
                    text=dfhack.df2utf(report.text),type=df.announcement_type[report.type],
                    repeat_count=report.repeat_count,flags=report.flags.whole,pos=pos(report.pos),pos2=pos(report.pos2),
                    year=report.year,time=report.time,speaker_id=report.speaker_id})
            end
        end
    end
    local function local_scan(scan_terrain)
        if (bounds.x2-bounds.x1+1)*(bounds.y2-bounds.y1+1)*(bounds.z2-bounds.z1+1)>16384 then cap('terrain_cells',16384) end
        for _,b in ipairs(blocks) do
            local n=0;for _,id in ipairs(b.items) do
                n=n+1;if n>8192 then cap('block_items',8192);break end
                local item=df.item.find(id);if item and inside(item.pos) then track_item(id) end
            end
            if scan_terrain then
                local entries={}
                for ei,event in ipairs(b.block_events) do
                    if ei>128 then cap('spatter_block_events',128);break end
                    if df.block_square_event_material_spatterst:is_instance(event) then
                        local info=dfhack.matinfo.decode(event.mat_type,event.mat_index)
                        local token=info and info:getToken() or 'UNKNOWN'
                        for x=0,15 do for y=0,15 do
                            local amount=event.amount[x][y]
                            if amount>0 and #entries<2048 then
                                entries[#entries+1]={pos={x=b.map_pos.x+x,y=b.map_pos.y+y,z=b.map_pos.z},material=token,state=event.mat_state,amount=amount}
                            elseif amount>0 then
                                cap('spatter_block_entries',2048)
                            end
                        end end
                    end
                end
                local key=string.format('%d:%d:%d',b.map_pos.x,b.map_pos.y,b.map_pos.z)
                changed(spatter_cache,key,'spatters',{block=pos(b.map_pos),entries=entries})
            end
        end
        if scan_terrain then for _,c in ipairs(cells) do
            local d=c.block.designation[c.lx][c.ly]
            local tiletype=c.block.tiletype[c.lx][c.ly]
            local building=c.block.occupancy[c.lx][c.ly].building
            -- Compare scalar values; JSON/table allocation happens only on change.
            local dig,hidden,liquid,liquid_type=d.dig,d.hidden,d.flow_size,d.liquid_type
            if c.tiletype~=tiletype or c.dig~=dig or c.hidden~=hidden or c.liquid~=liquid
                or c.liquid_type~=liquid_type or c.building~=building then
                c.tiletype,c.dig,c.hidden,c.liquid,c.liquid_type,c.building=tiletype,dig,hidden,liquid,liquid_type,building
                emit('terrain',{pos={x=c.x,y=c.y,z=c.z},tiletype=tiletype,dig=dig,hidden=hidden,
                    liquid=liquid,liquid_type=liquid_type,building=building})
            end
        end end
        for id in pairs(tracked_items) do
            local item=df.item.find(id)
            if not item then
                if item_cache[id]~='missing' then emit('item_removed',{item_id=id,reason='not_in_native_item_index'});item_cache[id]='missing' end
            else
                local v={item_id=id,pos=pos(item.pos),flags=item.flags.whole,flags2=item.flags2.whole,stack_size=item:getStackSize(),
                    item_type=df.item_type[item:getType()],subtype=item:getSubtype(),material=item:getMaterial(),material_index=item:getMaterialIndex()}
                if df.item_body_component:is_instance(item) then v.unit_id=item.unit_id;v.race=item.race end
                if not item_cache[id] then
                    v.description=dfhack.df2utf(dfhack.items.getDescription(item,0,true))
                    v.observation=id>=first_item and 'created_during_recording' or 'first_observed'
                    emit('item_identity',v)
                    v.description=nil;v.observation=nil
                end
                changed(item_cache,id,'item',v)
            end
        end
    end
    function r:finish(reason)
        if self.closed then return self.error==nil end
        emit('end',{reason=reason or 'capture_finished',error=self.error,counts=self.counts,caps=self.caps,
            elapsed_ms=dfhack.getTickCount()-started,samples=iterations,total_sample_ms=total_sample_ms,
            max_sample_ms=max_sample_ms,complete=self.error==nil})
        self:flush();assert(f:close());self.closed=true
        return self.error==nil
    end
    function r:sample()
        if self.closed then return self.error==nil end
        local ok,err=xpcall(function()
            local t=dfhack.getTickCount();units();local u=dfhack.getTickCount()
            projectiles();local p=dfhack.getTickCount();reports();local a=dfhack.getTickCount()
            if iterations%5==0 then local_scan(iterations%10==0) end
            local stop=dfhack.getTickCount()
            total_sample_ms=total_sample_ms+stop-t;max_sample_ms=math.max(max_sample_ms,stop-t)
            if iterations%30==0 then
                emit('timing',{unit_ms=u-t,projectile_ms=p-u,report_ms=a-p,local_scan_ms=stop-a,total_ms=stop-t,
                    tracked_items=item_count,tracked_reports=report_count});self:flush()
            end
            iterations=iterations+1
        end,debug.traceback)
        if not ok then
            self.error=tostring(err);_G.df3d_arena_diagnostics_error=self.error
            dfhack.printerr('ARENA_DIAGNOSTICS_ERROR '..self.error)
            -- If storage itself failed, preserve the original error for the setup JSON.
            pcall(function() emit('error',{text=self.error});self:finish('recorder_error') end)
            self.closed=true;pcall(function() f:close() end)
        end
        return ok,self.error
    end
    emit('start',{schema_version=1,scenario=context.scenario,unit_ids=context.unit_ids,bounds=bounds,
        cadence={units=1,projectiles=1,reports=1,items=5,terrain=10,spatters=10,flush=30},
        semantics='Native observations; projectile removal is not evidence of item destruction. Initial terrain is a baseline.'})
    r:sample()
    return r
end
return M
