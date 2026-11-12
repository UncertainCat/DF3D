-- Read-only oracle: inspect existing native rows and compare independently owned
-- text. No runtime code may consult these widgets or screen cells.
local out,view,probe,settle,tab,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
tab('Open cases');click(100,202);click(100,166);click(652,190)
local rows={}
local function walk(w)
 if (w.flag.whole&1)==0 then return end
 -- This fixed1200x800 reference shows13 rows. Native retains offscreen row
 -- widgets clamped to the list's bottom; those are not rendered evidence.
 if df.widget_unit_name:is_instance(w) and w.u and #rows<13 and w.rect.y1>=0 and w.rect.y2<g.dimy then
  local columns=math.max(w.min_w,w.rect.x2-w.rect.x1+1)
  local supplied=probe('justice-candidate-presentation-probe',{'9',tostring(w.u.id),tostring(columns)})
  local name_found=false;local label_found=false;local lines={}
  for y=math.max(0,w.rect.y1-2),math.min(g.dimy-1,w.rect.y2+1)do
   local chars={}
   for x=w.rect.x1,math.min(g.dimx-1,120)do local c=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=c>0 and c<=255 and string.char(c)or' 'end
   local line=dfhack.df2utf(table.concat(chars));lines[#lines+1]=line
   if line:find(supplied.name,1,true)==1 then name_found=true end
   if line:find(supplied.witness_label,1,true)then label_found=true end
  end
  rows[#rows+1]={unit_id=w.u.id,columns=columns,rect={w.rect.x1,w.rect.y1,w.rect.x2,w.rect.y2},supplied=supplied,lines=lines,
   name_found=name_found,label_found=label_found,one_line=w.one_line_only,show_gender=w.show_gender,show_profession=w.show_profession}
 end
 if df.widget_container:is_instance(w)then for index,child in ipairs(dfhack.gui.getWidgetChildren(w))do
  if not df.widget_tabs:is_instance(w)or index-1==w.cur_idx then walk(child)end
 end end
end
walk(df.global.game.main_interface.info.justice)
local f=assert(io.open(out..'/justice-candidate-presentation.json','w'));f:write(json.encode(rows));f:close()
capture('justice-candidate-presentation')
assert(#rows==13,'Expected13 visible native candidate rows')
for _,row in ipairs(rows)do
 assert(row.one_line and row.show_gender and row.show_profession,'Unexpected native candidate name mode')
 assert(row.name_found and row.label_found,'Native candidate text differs for '..row.unit_id)
end
gui.simulateInput(view,'LEAVESCREEN');settle()
if not df.global.game.main_interface.info.open then gui.simulateInput(view,'D_JUSTICE');settle()end
