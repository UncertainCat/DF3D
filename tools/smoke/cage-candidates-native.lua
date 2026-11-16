-- Protected native oracle only: widget storage is never a runtime input.
local view,cage=...
local main=df.global.game.main_interface
local function find_list(widget,depth)
 assert(depth<10,'Cage widget depth exceeded')
 if df.widget_unit_list:is_instance(widget)then return df.reinterpret_cast(df.widget_unit_list,widget)end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%16==0 and last-first<=65536,'Invalid cage widget children')
 for at=first,last-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then local list=find_list(df.reinterpret_cast(df.widget,ptr),depth+1);if list then return list end end
 end
end
local list=assert(find_list(main.unit_selector,0),'Cage list absent')
local native={}
for _,entry in ipairs(list.entry_list)do
 local id=entry.t==0 and entry.u and entry.u.id or entry.t==1 and entry.i and entry.i.id or -1
 assert(id>=0,'Invalid native cage entry')
 native[#native+1]={kind=entry.t,id=id}
end
local guards={}
for _,value in ipairs{df.global.gps,main}do
 local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
 dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
end
local text,code=dfhack.run_command_silent('df3d','cage-candidates-read',tostring(cage.id))
assert(code==0,text)
local owned=require('json').decode(text)
assert(#owned==#native,'Cage candidate count differs')
for i,row in ipairs(owned)do
 assert(row.kind==native[i].kind and row.id==native[i].id,'Cage candidate producer order differs at '..i)
 local assigned=false
 for _,id in ipairs(row.kind==0 and cage.assigned_units or cage.assigned_items)do if id==row.id then assigned=true end end
 assert(row.assigned==assigned,'Cage assignment state differs')
end
for _,guard in ipairs(guards)do
 assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'Cage read changed native UI/drawing state')
 df.delete(guard.copy)
end
local result={native=native,owned=owned,flags=cage.cage_flags.whole,ui_unchanged=true}
local mode=os.getenv('DF3D_CAGE_EFFECT')
if mode=='native' or mode=='owned'then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('cage%-candidates%-native.lua$','cage-assignment-native.lua')
 result.effects=assert(loadfile(source))(view,cage,list,mode)
end
return result
