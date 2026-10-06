-- Pure generic-group selection kernel, separate from UI actions and placement.
-- Native evidence: material_candidates.json selection_kernel_capture.
-- Select nearest unselected item; deselect farthest selected item. Both break
-- distance ties toward the highest candidate ID. No native staged state is read.
-- A requested_id selects an expanded ordinary-item row exactly; a second click
-- is a no-op. This does not implement UI deselection or artifact descriptions.
return function(ids,distances,selected,action,requested_id)
    if type(ids)~='table' or type(distances)~='table' or type(selected)~='table' or
        (action~='select' and action~='deselect') then return nil end
    local function dense(t)
        local count=0
        for key in pairs(t) do
            if math.type(key)~='integer' or key<1 then return nil end
            count=count+1
        end
        for i=1,count do if t[i]==nil then return nil end end
        return count
    end
    local count,nselected=dense(ids),dense(selected)
    if not count or not nselected or count>65536 then return nil end
    local members,chosen={},{}
    local previous=-1
    for _,id in ipairs(ids) do
        local d=distances[id]
        if math.type(id)~='integer' or id<=previous or id>0x7fffffff or
            math.type(d)~='integer' or d<0 or d>0xffffffff then return nil end
        previous=id;members[id]=true
    end
    for _,id in ipairs(selected) do
        if not members[id] or chosen[id] then return nil end
        chosen[id]=true
    end
    if requested_id~=nil and (action~='select' or not members[requested_id]) then return nil end
    local changed,best
    for i=count,1,-1 do
        local id=ids[i]
        if (requested_id==nil or requested_id==id) and
            ((action=='select' and not chosen[id]) or (action=='deselect' and chosen[id])) then
            local d=distances[id]
            if not best or (action=='select' and d<best) or (action=='deselect' and d>best) then
                changed=id;best=d
            end
        end
    end
    if changed then chosen[changed]=action=='select' or nil end
    local result={selected={},changed_id=changed or -1,distance=-1}
    for _,id in ipairs(ids) do
        if chosen[id] then result.selected[#result.selected+1]=id
        elseif result.distance<0 or distances[id]<result.distance then result.distance=distances[id] end
    end
    result.used=#result.selected
    return result
end
