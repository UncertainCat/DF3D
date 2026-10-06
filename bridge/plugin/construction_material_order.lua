-- Initial ordering only. Caller owns route, semantic snapshot and search facts.
-- Native generic groups use minimum candidate navigation distance; equal-distance
-- rows retain initial partition order. This layer consumes owned distance results.
return function(snapshot,seed,reader,search,maximum,tile_limit,seeds)
    if type(snapshot)~='table' or snapshot.status~=0 or type(snapshot.candidates)~='table' or
        type(snapshot.initial_groups)~='table' or type(reader)~='function' or type(search)~='function' then return {status=2} end
    local targets,index={},{}
    for _,candidate in ipairs(snapshot.candidates) do
        if candidate.enabled then
            if #targets>=16384 then return {status=3} end
            targets[#targets+1]=candidate.position;index[candidate.id]=#targets
        end
    end
    if #targets==0 then return {status=0,groups={},candidate_distances={}} end
    local result=search(reader,seeds or {seed},targets,maximum,tile_limit)
    if type(result)~='table' or result.status~=0 then return {status=type(result)=='table' and result.status or 2,native_message=type(result)=='table' and result.native_message or nil,reason='search status '..tostring(type(result)=='table' and result.status or 'missing')..(type(result)=='table' and result.reason and ': '..result.reason or '')} end
    if type(result.distances)~='table' or #result.distances~=#targets then return {status=2} end
    local groups={}
    for ordinal,group in ipairs(snapshot.initial_groups) do
        local distance
        for _,id in ipairs(group.ids) do
            local row=index[id] and result.distances[index[id]]
            -- Native stale costs for unreachable candidates are not a semantic
            -- distance. Keep that ordering unverified; do not invent a fallback.
            if not row or row.reachable~=true or math.type(row.distance)~='integer' or row.distance<0 then return {status=2,reason='candidate '..id..' reachable='..tostring(row and row.reachable)..' distance='..tostring(row and row.distance)} end
            distance=distance and math.min(distance,row.distance) or row.distance
        end
        if not distance then return {status=2} end
        local copy={}
        for key,value in pairs(group) do copy[key]=value end
        -- Expanded display order is distinct from nearest-item selection ties:
        -- native child rows retain ascending candidate-ID order on equal costs.
        copy.expanded_ids={}
        for _,id in ipairs(group.ids) do copy.expanded_ids[#copy.expanded_ids+1]=id end
        table.sort(copy.expanded_ids,function(a,b)
            local da,db=result.distances[index[a]].distance,result.distances[index[b]].distance
            return da<db or (da==db and a<b)
        end)
        copy.distance=distance;copy.ordinal=ordinal;groups[#groups+1]=copy
    end
    table.sort(groups,function(a,b)return a.distance<b.distance or (a.distance==b.distance and a.ordinal<b.ordinal)end)
    for _,group in ipairs(groups) do group.ordinal=nil end
    local candidate_distances={}
    for _,candidate in ipairs(snapshot.candidates) do
        if candidate.enabled then
            local row=result.distances[index[candidate.id]]
            if row.reachable~=true or math.type(row.distance)~='integer' or row.distance<0 then return {status=2} end
            candidate_distances[#candidate_distances+1]={id=candidate.id,distance=row.distance}
        end
    end
    return {status=0,groups=groups,candidate_distances=candidate_distances}
end
