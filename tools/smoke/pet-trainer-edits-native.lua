-- Protected native click/provider comparison, invoked with the picker open.
local out,view,info,callbacks=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local f=assert(io.open(out..'/pet-trainer-fixture.json'));local id=json.decode(f:read('*a')).id;f:close()
local function read(revision,mode,trainer)
 local args={'df3d','pet-trainer-edit-probe',tostring(id)}
 if revision then args[#args+1]=revision;args[#args+1]=tostring(mode);args[#args+1]=tostring(trainer)end
 local text,rc=dfhack.run_command_silent(table.unpack(args));assert(rc==0,text);return json.decode(text)
end
local function snapshot()
 local result={}
 for _,row in ipairs(df.global.plotinfo.training.training_assignments)do result[#result+1]={row.animal_id,row.trainer_id,row.flags.whole}end
 return result
end
local function restore(value)
 local rows=df.global.plotinfo.training.training_assignments
 for index,row in ipairs(rows)do if row.animal_id==id then rows:erase(index);row:delete();break end end
 for _,row in ipairs(value)do if row[1]==id then
  local entry=df.training_assignment:new();entry.animal_id=id;entry.trainer_id=row[2];entry.flags.whole=row[3]
  local index=0;while index<#rows and rows[index].animal_id<id do index=index+1 end
  rows:insert(index,entry);break
 end end
end
local function find(wanted,unit_id)
 local result
 local seen={}
 local function walk(widget)
  if (widget.flag.whole&1)==0 then return end
  local candidate=widget
  if df.widget_unit_name:is_instance(widget) and widget.u then seen[#seen+1]={id=widget.u.id,parent_callbacks=callbacks(widget.parent.custom_activated,64)}end
  if unit_id then
   if not df.widget_unit_name:is_instance(widget) or not widget.u or widget.u.id~=unit_id then candidate=nil else candidate=widget.parent end
  end
  if candidate then for _,address in ipairs(callbacks(candidate.custom_activated,64))do if address==wanted then result=candidate end end end
  if df.widget_container:is_instance(widget)then
   for ordinal,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if not df.widget_tabs:is_instance(widget) or ordinal-1==widget.cur_idx then walk(child)end end
  end
 end
 walk(info.creatures)
 if not result then
  local file=assert(io.open(out..'/pet-trainer-missing-action.json','w'));file:write(json.encode({wanted=wanted,unit=unit_id,seen=seen}));file:close()
 end
 return assert(result,'Trainer action missing '..wanted)
end
local function click(widget)
 local x=math.floor((widget.rect.x1+widget.rect.x2)/2);local y=math.floor((widget.rect.y1+widget.rect.y2)/2)
 local g=df.global.gps;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 -- Allow the native close/rebuild and mouse debounce to settle before the
 -- next opening click; three frames intermittently leave the picker closed.
 for _=1,15 do script.sleep(1,'frames')end
 view:render(dfhack.getTickCount())
end
local text,rc=dfhack.run_command_silent('df3d','pet-trainers-probe',tostring(id));assert(rc==0,text)
local trainer=assert(json.decode(text).rows[1]).id
local cases={{mode=1,trainer=-1,callback=0x3d1a90},{mode=2,trainer=-1,callback=0x3d19d0},
 {mode=3,trainer=trainer,callback=0x3d1850},{mode=1,trainer=-1,callback=0x3d1a90},{mode=0,trainer=-1,callback=0x3d1910}}
local original=snapshot();local evidence={}
local ok,err=pcall(function()
 for ordinal,case in ipairs(cases)do
  if ordinal>1 then
   -- Existing training flags must survive trainer changes (None removes all).
   local assignment=assert(df.training_assignment.find(id));assignment.flags.train_war=true
   click(find(0x3d1700))
  end
  local before=snapshot();local receipt=read()
  local invalid=read(receipt.revision,3,2147483647);assert(invalid.outcome==1 and json.encode(snapshot())==json.encode(before),'Unavailable trainer changed state')
  click(find(case.callback,case.mode==3 and trainer or nil))
  local native=snapshot();assert(json.encode(native)~=json.encode(before),'Trainer native click had no effect')
  restore(before)
  local applied=read(receipt.revision,case.mode,case.trainer)
  assert(applied.outcome==0 and json.encode(snapshot())==json.encode(native),'Trainer provider differs from native')
  local stale=read(receipt.revision,case.mode,case.trainer);assert(stale.outcome==2,'Stale trainer selection accepted')
  local duplicate=read(applied.revision,case.mode,case.trainer);assert(duplicate.outcome==1,'Duplicate trainer selection accepted')
  assert(json.encode(snapshot())==json.encode(native),'Rejected trainer selection changed state')
  evidence[#evidence+1]={mode=case.mode,trainer=case.trainer,before=before,native=native,provider=applied,stale=stale.outcome,duplicate=duplicate.outcome}
 end
end)
restore(original)
f=assert(io.open(out..'/pet-trainer-edits-reference.json','w'));f:write(json.encode({cases=evidence,restored=json.encode(snapshot())==json.encode(original),ok=ok,error=not ok and tostring(err) or nil}));f:close()
assert(ok,err);assert(json.encode(snapshot())==json.encode(original),'Trainer fixture not restored')
