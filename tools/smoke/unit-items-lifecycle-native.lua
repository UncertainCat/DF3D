-- Diagnostic producer loss/replacement in the owned paused clone.
local unit,capture,out=...
local json=require('json');local enabled=true;local events={}
local prefix=os.getenv('DF3D_UNIT_HEALTH_LIFECYCLE')=='1'and'unit-health-lifecycle'or'unit-items-lifecycle'
local frame=df.global.world.frame_counter
local function service()
 local file=io.open(out..'/unit-items-lifecycle-request.json');if not file then return end
 local request=json.decode(file:read('*a'));file:close();assert(os.remove(out..'/unit-items-lifecycle-request.json'))
 assert(request.op=='disable' or request.op=='enable','invalid lifecycle operation')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'lifecycle advanced simulation')
 local text,status=dfhack.run_command_silent(request.op,'df3d');assert(status==0,text)
 enabled=request.op=='enable';events[#events+1]=request.op
 file=assert(io.open(out..'/unit-items-lifecycle-ack.tmp','w'));file:write(json.encode(request));file:close()
 assert(os.rename(out..'/unit-items-lifecycle-ack.tmp',out..'/unit-items-lifecycle-ack.json'))
end
local file=assert(io.open(out..'/'..prefix..'-expected.json','w'));file:write(json.encode{unit_id=unit.id});file:close()
local ok,err=xpcall(function()capture('farm-item-carrier-unit-scene',service)end,debug.traceback)
if not enabled then local text,status=dfhack.run_command_silent('enable','df3d');assert(status==0,text);enabled=true end
file=assert(io.open(out..'/'..prefix..'-native.json','w'));file:write(json.encode{success=ok,restored=enabled,events=events});file:close()
assert(ok,err)
assert(#events==2 and events[1]=='disable' and events[2]=='enable','lifecycle did not execute both transitions')
local scene_file=assert(io.open(out..'/'..prefix..'-scene.json','r'),'Missing lifecycle scene result')
local scene=json.decode(scene_file:read('*a'));scene_file:close();assert(scene.success,'Lifecycle scene failed')
return {success=true,restored=true,events=events}
