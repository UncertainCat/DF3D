-- Safe-point semantic Track candidate snapshot. Native buildreq, widgets and
-- native navigation scratch are forbidden inputs. Inject the verified helpers
-- once with the construction owner's lifetime; callers provide their own route.
return function(gate, recipe, enabled, collect_groups, partition, group_name)
    return function(path, maximum_candidates)
        if math.type(maximum_candidates)~='integer' or maximum_candidates<1 or maximum_candidates>65536 then
            return {status=1}
        end
        local function scan()
            local function raw_group(p)
                if not dfhack.maps.isValidTilePos(p) then return 0 end
                local block=dfhack.maps.getTileBlock(p)
                return block and block.walkable[p.x%16][p.y%16] or 0
            end
            local groups=collect_groups(path,raw_group)
            if not groups then return {status=2} end
            local rows,seen={},{}
            for _,item in ipairs(df.global.world.items.other.IN_PLAY) do
                local facts={type=df.item_type[item:getType()],is_build_mat=item:isBuildMat(),
                    material_type=item:getMaterial(),material_index=item:getMaterialIndex()}
                if facts.type=='BOULDER' and facts.material_type==0 and facts.material_index>=0 then
                    local policy=df.global.plotinfo.economic_stone
                    facts.economic_restricted=facts.material_index<#policy and policy[facts.material_index]~=0 or false
                end
                local suitable=recipe(facts)
                if suitable==nil then return {status=2} end
                if suitable then
                    facts.flags=item.flags.whole;facts.flags2=item.flags2.whole
                    if item.flags.in_inventory then
                        local container=dfhack.items.getContainer(item)
                        facts.container_kind=container and df.item_type[container:getType()] or 'UNIT'
                        if container then facts.container_flags=container.flags.whole;facts.container_flags2=container.flags2.whole end
                    end
                    local allowed=gate(facts)
                    if allowed==nil then return {status=2} end
                    if allowed and not item:isAssignedToStockpile() then
                        local x,y,z=dfhack.items.getPosition(item)
                        local p={x=x,y=y,z=z}
                        if x and y and z and dfhack.maps.isValidTilePos(p) and not seen[item.id] then
                            if #rows>=maximum_candidates then return {status=3} end
                            local group=raw_group(p)
                            local available=enabled(group,groups)
                            if available==nil then return {status=2} end
                            rows[#rows+1]={id=item.id,item_type=item:getType(),item_subtype=item:getSubtype(),
                                mat_type=facts.material_type,mat_index=facts.material_index,
                                position=p,walkable_group=group,enabled=available,
                                individual=item.flags.artifact or item:isImproved()}
                            seen[item.id]=true
                        end
                    end
                end
            end
            table.sort(rows,function(a,b)return a.id<b.id end)
            local initial_groups=partition(rows)
            if not initial_groups then return {status=2} end
            local by_id={}
            for _,row in ipairs(rows) do by_id[row.id]=row end
            for _,group in ipairs(initial_groups) do
                group.name=group_name(group)
                for _,id in ipairs(group.ids) do by_id[id].name=group_name(group,id) end
            end
            return {status=0,site_groups=groups,candidates=rows,initial_groups=initial_groups}
        end
        local ok,result=pcall(scan)
        return ok and result or {status=2}
    end
end
