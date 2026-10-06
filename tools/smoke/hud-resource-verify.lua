-- Protected clone controls and native rendered references; never runtime UI reads.
local out,index=...
local json=require('json')
local function write(path,v)local f=assert(io.open(path,'w'));f:write(json.encode(v));f:close()end
local request
if index=='cleanup' then request={op='hud_restore'} else
 local f=assert(io.open(out..'/request-'..index..'.json'));request=json.decode(f:read('*a'));f:close()
end
local food=df.global.plotinfo.tasks.food
local nobles=df.global.plotinfo.nobles
local fields={'total','drink','seeds','meat','fish','plant','other'}
local state=_G.df3d_hud_resource_fixture
if not state then
 state={counts={},precision=nobles.bookkeeper_precision,frame=df.global.world.frame_counter}
 for _,k in ipairs(fields)do state.counts[k]=food[k]end
 _G.df3d_hud_resource_fixture=state
end
assert(df.global.pause_state and df.global.world.frame_counter==state.frame,'simulation advanced')
if request.op=='hud_set' then
 assert(request.value>=0 and request.value<=2147483647 and request.precision>=0)
 for _,k in ipairs(fields)do food[k]=k=='drink' and request.value or 0 end
 nobles.bookkeeper_precision=request.precision
elseif request.op=='hud_restore' then
 for k,v in pairs(state.counts)do food[k]=v end
 nobles.bookkeeper_precision=state.precision
else error('unexpected HUD control')end
local screen=dfhack.gui.getDFViewscreen(true)
assert(df.viewscreen_dwarfmodest:is_instance(screen),'native fortress screen required')
screen:render(dfhack.getTickCount())
assert(df.global.gps.dimx==150,'reference columns require the protected 1200px viewport')
local line=''
for x=62,85 do local t=dfhack.screen.readTile(x,2);local ch=t and t.ch or 32;line=line..(ch>=32 and ch<127 and string.char(ch)or' ')end
local expected=line:match('(~?%-?%d+)%s*$')or line:match('(None)%s*$')
assert(expected,'native Drink text absent: '..line)
local counts={};for _,k in ipairs(fields)do counts[#counts+1]=food[k]end
if index~='cleanup' then write(out..'/native-'..index..'.json',{counts=counts,precision=nobles.bookkeeper_precision,drink=expected,line=line})end
if request.op=='hud_restore' then
 for k,v in pairs(state.counts)do assert(food[k]==v,'counter restoration failed')end
 assert(nobles.bookkeeper_precision==state.precision,'precision restoration failed')
 write(out..'/hud-restoration.json',{restored=true,counts=counts,precision=nobles.bookkeeper_precision,frame=state.frame})
end
print('SEMANTIC_PASS '..request.op)
if index~='cleanup' then write(out..'/response-'..index..'.json',{status='passed'})end
