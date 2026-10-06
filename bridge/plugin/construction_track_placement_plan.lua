-- Pure preflight for exact Track placement. The caller captures fresh semantic
-- facts at one safe point, then commits this owned result without yielding.
-- No native UI, reservation or mutation occurs here.
-- Route-order assignment evidence: material_candidates.json assignment_capture.
return function(retained,fresh,selections)
    local function integer(v,lo,hi)return math.type(v)=='integer' and v>=lo and v<=hi end
    local function dense(v,cap)
        if type(v)~='table' then return nil end
        local n=0;for key in pairs(v)do
            if not integer(key,1,cap) then return nil end;n=n+1
        end
        for i=1,n do if v[i]==nil then return nil end end
        return n
    end
    local function key(row)
        if type(row)~='table' then return nil end
        for _,field in ipairs{'item_type','item_subtype','mat_type','mat_index'}do
            if not integer(row[field],-1,0x7fffffff)then return nil end
        end
        return table.concat({row.item_type,row.item_subtype,row.mat_type,row.mat_index},':')
    end
    if type(retained)~='table' or type(fresh)~='table' or
        not integer(retained.revision,1,0x7fffffffffffffff) or
        not integer(retained.epoch,1,0x7fffffffffffffff) or retained.epoch~=fresh.epoch or type(retained.plan_key)~='string' or retained.plan_key=='' or
        retained.plan_key~=fresh.plan_key or not integer(fresh.required,0,16384) or
        retained.required~=fresh.required then return nil end
    local function members(snapshot)
        if not dense(snapshot.rows,65536)then return nil end
        local ids,groups={},{}
        for _,row in ipairs(snapshot.rows)do
            local group=key(row);local count=dense(row.candidates,16384)
            if not group or groups[group] or not count or count~=row.count then return nil end
            groups[group]=true
            for _,candidate in ipairs(row.candidates)do
                if type(candidate)~='table' or not integer(candidate.id,0,0x7fffffff) or ids[candidate.id]then return nil end
                ids[candidate.id]=group
            end
        end
        return ids
    end
    local old,current=members(retained),members(fresh)
    if not old or not current or not dense(selections,16384) or not dense(fresh.pieces,16384)then return nil end
    local chosen,ids,groups={},{},{}
    for _,selection in ipairs(selections)do
        if type(selection)~='table' then return nil end
        local group=key(selection);local count=dense(selection.item_ids,16384)
        if not group or groups[group] or selection.filter~=0 or selection.expected_list_revision~=retained.revision or
            not count or count<1 or count~=selection.count then return nil end
        groups[group]=true
        for _,id in ipairs(selection.item_ids)do
            if not integer(id,0,0x7fffffff) or chosen[id] or old[id]~=group or current[id]~=group then return nil end
            chosen[id]=true;ids[#ids+1]=id
        end
    end
    if #ids~=fresh.required then return nil end
    table.sort(ids) -- Native assignment uses global ID order, not click/group order.
    local result={pieces={},item_ids=ids,required=#ids};local next_item=1
    local positions,buildings={},{}
    for _,piece in ipairs(fresh.pieces)do
        if type(piece)~='table' or not integer(piece.action,0,2) or not integer(piece.connections,1,15) or
            type(piece.ramp)~='boolean' or piece.item_id~=nil then return nil end
        for _,axis in ipairs{'x','y','z'}do if not integer(piece[axis],0,0x7fffffff)then return nil end end
        local position=table.concat({piece.x,piece.y,piece.z},':')
        if positions[position]then return nil end;positions[position]=true
        local copy={};for k,v in pairs(piece)do
            -- Plan rows contain scalar expectations only, never borrowed objects.
            if type(v)=='table' or type(v)=='userdata' or type(v)=='function'then return nil end
            copy[k]=v
        end
        if piece.action==0 then
            if not ids[next_item] or piece.building_id~=-1 then return nil end
            copy.item_id=ids[next_item];next_item=next_item+1
        else
            if not integer(piece.building_id,0,0x7fffffff) or buildings[piece.building_id]then return nil end
            buildings[piece.building_id]=true
        end
        result.pieces[#result.pieces+1]=copy
    end
    if next_item~=#ids+1 then return nil end
    return result
end
