-- Semantic red ALERT dismissal. Protocol wiring is separate; never call native UI.
-- Native effects: fixtures/reports/alert_entries.json, red_alert_native_dismissal.
-- Caller must validate fortress epoch/command ownership and execute at a safe point.
-- Retain only copied IDs; a receipt authorizes precisely that ordered source vector.
local revision=0
local retained
local MAX_REFS=65536
local function fail(message)return {ok=false,message=message}end
local function capture()
 local source=df.global.world.status.alert_button_announcement_id
 if #source>MAX_REFS then return fail('Alert group exceeds 65536 references')end
 local ids={}
 for _,id in ipairs(source)do
  if math.type(id)~='integer' or id<0 then return fail('Invalid native report reference')end
  ids[#ids+1]=id
 end
 if revision==math.maxinteger then return fail('Alert dismissal receipt exhausted')end
 revision=revision+1;retained={receipt=revision,ids=ids}
 return {ok=true,receipt=revision,count=#ids}
end
local function dismiss(receipt)
 if math.type(receipt)~='integer' or receipt<=0 or not retained or receipt~=retained.receipt then
  return fail('Alert dismissal receipt expired')
 end
 local source=df.global.world.status.alert_button_announcement_id
 local ids=retained.ids
 -- Consume even rejected receipts; unknown outcomes must never be replayed.
 retained=nil
 if #source~=#ids then return fail('Alert references changed')end
 for i,id in ipairs(ids)do if source[i-1]~=id then return fail('Alert references changed')end end
 source:resize(0)
 return {ok=true,count=#ids}
end
local function reset()retained=nil end
return capture,dismiss,reset
