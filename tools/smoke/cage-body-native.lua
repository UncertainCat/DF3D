-- Native parent-body oracle, with reversible assignment through the owned API.
local out,view,cage,capture=...
local json=require('json');local g=df.global.gps
local frame=df.global.world.frame_counter;local flags=cage.cage_flags.whole
local function ids(v)local t={};for _,id in ipairs(v)do t[#t+1]=id end;return t end
local before={units=ids(cage.assigned_units),items=ids(cage.assigned_items)}
local result={id=cage.id,contained={},rooms={},cases={}}
assert(#cage.contained_items>0)
for _,ref in ipairs(cage.contained_items[0].item.general_refs)do
 if ref:getType()==df.general_ref_type.CONTAINS_UNIT then
  local u=ref:getUnit();result.contained[#result.contained+1]={entity=1,id=u and u.id or -1}
 elseif ref:getType()==df.general_ref_type.CONTAINS_ITEM then
  local item=ref:getItem();if item and item:isLiveAnimal()then result.contained[#result.contained+1]={entity=2,id=item.id}end
 end
end
for _,zone in ipairs(cage.relations)do
 local row={id=zone.id,type=zone.type,site_id=zone.site_id,location_id=zone.location_id}
 local site=df.world_site.find(zone.site_id)
 if site then for _,location in ipairs(site.buildings)do if location.id==zone.location_id then
  row.location_type=location:getType();local contents=location:getContents();row.location_tier=contents and contents.location_tier or -1
 end end end
 result.rooms[#result.rooms+1]=row
end
local function record(label)
 view:render(dfhack.getTickCount());capture('cage-body-'..label)
 local row={label=label,units=ids(cage.assigned_units),items=ids(cage.assigned_items),lines={}}
 for y=8,31 do
  local chars={};for x=54,110 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
 end
 result.cases[#result.cases+1]=row
end
local function request(...)
 local text,code=dfhack.run_command_silent('df3d','cage-state-probe',tostring(cage.id),...);assert(code==0,text);return json.decode(text)
end
local state=request();local id
for _,row in ipairs(state.rows)do if row.kind==0 and not row.assigned then id=row.id;break end end
assert(id,'Missing unassigned candidate')
local function edit(value)
 local current=request();local receipt=request(tostring(current.revision),tostring(id),'0',value and '1'or'0')
 assert(receipt.outcome==1,'Cage body setup effect failed')
end
record('contained-item')
local ok,err=xpcall(function()edit(true);record('assigned-unit')end,debug.traceback)
edit(false);cage.cage_flags.whole=flags
assert(json.encode(before)==json.encode({units=ids(cage.assigned_units),items=ids(cage.assigned_items)}))
assert(df.global.world.frame_counter==frame)
assert(ok,err)
record('restored');result.success=true;result.restored=true
local f=assert(io.open(out..'/cage-body-native.json','w'));f:write(json.encode(result));f:close()
