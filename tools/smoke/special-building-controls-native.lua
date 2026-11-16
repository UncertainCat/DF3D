-- Paused native-input evidence; no runtime UI state is used by the product.
local out,view,b,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local kind=b:getType();local result={type=kind,building_id=b.id,cases={}}
local function read_owned()
 if os.getenv('DF3D_SPECIAL_BUILDINGS_READERS')~='1' then return nil end
 local guards={}
 for _,value in ipairs{g,df.global.game.main_interface}do
  local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
  dfhack.internal.memmove(copy,address,size);guards[#guards+1]={size=size,address=address,copy=copy}
 end
 local text,code=dfhack.run_command_silent('df3d','special-building-read',tostring(b.id))
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'Owned reader changed native UI storage')
  df.delete(guard.copy)
 end
 assert(code==0,text);local body=json.decode(text);assert(body.building_id==b.id and body.type==kind)
 if kind==24 then
  assert(body.bait_type==b.bait_type and body.state==1)
  local names={[-1]='Nothing',[48]='Meat',[49]='Fish',[44]='Large gem'}
  assert(body.status=='Desired bait: '..names[b.bait_type] and body.item_id==-1 and body.name=='')
 elseif kind==48 then
  assert(body.claimant_id==b.claimed_by)
  if b.claimed_by==-1 then assert(body.status=='Nest box unclaimed' and body.name=='')
  else assert(body.status=='Nest box claimed by' and body.name=='Stray Drake (Tame)' and body.color)end
 elseif kind==49 then
  assert(body.flags==b.hive_flags.whole and body.crowding==0 and body.matching_colonies==0)
  assert(body.outdoor_access==false and body.colony_race==-1)
 end
 return body
end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function shot(label,facts)
 local name='special-building-'..kind..'-'..label;capture(name)
 facts.owned=read_owned()
 facts.reference=name;result.cases[#result.cases+1]=facts
end
assert(#b.jobs==0)
if kind==24 then
 local before=b.bait_type
 for i,bait in ipairs{48,49,44,-1}do
  click(444+(i-1)*24,202)
  assert(b.bait_type==bait,'Animal trap bait click differs')
  assert(#b.jobs==0);shot('bait-'..i,{bait_type=b.bait_type})
 end
 b.bait_type=before;result.restored=b.bait_type==before
elseif kind==49 then
 local before=b.hive_flags.whole
 click(444,148);assert(b.hive_flags.whole==(before~1));shot('install',{flags=b.hive_flags.whole})
 click(444,184);assert(b.hive_flags.whole==(before~3));shot('gather',{flags=b.hive_flags.whole})
 click(444,148);assert(b.hive_flags.whole==(before~2));shot('no-install',{flags=b.hive_flags.whole})
 click(444,184);assert(b.hive_flags.whole==before);shot('restored',{flags=b.hive_flags.whole})
 assert(#b.jobs==0);result.restored=true
elseif kind==48 then
 local before=b.claimed_by
 -- Controlled claim display; this does not assert natural nesting eligibility.
 local unit=assert(df.unit.find(6960));b.claimed_by=unit.id;view:render(dfhack.getTickCount())
 shot('claimed',{claimed_by=b.claimed_by})
 b.claimed_by=before;view:render(dfhack.getTickCount());shot('restored',{claimed_by=b.claimed_by})
 result.restored=true
end
assert(result.restored and #b.jobs==0)
if os.getenv('DF3D_SPECIAL_BUILDINGS_EDITS')=='1' and (kind==24 or kind==49)then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('special%-building%-controls%-native.lua$','special-building-edits-native.lua')
 result.edits=assert(loadfile(source))(out,view,b,click)
 assert(#b.jobs==0)
end
local f=assert(io.open(out..'/special-building-'..kind..'-controls.json','w'));f:write(json.encode(result));f:close()
return result
