-- Protected native oracle only. Runtime providers must never read this menu.
local out,view,info,job,button,evidence,owner=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local m=df.global.game.main_interface;local art=m.image_creator;local g=df.global.gps
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return result
end
local function label(text)
 for _,line in ipairs(lines())do local x=line.text:find(text,1,true);if x then click(x-1,line.y);return end end
 error('Missing artwork label: '..text)
end
local function effect()return {type=job.art_spec.type,id=job.art_spec.id,subid=job.art_spec.subid,requirements=#job.job_items.elements,art_open=art.open,details_open=m.job_details.open,info_open=info.open}end
evidence.artwork={};local result=evidence.artwork
local function save()
 local f=assert(io.open(out..'/residents-job-art-reference.json','w'));f:write(json.encode(evidence));f:close()
end
local function shot(name)
 save();local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Job art capture timeout');script.sleep(1,'frames')end
end
settle()
assert(art.open and art.ics.jb==job and not art.ics.wq,'Job did not open job-backed artwork')
result.context=art.context;result.header=dfhack.df2utf(art.header);result.root=lines();result.before=effect()
shot('residents-job-art-root')
if os.getenv('DF3D_RESIDENTS_JOB_ART_PROVIDER')=='1' then
 result.provider={}
 for kind,caption in ipairs({'Related to historical figure','Related to site','Related to civilization or other group'})do
  -- Cold owned read before native populates that subject list.
  local old=owner.job.current_job;owner.job.current_job=job
  local ok,text,rc=pcall(dfhack.run_command_silent,'df3d','residents-job-art-subjects-probe',tostring(owner.id),tostring(kind))
  owner.job.current_job=old
  assert(ok and rc==0,'Owned job art subject read failed: '..tostring(text))
  local observed=json.decode(text)
  assert(art.open and art.current_option==-1 and art.ics.jb==job,'Owned read changed native artwork state')
  assert(observed.caption==result.header and observed.job_id==job.id,'Owned job art header/identity differs')
  label(caption)
  local rows=kind==1 and art.hf or kind==2 and art.st or art.ent
  assert(#observed.ids==#rows,'Owned subject count differs')
  for i,row in ipairs(rows)do assert(observed.ids[i+1]==row.id,'Owned subject order differs')end
  result.provider[#result.provider+1]={kind=kind,count=#rows,revision=observed.revision,list_revision=observed.list_revision,matched=true}
  df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R')
  df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1;settle()
  assert(art.open and art.current_option==-1,'Subject Back did not return to artwork root')
 end
end
label('Related to historical figure')
assert(art.current_option==1 and #art.hf>0,'Figure page did not open')
result.figures={};for _,hf in ipairs(art.hf)do result.figures[#result.figures+1]=hf.id end
result.figure_lines=lines();shot('residents-job-art-figures')
local chosen=art.hf[0].id
-- Native first subject row below the filter, verified in captured layout.
click(10,14)
result.figure_effect=effect();result.figure_choice=chosen
assert(job.art_spec.type==0 and job.art_spec.id==chosen and job.art_spec.subid==result.before.subid,'Figure selection effect differs')
assert(not art.open and not m.job_details.open and info.open,'Figure selection did not return to Residents')
click(button.rect.x1+1,button.rect.y1+1)
assert(art.open and art.ics.jb==job,'Artwork did not reopen')
label('Allow artist to choose')
result.artist_effect=effect()
assert(job.art_spec.type==-1 and job.art_spec.id==-1 and job.art_spec.subid==-1 and not art.open,'Artist choice did not clear specification')
click(button.rect.x1+1,button.rect.y1+1);assert(art.open,'Artwork did not reopen for cancellation')
gui.simulateInput(view,'LEAVESCREEN');settle();result.escape=effect();save()
assert(art.open and info.open,'Artwork Escape changed the native editor')
df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R')
df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1;settle()
result.right_click=effect();save()
assert(not art.open and not m.job_details.open and info.open,'Artwork right click did not return to Residents')
