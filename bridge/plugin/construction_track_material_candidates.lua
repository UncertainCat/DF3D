-- Safe-point semantic Track candidate snapshot. Native buildreq, widgets and
-- native navigation scratch are forbidden inputs. Inject the verified helpers
-- once with the construction owner's lifetime; callers provide their own route.
return function(enabled, collect_groups, partition, group_name)
    return function(path, maximum_candidates, native_query, native_type, native_subtype)
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
            if type(native_query)~='function' then return {status=2} end
            local native=native_query(native_type,native_subtype)
            if type(native)~='table' or native.status~=0 or type(native.candidates)~='table' or
                #native.candidates~=1 or type(native.candidates[1])~='table' then return {status=2} end
            if #native.candidates[1]>maximum_candidates then return {status=3} end
            local rows,seen={},{}
            for _,id in ipairs(native.candidates[1]) do
                if math.type(id)~='integer' or id<0 or seen[id] then return {status=2} end
                seen[id]=true
                local item=df.item.find(id)
                if not item then return {status=2} end
                -- Native collection owns suitability, flags and containment.
                -- Placement-group enablement remains a separate semantic step.
                local x,y,z=dfhack.items.getPosition(item)
                local p={x=x,y=y,z=z}
                if not x or not y or not z or not dfhack.maps.isValidTilePos(p) then return {status=2} end
                local group=raw_group(p)
                local available=enabled(group,groups)
                if available==nil then return {status=2} end
                rows[#rows+1]={id=id,item_type=item:getType(),item_subtype=item:getSubtype(),
                    mat_type=item:getMaterial(),mat_index=item:getMaterialIndex(),
                    position=p,walkable_group=group,enabled=available,
                    individual=item.flags.artifact or item:isImproved()}
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
