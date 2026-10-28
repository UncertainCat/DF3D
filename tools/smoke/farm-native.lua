-- Protected owned paused native farm reference; never used by runtime.
-- Called by stockpile_storage_native.lua with save preservation and unsaved exit.
local out,view,records=...
local script=require('gui.script')
  local gui=require('gui');local g=df.global.gps
  assert(df.global.pause_state);local frame=df.global.world.frame_counter
  assert(dfhack.run_command('disable','overlay')==0)
  local b=assert(df.global.world.buildings.other.FARM_PLOT[0],'fixture has no farm')
  local function semantic_rows()
   local guards={}
   local function guard(address,size)
    local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
    guards[#guards+1]={address=address,size=size,bytes=bytes}
   end
   for _,object in ipairs{b,df.global.plotinfo,df.global.game.main_interface,g}do
    local size,address=df.sizeof(object);guard(address,size)
   end
   local base=dfhack.internal.getImageBase()
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2}}do guard(base+range[1],range[2])end
   local rows={}
   for id,plant in ipairs(df.global.world.raws.plants.all)do
    if plant.flags.SEED then
     local text,code=dfhack.run_command_silent('df3d','farm-eligibility-read',tostring(b.id),tostring(id))
     assert(code==0,text);local row=require('json').decode(text)
     assert(row.building_id==b.id and row.crop_id==id and #row.seasons==4,'invalid semantic result')
     rows[#rows+1]=row
    end
   end
   for _,args in ipairs{{'-1','0'},{tostring(b.id),'-1'},{tostring(b.id),'32768'},{'2147483647','0'}}do
    local _,code=dfhack.run_command_silent('df3d','farm-eligibility-read',args[1],args[2]);assert(code~=0,'invalid target accepted')
   end
   local choices={}
   for season=0,3 do
    local text,code=dfhack.run_command_silent('df3d','farm-choices-read',tostring(b.id),tostring(season))
    assert(code==0,text);choices[#choices+1]=require('json').decode(text)
   end
   for _,entry in ipairs(guards)do
    assert(dfhack.internal.memcmp(entry.bytes,entry.address,entry.size)==0,'semantic farm read changed guarded state')
    df.delete(entry.bytes)
   end
   return rows,choices
  end
  local cold=semantic_rows()
  local function capture(name)
   g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0
   for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
   local row={name=name,id=b.id,grid={g.dimx,g.dimy},lines={},crops={},seeds={},seasons={},raws={}}
   row.selected_season=df.global.game.main_interface.view_sheets.active_sub_tab
   row.current_season=df.global.cur_season;row.season_tick=df.global.cur_season_tick
   if name=='farm-selected' then
    row.sweet_pod_seed_items={}
    for _,item in ipairs(df.global.world.items.other.SEEDS)do if item.mat_index==176 then
     local flags={};for key,value in pairs(item.flags)do if type(key)=='string' and value==true then flags[#flags+1]=key end end
     table.sort(flags)
     row.sweet_pod_seed_items[#row.sweet_pod_seed_items+1]={id=item.id,quantity=item:getStackSize(),mat_type=item.mat_type,flags=item.flags.whole,set_flags=flags}
    end end
   end
   for y=0,g.dimy-1 do
    local line={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);line[#line+1]=t.ch>=32 and t.ch<127 and string.char(t.ch)or' ' end
    row.lines[#row.lines+1]=dfhack.df2utf(table.concat(line))
   end
   for _,id in ipairs(df.global.plotinfo.selected_farm_crops)do
    row.crops[#row.crops+1]=id
    if id>=0 then local p=df.plant_raw.find(id);row.raws[#row.raws+1]={id=id,name=p.name_plural,growdur=p.growdur,flags={p.flags.SPRING,p.flags.SUMMER,p.flags.AUTUMN,p.flags.WINTER}}end
   end
   row.name_colors={}
   for index,id in ipairs(row.crops)do
    local pen=dfhack.screen.readTile(61,17+(index-1)*3)
    row.name_colors[#row.name_colors+1]={crop_id=id,fg=pen.fg,bg=pen.bg,bold=pen.bold}
   end
   for _,value in ipairs(df.global.plotinfo.available_seeds)do row.seeds[#row.seeds+1]=value end
   for i=0,3 do row.seasons[#row.seasons+1]=b.plant_id[i]end
   local source=debug.getinfo(1,'S').source:sub(2):gsub('tools/smoke/farm%-native.lua$','bridge/plugin/production.lua')
   local adapter=assert(loadfile(source))()
   local result
   for i=1,100 do result=adapter{action=16,seq=1,production={building_id=b.id}};if not result.pending then break end end
   assert(not result.pending,'adapter read did not finish');row.adapter=result
   row.semantic,row.choices=semantic_rows();row.semantic_guards_unchanged=true
   assert(require('json').encode(row.semantic)==require('json').encode(cold),'semantic read depends on native sheet history')
   local eligible={}
   for _,entry in ipairs(row.semantic)do
    if entry.eligible and entry.seasons[row.selected_season+1]then eligible[entry.crop_id]=true end
   end
   for _,id in ipairs(row.crops)do if id>=0 then assert(eligible[id],'native menu includes an ineligible crop');eligible[id]=nil end end
   assert(next(eligible)==nil,'native menu omits a semantic eligible crop')
   local choices=row.choices[row.selected_season+1].rows
   assert(#choices==#row.crops-1,'choice count differs')
   local by_id={};for _,choice in ipairs(choices)do by_id[choice.crop_id]=choice end
   -- DF retains its entry order after a choice until the tab is rebuilt.
   local rebuilt=name~='farm-summer-fallow' and name~='farm-spring-no-seeds-choice'
   for index=2,#row.crops do
    local id=row.crops[index];local choice=assert(by_id[id],'native choice missing')
    if rebuilt then assert(choices[index-1].crop_id==id,'native choice order differs')end
    assert(choice.seeds_available==row.seeds[index],'native seed availability differs')
    local line=row.lines[18+(index-1)*3]:sub(62)
    assert(line:sub(1,#choice.name)==choice.name,'native choice name differs')
   end
   row.fresh_choice_order_compared=rebuilt
   records[#records+1]=row
   local f=assert(io.open(out..'/shot','w'));f:write(name);f:close()
   local limit=dfhack.getTickCount()+30000
   while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
    assert(dfhack.getTickCount()<limit,'capture timeout');script.sleep(1,'frames') end
  end
  df.global.game.main_interface.bottom_mode_selected=-1
  local point={x=b.centerx,y=b.centery,z=b.z}
  dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
  local found=false
  for y=0,g.dimy-1 do for x=0,g.dimx-1 do
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
   local p=dfhack.gui.getMousePos(true)
   if p and p.x==point.x and p.y==point.y and p.z==point.z then
    gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());found=true;break
   end
  end if found then break end end
  assert(found,'farm tile not visible');capture('farm-selected')
  for season,x in ipairs{470,600,720,840}do
   g.mouse_x=x//8;g.mouse_y=10;g.precise_mouse_x=x;g.precise_mouse_y=124
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   assert(df.global.game.main_interface.view_sheets.active_sub_tab==season-1,'season tab selection differs')
   capture('farm-season-'..(season-1))
  end
  local function click(x,y)
   g.mouse_x=x//8;g.mouse_y=y//12;g.precise_mouse_x=x;g.precise_mouse_y=y
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  end
  click(600,124);capture('farm-summer-before-choice')
  click(872,430);capture('farm-summer-red-choice')
  click(872,214);capture('farm-summer-fallow')
  click(470,124);capture('farm-spring-before-no-seeds-choice')
  click(872,358);capture('farm-spring-no-seeds-choice')
  assert(b.plant_id[0]==176,'native future season rejected the seedless crop')
  click(600,124);capture('farm-summer-after-spring-choice')
  click(872,430);capture('farm-summer-red-choice-after-spring')
  assert(b.plant_id[1]==-1,'native warning did not refuse the current-season crop')
  -- Controlled unsaved job fixtures establish the native input transaction.
  -- Runtime must not call this sheet handler or read its selected-crop vector.
  local function add_job(kind)
   local job=df.job:new();job.job_type=kind;job.posting_index=-1
   job.pos={x=b.centerx,y=b.centery,z=b.z}
   local ref=df.general_ref_building_holderst:new();ref.building_id=b.id
   job.general_refs:insert('#',ref)
   assert(dfhack.job.linkIntoWorld(job,true));b.jobs:insert('#',job)
   return job.id
  end
  local current=df.global.cur_season
  for _,args in ipairs{{'-1','0','-1'},{tostring(b.id),'-1','-1'},{tostring(b.id),'4','-1'},{tostring(b.id),'0','-2'},{'2147483647','0','-1'}}do
   local _,status=dfhack.run_command_silent('df3d','farm-crop-set',table.unpack(args))
   assert(status~=0,'invalid farm action accepted')
  end
  local function find_job(id)
   local link=df.global.world.jobs.list.next
   while link do
    if link.item and link.item.id==id then return link.item end
    link=link.next
   end
  end
  local text,code=dfhack.run_command_silent('df3d','farm-choices-read',tostring(b.id),tostring(current))
  assert(code==0,text)
  local allowed,warned
  for _,choice in ipairs(require('json').decode(text).rows)do
   if choice.current_season_warning then warned=choice.crop_id else allowed=choice.crop_id end
  end
  assert(allowed and warned,'fixture needs allowed and warned current-season crops')
  local tabs={470,600,720,840}
  for _,case in ipairs{
   {name='changed-current',season=current,before=-1,crop=allowed,cancel=true},
   {name='same-current',season=current,before=allowed,crop=allowed,cancel=false},
   {name='fallow-current',season=current,before=allowed,crop=-1,cancel=true},
   {name='fallow-already',season=current,before=-1,crop=-1,cancel=true},
   {name='warned-current',season=current,before=-1,crop=warned,cancel=false},
   {name='future-choice',season=0,before=-1,crop=176,cancel=false},
   {name='future-fallow',season=0,before=176,crop=-1,cancel=false},
  }do
   assert(current~=0,'future-season fixture requires a non-spring current season')
   for _,method in ipairs{'native','semantic'}do
   b.plant_id[case.season]=case.before
   -- Rebuild the tab after fixture setup. The click selects a real native row.
   click(tabs[(case.season+1)%4+1],124);click(tabs[case.season+1],124)
   local index
   for i,id in ipairs(df.global.plotinfo.selected_farm_crops)do if id==case.crop then index=i;break end end
   assert(index,'native action row missing: '..case.name)
   local planting={add_job(df.job_type.PlantSeeds),add_job(df.job_type.PlantSeeds)}
   local other=add_job(df.job_type.FertilizeField)
   local before={};for i=0,3 do before[#before+1]=b.plant_id[i]end
   if method=='native' then click(872,214+index*36)
   else
    local guards={}
    for _,object in ipairs{df.global.game.main_interface,g}do
     local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
     dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={address=address,size=size,bytes=bytes}
    end
    local base=dfhack.internal.getImageBase()
    for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2}}do
     local bytes=df.new('uint8_t',range[2]);dfhack.internal.memmove(bytes,base+range[1],range[2])
     guards[#guards+1]={address=base+range[1],size=range[2],bytes=bytes}
    end
    local output,status=dfhack.run_command_silent('df3d','farm-crop-set',tostring(b.id),tostring(case.season),tostring(case.crop))
    assert(status==0,output)
    assert(require('json').decode(output).accepted==(case.name~='warned-current'),'semantic admission differs')
    for _,guard in ipairs(guards)do
     assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'semantic crop action changed UI/GPS/RNG')
     df.delete(guard.bytes)
    end
   end
   local after={};for i=0,3 do after[#after+1]=b.plant_id[i]end
   local expected=case.name=='warned-current' and case.before or case.crop
   assert(after[case.season+1]==expected,'native crop write differs: '..case.name)
   for i=1,4 do if i~=case.season+1 then assert(before[i]==after[i],'unrelated season changed')end end
   local alive={}
   for _,id in ipairs(planting)do
    alive[#alive+1]=find_job(id)~=nil
    assert(alive[#alive]==not case.cancel,'native planting cancellation differs: '..case.name)
    local attached=false;for _,job in ipairs(b.jobs)do if job.id==id then attached=true end end
    assert(attached==alive[#alive],'farm/world job membership differs')
   end
   assert(find_job(other),'native removed nonplanting job')
   records[#records+1]={name='farm-job-action',case=case.name,method=method,season=case.season,crop=case.crop,
    before=before,after=after,planting_job_ids=planting,planting_jobs_alive=alive,
    other_job_id=other,other_job_alive=true,fixture_jobs_unassigned=true}
   for _,id in ipairs{planting[1],planting[2],other}do
    local job=find_job(id);if job then assert(dfhack.job.removeJob(job))end
   end
   end
  end
  assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
