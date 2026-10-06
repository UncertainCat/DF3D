-- Native candidate enablement once semantic site groups have been collected.
-- DF53.16 aafd10/ab0d50; material_candidates.json reach_capture. This is distinct
-- from candidate population, distance ordering and site-group collection.
-- Groups must be full map_block.walkable values, not DFHack's uint16 helper.
return function(item_group, site_groups)
    local function valid(v)
        return math.type(v)=='integer' and v>=0 and v<=0x7fffffff
    end
    if not valid(item_group) or type(site_groups)~='table' then return nil end
    local count=0
    for key,value in pairs(site_groups) do
        if math.type(key)~='integer' or key<1 or not valid(value) then return nil end
        count=count+1
    end
    local found=false
    for i=1,count do
        local value=site_groups[i]
        if value==nil then return nil end
        if value>0 and item_group==value then found=true end
    end
    return found
end
