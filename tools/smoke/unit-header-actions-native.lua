-- Native input/layout reference in the paused, owned fixture. Names are restored.
local unit,view,capture,out=...
local gui=require('gui')
local g=df.global.gps
local main=df.global.game.main_interface
local sheet=main.view_sheets
local original={nickname=unit.name.nickname,profession=unit.custom_profession,
 customizing=sheet.unit_overview_customizing,nickname_focus=sheet.unit_overview_entering_nickname,
 profession_focus=sheet.unit_overview_entering_profession_nickname,draft=sheet.unit_overview_entering_str}
local frame=df.global.world.frame_counter
local figure=df.historical_figure.find(unit.hist_figure_id)
local soul=unit.status.current_soul
local saved_figure=figure and figure.name.nickname
local saved_soul=soul and soul.name.nickname
local observations={}
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.mouse_x=x//8;g.mouse_y=(y-4)//12;g.precise_mouse_x=x;g.precise_mouse_y=y
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function record(name,edited)
 capture('unit-header-actions-'..name)
 observations[#observations+1]={name=name,customizing=sheet.unit_overview_customizing,
  nickname_focus=sheet.unit_overview_entering_nickname,
  profession_focus=sheet.unit_overview_entering_profession_nickname,
  draft=dfhack.df2utf(sheet.unit_overview_entering_str),open=sheet.open,active_id=sheet.active_id,
  nickname=dfhack.df2utf(unit.name.nickname),profession=dfhack.df2utf(unit.custom_profession),
  figure_nickname=figure and dfhack.df2utf(figure.name.nickname),soul_nickname=soul and dfhack.df2utf(soul.name.nickname)}
 if sheet.unit_overview_customizing and not sheet.unit_overview_entering_nickname and not sheet.unit_overview_entering_profession_nickname then
  local guards={}
  for _,object in ipairs{sheet,df.global.plotinfo,unit}do
   local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
   dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={size=size,address=address,bytes=bytes}
  end
  local output,status=dfhack.run_command_silent('df3d','unit-customize-captions-probe',tostring(unit.id))
  local unchanged=true
  for _,guard in ipairs(guards)do
   if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
   df.delete(guard.bytes)
  end
  assert(status==0,output);assert(unchanged,'Customize reader changed warmed unit/menu state')
  local captions=require('json').decode(output)
  for _,field in ipairs{{'name',6},{'profession',9}}do
   local bytes={}
   for x=68,97 do local pen=dfhack.screen.readTile(x,field[2]);bytes[#bytes+1]=pen.ch>=32 and string.char(pen.ch) or ' ' end
   local expected=dfhack.utf2df(captions[field[1]]):sub(1,30):gsub('%s+$','')
   assert(expected==table.concat(bytes):gsub('%s+$',''),'Customize caption differs: '..name..' '..field[1])
  end
  observations[#observations].captions=captions
  observations[#observations].captions_native_match=true
  observations[#observations].captions_guards_unchanged=unchanged
 end
 if not edited then assert(unit.name.nickname==original.nickname and unit.custom_profession==original.profession,'focus action edited unit')end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'header reference advanced simulation')
end
local function click(x,y)
 pointer(x,y);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local ok,err=xpcall(function()
 local found
 for y=64,136,12 do for x=792,888,8 do
  pointer(x,y)
  if main.current_hover==df.main_hover_instruction.UNIT_SHEET_CUSTOMIZE then found={x,y};break end
 end if found then break end end
 assert(found,'native Customize hitbox not found')
 observations[#observations+1]={name='customize-hitbox',mouse=found,hover=main.current_hover}
 click(found[1],found[2]);assert(sheet.unit_overview_customizing,'Customize did not open editor')
 record('open')
 click(600,82);assert(sheet.unit_overview_entering_nickname,'nickname field did not focus');record('nickname-focus')
 click(600,118);assert(sheet.unit_overview_entering_profession_nickname,'profession field did not focus');record('profession-focus')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not sheet.unit_overview_customizing and sheet.open and sheet.active_id==unit.id,'Escape did not return to unit Overview')
 record('escape')
 local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
 local function text(value)for i=1,#value do key(('STRING_A%03d'):format(value:byte(i)))end end
 click(found[1],found[2]);click(600,82)
 text('Native nick');record('nickname-typed',true)
 assert(unit.name.nickname=='Native nick' and figure.name.nickname=='Native nick','native nickname propagation differs')
 assert(soul.name.nickname==saved_soul,'native nickname unexpectedly changed soul')
 key('SELECT');record('nickname-enter',true)
 key('LEAVESCREEN')
 click(found[1],found[2]);click(600,118)
 text('Native profession');record('profession-typed',true)
 assert(unit.custom_profession=='Native profession','native profession did not apply while typing')
 key('SELECT');record('profession-enter',true)
 key('LEAVESCREEN')
 local function restore_names()
  unit.name.nickname=original.nickname;unit.custom_profession=original.profession
  figure.name.nickname=saved_figure;soul.name.nickname=saved_soul
 end
 local function names()
  return {unit.name.nickname,unit.custom_profession,figure.name.nickname,soul.name.nickname}
 end
 -- Observe both focus orders through native input, including typing and Enter.
 -- The two flags share one draft; do not infer behavior from flags alone.
 for _,first in ipairs{'nickname','profession'}do
  restore_names()
  click(found[1],found[2])
  click(600,first=='nickname' and 82 or 118)
  click(600,first=='nickname' and 118 or 82)
  assert(sheet.unit_overview_entering_nickname and sheet.unit_overview_entering_profession_nickname,'dual focus setup failed')
  record('dual-'..first..'-before')
  text('Q');record('dual-'..first..'-typed',true)
  key('SELECT');record('dual-'..first..'-enter',true)
  key('LEAVESCREEN')
 end
 restore_names()
 for _,kind in ipairs{'nickname','profession'}do
  for index,value in ipairs{'Compared name','',string.rep('X',30),'Native '..string.char(130)}do
   restore_names()
   click(found[1],found[2]);click(600,kind=='nickname' and 82 or 118)
   for i=1,40 do key('STRING_A000')end
   text(value);key('SELECT');key('LEAVESCREEN')
   local expected=names()
   assert(expected[kind=='nickname' and 1 or 2]==value,'native text entry differs')
   restore_names()
   local guards={}
   for _,object in ipairs{sheet,df.global.plotinfo}do
    local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
    dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={size=size,address=address,bytes=bytes}
   end
   local output,status=dfhack.run_command_silent('df3d','unit-header-name-write-probe',tostring(unit.id),kind,dfhack.df2utf(value))
   local unchanged=true
   for _,guard in ipairs(guards)do
    if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
    df.delete(guard.bytes)
   end
   assert(status==0,output);assert(unchanged,'direct name write changed menu state')
   for i,actual in ipairs(names())do assert(actual==expected[i],'direct name write differs from native')end
   observations[#observations+1]={name='direct-'..kind..'-'..index,value=dfhack.df2utf(value),native_match=true,menu_unchanged=unchanged}
  end
 end
 local before=names()
 local _,status=dfhack.run_command_silent('df3d','unit-header-name-write-probe',tostring(unit.id),'nickname',string.rep('X',31))
 assert(status~=0,'oversized nickname accepted')
 for i,actual in ipairs(names())do assert(actual==before[i],'oversized write changed names')end
 observations[#observations+1]={name='oversized-refused',unchanged=true}
 local json=require('json')
 local function receipt()
  local output,status=dfhack.run_command_silent('df3d','unit-header-name-edit-read',tostring(unit.id))
  assert(status==0,output);return json.decode(output)
 end
 restore_names()
 local prior=receipt()
 unit.custom_profession='External change'
 local output,status=dfhack.run_command_silent('df3d','unit-header-name-write-probe',tostring(unit.id),'nickname','Stale write',tostring(prior.revision))
 local stale=json.decode(output)
 assert(status~=0 and stale.outcome==2 and not stale.mutated,'stale edit was not rejected')
 assert(unit.name.nickname==original.nickname and unit.custom_profession=='External change' and figure.name.nickname==saved_figure,'stale edit changed names')
 observations[#observations+1]={name='stale-revision',outcome=stale.outcome,mutated=stale.mutated,unchanged=true}
 restore_names()
 figure.name.nickname='Divergent history'
 click(found[1],found[2]);click(600,82);key('SELECT');key('LEAVESCREEN')
 assert(figure.name.nickname=='Divergent history','native unchanged nickname repaired historical name')
 local current=receipt()
 output,status=dfhack.run_command_silent('df3d','unit-header-name-write-probe',tostring(unit.id),'nickname',dfhack.df2utf(unit.name.nickname),tostring(current.revision))
 local unchanged=json.decode(output)
 assert(status==0 and unchanged.outcome==1 and not unchanged.mutated,'unchanged edit was not a no-op')
 assert(figure.name.nickname=='Divergent history','direct unchanged nickname repaired historical name')
 observations[#observations+1]={name='unchanged-divergent-history',outcome=unchanged.outcome,mutated=unchanged.mutated,native_match=true}
end,debug.traceback)
unit.name.nickname=original.nickname;unit.custom_profession=original.profession
if figure then figure.name.nickname=saved_figure end
if soul then soul.name.nickname=saved_soul end
sheet.unit_overview_customizing=original.customizing
sheet.unit_overview_entering_nickname=original.nickname_focus
sheet.unit_overview_entering_profession_nickname=original.profession_focus
sheet.unit_overview_entering_str=original.draft
pointer(0,4)
assert(ok,err)
do
 local output,status=dfhack.run_command_silent('df3d','unit-customize-captions-probe',tostring(unit.id))
 assert(status==0,output)
 local file=assert(io.open(out..'/unit-customize-captions.json','w'));file:write(output);file:close()
end
if os.getenv('DF3D_UNIT_HEADER_WIRE')=='1' then
 local json=require('json')
 local output,status=dfhack.run_command_silent('df3d','unit-header-name-edit-read',tostring(unit.id))
 assert(status==0,output);local expected=json.decode(output);expected.revision=tostring(expected.revision);expected.unit_id=unit.id
 -- The lane passes its evidence directory explicitly; the viewer environment
 -- is established by the PowerShell capture handler.
 assert(out,'missing header wire directory')
 local file=assert(io.open(out..'/unit-header-wire-expected.json','w'));file:write(json.encode(expected));file:close()
 capture('unit-header-wire')
 file=assert(io.open(out..'/unit-header-wire-result.json'));local result=json.decode(file:read('*a'));file:close()
 assert(result.success and result.restored,'header wire verification failed')
 assert(unit.name.nickname==original.nickname and unit.custom_profession==original.profession and
  figure.name.nickname==saved_figure and soul.name.nickname==saved_soul,'header wire changed restored names')
 observations[#observations+1]={name='wire',result=result}
end
return observations
