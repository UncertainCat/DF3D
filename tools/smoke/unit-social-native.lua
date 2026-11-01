-- Native Relations and Groups reference; diagnostic menu access only in a protected clone.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local function row(y)
 local text={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 return table.concat(text)
end
local function select(name,first,last)
 for y=first,last do local x=row(y):find(name,1,true);if x then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=(x-1)*8+4;g.precise_mouse_y=y*12+10;g.mouse_x=x-1;g.mouse_y=y
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  return
 end end
 error('Missing creature tab '..name)
end
local subjects={unit};local result={pages={}}
for _,candidate in ipairs(df.global.world.units.active)do
 if candidate.military.squad_id>=0 and dfhack.units.isAlive(candidate)then subjects[#subjects+1]=candidate;break end
end
for _,subject in ipairs(subjects)do
 sheet.active_id=subject.id;view:render(dfhack.getTickCount())
 for _,name in ipairs{'Relations','Groups'}do
  select(name,13,16)
  local page={unit_id=subject.id,name=name,lines={},rows={}}
  for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
  if name=='Relations'then
   for i,text in ipairs(sheet.rel_name)do
    page.rows[#page.rows+1]={caption=dfhack.df2utf(text.value),relation=sheet.relation[i],flags=sheet.relation_f[i],unit_id=sheet.rel_unid[i],hf_id=sheet.rel_hf[i] and sheet.rel_hf[i].id or -1,value=sheet.rel_value[i]}
   end
  else
   for i,id in ipairs(sheet.unit_group_enid)do
    page.rows[#page.rows+1]={entity_id=id,link=sheet.unit_group_hfel[i],position_id=sheet.unit_group_epid[i],assignment_id=sheet.unit_group_eppid[i],spouse=sheet.unit_group_ep_is_spouse[i],reputation=sheet.unit_group_rep[i],level=sheet.unit_group_rep_level[i]}
   end
  end
  result.pages[#result.pages+1]=page;capture('unit-social-'..subject.id..'-'..name:lower())
 end
end
sheet.active_id=unit.id;view:render(dfhack.getTickCount());select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Social reference advanced simulation')
local file=assert(io.open(out..'/unit-social-native.json','w'));file:write(json.encode(result));file:close()
return result
