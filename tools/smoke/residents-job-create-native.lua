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
local building
for _,b in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
 if df.building_workshopst:is_instance(b) and df.workshop_type[b.type]=='Masons' and b:getBuildStage()==b:getMaxBuildStage()then building=b;break end
end
assert(building,'No completed native stoneworker workshop')
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
for character in ('statue'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(character:byte()))end
settle()
assert(label('Make rock statue'),'Workshop statue choice missing')
local job=building.jobs[#building.jobs-1]
assert(job and job.job_type==df.job_type.ConstructStatue and #job.job_items.elements>0,'Native statue did not create real material requirements')
local f=assert(io.open(out..'/residents-production-created.json','w'));f:write(require('json').encode({job_id=job.id,building_id=building.id,requirements=#job.job_items.elements}));f:close()
gui.simulateInput(view,'LEAVESCREEN');gui.simulateInput(view,'D_UNITLIST');settle()
return job
