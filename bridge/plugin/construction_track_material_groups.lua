-- Collect Track material-access groups from an independently validated route.
-- DF53.16 aafd10: four cardinal neighbors at each end (aafe02..ab01b9),
-- followed by the second endpoint itself (ab08ec..ab095e). Route interiors do
-- not contribute groups. Reader returns full raw map_block.walkable values;
-- known outside-map samples return zero, unavailable facts return nil.
-- Flat mixed-group capture: material_candidates.json site_group_capture.
-- Elevated capture covers a two-level ramp in both directions. Same-point
-- native clicks yield an empty route and stay in Placement, not a one-tile picker.
return function(path, read_group)
    local function integer(v,lo,hi)
        return math.type(v)=='integer' and v>=lo and v<=hi
    end
    if type(path)~='table' or type(read_group)~='function' then return nil end
    local count=0
    for index,p in pairs(path) do
        if not integer(index,1,0x7fffffff) or type(p)~='table' then return nil end
        for _,axis in ipairs{'x','y','z'} do
            if not integer(p[axis],-0x80000000,0x7fffffff) then return nil end
        end
        count=count+1
    end
    if count<2 then return nil end
    for i=1,count do if path[i]==nil then return nil end end
    local groups,seen={},{}
    local function sample(p,dx,dy,unique)
        local x,y=p.x+dx,p.y+dy
        if not integer(x,-0x80000000,0x7fffffff) or not integer(y,-0x80000000,0x7fffffff) then return false end
        local ok,g=pcall(read_group,{x=x,y=y,z=p.z})
        if not ok or not integer(g,0,0x7fffffff) then return false end
        if g>0 and (not unique or not seen[g]) then groups[#groups+1]=g;seen[g]=true end
        return true
    end
    if count>=2 then
        for _,p in ipairs{path[1],path[count]} do
            for _,delta in ipairs{{0,-1},{0,1},{-1,0},{1,0}} do
                if not sample(p,delta[1],delta[2],true) then return nil end
            end
        end
    end
    -- Native appends the destination's nonzero group even if already present.
    if not sample(path[count],0,0,false) then return nil end
    return groups
end
