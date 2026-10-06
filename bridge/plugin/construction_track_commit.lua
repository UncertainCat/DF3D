-- Execute an already validated, owned Track plan at one safe point. The caller
-- supplies a native operation for each Create/Update; no callback may yield.
-- Outcomes are internal receipt facts, never player-facing copy. Production
-- wiring must preserve these distinctions instead of flattening them to Rejected.
return function(plan,apply)
    if type(plan)~='table' or type(plan.pieces)~='table' or type(apply)~='function' then return nil end
    local result={outcome='complete',created=0,updated=0,unchanged=0,completed={},attempted=0,first_building=-1}
    -- Validate all dispatch shapes before the first callback can mutate the world.
    for _,piece in ipairs(plan.pieces)do
        if type(piece)~='table' or math.type(piece.action)~='integer' or piece.action<0 or piece.action>2 then return nil end
        if piece.action==0 and (math.type(piece.item_id)~='integer' or piece.item_id<0)then return nil end
        if piece.action~=0 and (math.type(piece.building_id)~='integer' or piece.building_id<0)then return nil end
    end
    for index,piece in ipairs(plan.pieces)do
        if piece.action==2 then
            result.unchanged=result.unchanged+1
        else
            result.attempted=result.attempted+1
            local ok,receipt=pcall(apply,piece)
            -- Exceptions and malformed receipts cannot prove that no write took
            -- place. Keep prior confirmed work and stop; never replay this item.
            if not ok or type(receipt)~='table' or
                (receipt.outcome~='applied' and receipt.outcome~='rejected') then
                result.outcome='unknown';result.failed_index=index;return result
            end
            if receipt.outcome=='rejected' then
                result.outcome=(result.created+result.updated)>0 and 'partial' or 'rejected'
                result.failed_index=index;return result
            end
            if math.type(receipt.building_id)~='integer' or receipt.building_id<0 or
                (piece.action==1 and receipt.building_id~=piece.building_id)then
                result.outcome='unknown';result.failed_index=index;return result
            end
            local operation={x=piece.x,y=piece.y,z=piece.z,action=piece.action,building_id=receipt.building_id}
            result.completed[#result.completed+1]=operation
            if piece.action==0 then
                result.created=result.created+1
                if result.first_building<0 then result.first_building=receipt.building_id end
            else result.updated=result.updated+1 end
        end
    end
    return result
end
