-- Initial, single-requirement material grouping, before distance ordering or
-- selection. DF53.16 8d4370 groups ordinary items by four-part identity and keeps
-- artifacts/improved items individual. No labels or native UI state are inputs.
-- Caller supplies an ascending, unique semantic candidate snapshot and a copied
-- individual flag (artifact or isImproved). Unknown facts return no partial list.
return function(candidates)
    if type(candidates)~='table' then return nil end
    local count=0
    for k in pairs(candidates) do
        if math.type(k)~='integer' or k<1 then return nil end
        count=count+1
    end
    if count>65536 then return nil end
    local function integer(v)
        return math.type(v)=='integer' and v>=-0x80000000 and v<=0x7fffffff
    end
    local groups,individuals,lookup={},{},{}
    local previous=-1
    for i=1,count do
        local row=candidates[i]
        if type(row)~='table' or not integer(row.id) or row.id<=previous or
            type(row.enabled)~='boolean' then return nil end
        previous=row.id
        if row.enabled then
            if type(row.individual)~='boolean' then return nil end
            if row.individual then
                individuals[#individuals+1]={ids={row.id},individual=true}
            else
                local values={row.item_type,row.item_subtype,row.mat_type,row.mat_index}
                for n=1,4 do if not integer(values[n]) then return nil end end
                local key=table.concat(values,':')
                local group=lookup[key]
                if not group then
                    group={item_type=row.item_type,item_subtype=row.item_subtype,
                        mat_type=row.mat_type,mat_index=row.mat_index,ids={},individual=false}
                    lookup[key]=group;groups[#groups+1]=group
                end
                group.ids[#group.ids+1]=row.id
            end
        end
    end
    -- Native initial assembly inserts all generic groups before individual rows;
    -- later stable distance insertion is a separate operation.
    for _,row in ipairs(individuals) do groups[#groups+1]=row end
    return groups
end
