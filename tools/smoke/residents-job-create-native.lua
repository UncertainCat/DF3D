-- Protected oracle only: create the reference through native workshop controls.
local out,view=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function pointer(x,y)
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
end
local function click(x,y)
 pointer(x,y);df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function label(text)
 local rows={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=126 and string.char(ch)or' 'end
  local line=table.concat(chars);rows[#rows+1]=line
  local at=line:find(text,1,true);if at then click(at-1,y);return true end
 end
 local f=assert(io.open(out..'/residents-production-missing-label.txt','w'));f:write(text..'\n'..table.concat(rows,'\n'));f:close()
 return false
end
local multiple=os.getenv('DF3D_RESIDENTS_JOB_MULTIPLE')=='1'
local workshop_type=multiple and 'Jewelers' or 'Masons'
local job_type=multiple and df.job_type.EncrustWithStones or df.job_type.ConstructStatue
local building
for _,b in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
 if df.building_workshopst:is_instance(b) and df.workshop_type[b.type]==workshop_type and b:getBuildStage()==b:getMaxBuildStage()then building=b;break end
end
assert(building,'No completed native workshop: '..workshop_type)
gui.simulateInput(view,'LEAVESCREEN');settle()
dfhack.gui.revealInDwarfmodeMap({x=building.centerx,y=building.centery,z=building.z},true)
df.global.window_x=math.max(0,building.centerx-8);df.global.window_y=math.max(0,building.centery-10);settle()
local found=false
for y=5,g.dimy-4 do
 for x=0,48 do
  pointer(x,y);local p=dfhack.gui.getMousePos(true)
  if p and p.x==building.centerx and p.y==building.centery and p.z==building.z then click(x,y);found=true;break end
 end
 if found then break end
end
assert(found,'Workshop map selection failed')
assert(label('Add new task'),'Workshop Add new task missing')
click(58,12)
for character in (multiple and 'stone' or 'statue'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(character:byte()))end
settle()
local caption='Make rock statue'
if multiple then
 local choices={};caption=nil
 for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
  if df.interface_button_building_new_jobst:is_instance(button)then
   local text=dfhack.df2utf(require('utils').call_with_string(button,'text'))
   choices[#choices+1]={caption=text,type=button.jobtype,unavailable=button.show_help_instead}
   if not caption and button.jobtype==job_type and not button.show_help_instead then caption=text end
  end
 end
 local f=assert(io.open(out..'/residents-production-create-choices.json','w'));f:write(require('json').encode(choices));f:close()
end
assert(caption and label(caption),'Native production choice missing')
local job=building.jobs[#building.jobs-1]
assert(job and job.job_type==job_type and #job.job_items.elements>=(multiple and 2 or 1),'Native production task did not create required inputs')
local f=assert(io.open(out..'/residents-production-created.json','w'));f:write(require('json').encode({job_id=job.id,building_id=building.id,requirements=#job.job_items.elements}));f:close()
gui.simulateInput(view,'LEAVESCREEN');gui.simulateInput(view,'D_UNITLIST');settle()
return job
