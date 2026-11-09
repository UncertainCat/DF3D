-- Controlled diagnostic only: paused disposable clone, all fields restored.
local out,probe,run=...
local json=require('json')
assert(df.global.pause_state,'Door state capture requires a paused clone')
local selection=probe('stocks-selection-probe','6','')
local chosen={}
for _,id in ipairs(selection.groups[1].ids)do
 local item=assert(df.item.find(id));local door=dfhack.items.getHolderBuilding(item)
 if door and df.building_doorst:is_instance(door)then
  chosen[#chosen+1]={item=item,door=door,wear=item.wear,flags=door.door_flags.whole,timer=door.close_timer}
  if #chosen==8 then break end
 end
end
assert(#chosen==8,'Door state fixture needs eight visible installed doors')
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(json.encode(value));f:close()end
local function restore()
 for _,row in ipairs(chosen)do row.item.wear=row.wear;row.door.door_flags.whole=row.flags;row.door.close_timer=row.timer end
 for _,row in ipairs(chosen)do assert(row.item:getWear()==row.wear and row.door.door_flags.whole==row.flags and row.door.close_timer==row.timer,'Door fixture restoration failed')end
 write('stocks-door-states-restored.json',{restored=true,count=#chosen})
end
return dfhack.with_finalize(restore,function()
 local cases={}
 for i,row in ipairs(chosen)do
  local wear=(i-1)//2;local open=i%2==0
  row.item.wear=wear;row.door.close_timer=open and 10 or 0;row.door.door_flags.forbidden=true
  cases[#cases+1]={id=row.item.id,building_id=row.door.id,open=open,forbidden=true,wear=wear,original_wear=row.wear,original_flags=row.flags,original_timer=row.timer}
 end
 local offsets={};local offset=0
 for _,group in ipairs(probe('stocks-selection-probe','6','').groups)do
  offset=offset+1
  for _,id in ipairs(group.ids)do offsets[id]=offset;offset=offset+1 end
 end
 for _,case in ipairs(cases)do case.row_index=assert(offsets[case.id])end
 write('stocks-door-states.json',{cases=cases})
 return run()
end)
