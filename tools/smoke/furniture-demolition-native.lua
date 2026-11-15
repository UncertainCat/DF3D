-- Protected disposable-clone probe: native clicks queue jobs; DF executes them.
local out,view,records,buildings,select_map=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local result={scope='Native Remove clicks followed by bounded simulation; no forced job completion.',buildings={}}
local function persist()
 local f=assert(io.open(out..'/furniture-demolition.json','w'));f:write(json.encode(result));f:close()
end
local function capture(label,row)
 df.global.pause_state=true
 g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0
 for i=1,3 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 row.open=sheet.open;row.active_id=sheet.active_id;row.active_sheet=df.view_sheet_type[sheet.active_sheet]
 row.frame=df.global.world.frame_counter
 persist()
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(label);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+(label=='workshop-wire' and 180000 or 30000)
 while true do local ack=io.open(out..'/ack-'..label);if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'demolition capture timeout');script.sleep(1,'frames')end
end
local ok,err=xpcall(function()
 for _,entry in ipairs(buildings)do
  local target=assert(df.building.find(entry.id));local id=target.id
  local row={id=id,type=target:getType(),start_frame=df.global.world.frame_counter,items={},samples={}}
  for _,held in ipairs(target.contained_items)do row.items[#row.items+1]=held.item.id end
  result.buildings[#result.buildings+1]=row
  if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
  view:render(dfhack.getTickCount());select_map(target)
  assert(sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==id)
  g.precise_mouse_x=832;g.precise_mouse_y=82;g.mouse_x=104;g.mouse_y=6
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  assert(#target.jobs==1 and target.jobs[0].job_type==df.job_type.DestroyBuilding)
  row.job_id=target.jobs[0].id;row.before={};capture('demolition-'..id..'-before',row.before)
  local function advance()
   local deadline=dfhack.getTickCount()+90000;local last=-1
   while df.building.find(id) and dfhack.getTickCount()<deadline do
    local b=df.building.find(id);local job=b.jobs[0];local worker=job and dfhack.job.getWorker(job)
    local frame=df.global.world.frame_counter
    if last<0 or frame-last>=100 then
     row.samples[#row.samples+1]={frame=frame,job_id=job and job.id or -1,worker_id=worker and worker.id or -1,working=job and job.flags.working or false,counter=worker and worker.counters.job_counter or -1}
     last=frame;persist()
    end
    df.global.pause_state=false;script.sleep(1,'frames')
   end
   df.global.pause_state=true
  end
  if os.getenv('DF3D_FURNITURE_RUNTIME')=='1'then
   local f=assert(io.open(out..'/furniture-expected.json','w'));f:write(json.encode({buildings={{id=id,type=row.type,watch_demolition=true}}}));f:close()
   os.remove(out..'/ack-workshop-wire');os.remove(out..'/workshop-wire-result.json');os.remove(out..'/demolition-view-ready-'..id)
   local finished=false;local problem
   script.start(function()
    local ran,why=xpcall(function()
     local limit=dfhack.getTickCount()+90000
     while true do local marker=io.open(out..'/demolition-view-ready-'..id);if marker then marker:close();break end
      assert(dfhack.getTickCount()<limit,'Viewer did not open demolition panel');script.sleep(1,'frames')end
     advance()
    end,debug.traceback)
    df.global.pause_state=true;finished=true;problem=not ran and why or nil
   end)
   row.viewer_open={};capture('workshop-wire',row.viewer_open)
   assert(finished and not problem,problem or 'Viewer returned before simulation finished')
   f=assert(io.open(out..'/workshop-wire-result.json'));row.viewer=json.decode(f:read('*a'));f:close();assert(row.viewer.success,'Demolition viewer failed')
   for _,suffix in ipairs{'stdout.log','stderr.log','result.json'}do
    local input=assert(io.open(out..'/workshop-wire'..(suffix=='result.json' and '-' or '.')..suffix,'r'))
    local output=assert(io.open(out..'/demolition-'..id..'-'..suffix,'w'));output:write(input:read('*a'));output:close();input:close()
   end
  else
   advance()
  end
  df.global.pause_state=true;row.removed=df.building.find(id)==nil;row.after={}
  capture('demolition-'..id..'-after',row.after)
  assert(row.removed,'Native demolition did not complete within probe deadline')
  assert(not row.after.open,'Native panel remained open after completed demolition')
 end
end,debug.traceback)
df.global.pause_state=true;result.success=ok;result.error=ok and '' or tostring(err);persist()
records[#records+1]={name='furniture-demolition',result=result}
assert(ok,err)
