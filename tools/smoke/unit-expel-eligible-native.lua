local unit,view,pointer,out=...
local json=require('json')
local main=df.global.game.main_interface
local sheet=main.view_sheets
local profession=unit.profession
local flags=unit.flags2.whole
local frame=df.global.world.frame_counter
local observations={}
local ok,err=xpcall(function()
 local cases={{'adult',profession,true},{'child',df.profession.CHILD,false},{'baby',df.profession.BABY,false},
  {'trained-hunter',df.profession.TRAINED_HUNTER,false},{'trained-war',df.profession.TRAINED_WAR,false},
  {'master-thief',df.profession.MASTER_THIEF,false},{'thief',df.profession.THIEF,false},
  {'standard',df.profession.STANDARD,true},{'visitor',profession,false,true}}
 for _,case in ipairs(cases)do
  unit.profession=case[2];unit.flags2.whole=flags
  if case[4]then unit.flags2.visitor=true end
  pointer(872,118)
  local visible=main.current_hover==df.main_hover_instruction.EXPEL_UNIT
  local guards={}
  for _,object in ipairs{unit,sheet,df.global.plotinfo}do
   local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
   dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  local output,status=dfhack.run_command_silent('df3d','unit-expel-eligible-probe',tostring(unit.id))
  local unchanged=true
  for _,guard in ipairs(guards)do
   if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
   df.delete(guard.bytes)
  end
  assert(status==0,output);local result=json.decode(output)
  observations[#observations+1]={name=case[1],profession=case[2],native_visible=visible,reader=result.eligible,guards_unchanged=unchanged}
  assert(unchanged,'Eligibility reader changed unit or native UI')
  assert(visible==case[3] and result.eligible==visible,'Eligibility differs: '..case[1])
 end
 assert(df.global.pause_state and df.global.world.frame_counter==frame)
end,debug.traceback)
unit.profession=profession;unit.flags2.whole=flags;pointer(400,400)
local result={success=ok,observations=observations,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-expel-eligible.json','w'));file:write(json.encode(result));file:close()
assert(ok,err)
