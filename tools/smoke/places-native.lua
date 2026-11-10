-- Protected discovery only. Native menu lists are observations, never runtime inputs.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json');local g=df.global.gps
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return result
end
local function capture(name)
 write('shot.tmp',name);assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Places capture timed out');script.sleep(1,'frames')end
end
local info=df.global.game.main_interface.info
local function menu_snapshot()
 local result={open=info.open,mode=info.current_mode,places_mode=info.buildings.mode,lists={}}
 for mode=0,5 do
  local ids={};for _,building in ipairs(info.buildings.list[mode])do ids[#ids+1]=building.id end
  local _,address=df.sizeof(info.buildings.list[mode]);local allocation={}
  for offset=0,16,8 do allocation[#allocation+1]=tostring(df.reinterpret_cast('uint64_t',address+offset).value)end
  result.lists[#result.lists+1]={ids=ids,allocation=allocation,scroll=info.buildings.scrolling_position[mode],drag=info.buildings.scrolling[mode]}
 end
 return json.encode(result)
end
local function probe(command)
 local before=menu_snapshot();local text,rc=dfhack.run_command_silent('df3d',command or 'places-lists-probe')
 assert(rc==0,'Owned Places provider failed: '..text);assert(menu_snapshot()==before,'Owned Places provider changed native menu storage')
 return json.decode(text)
end
local cold=probe()
local cold_rows=probe('places-building-rows-probe')
gui.simulateInput(view,'D_LOCATIONS');settle()
assert(info.open and info.current_mode==df.info_interface_mode_type.BUILDINGS,'Places shortcut did not open native Buildings')
local warm=probe()
local warm_rows=probe('places-building-rows-probe')
assert(json.encode(cold_rows)==json.encode(warm_rows),'Places building rows depend on menu initialization')
for mode=0,5 do
 local ids={};for _,building in ipairs(info.buildings.list[mode])do ids[#ids+1]=building.id end
 assert(json.encode(ids)==json.encode(cold[mode+1]) and json.encode(ids)==json.encode(warm[mode+1]),'Owned Places order differs in mode '..mode)
 for i,building in ipairs(info.buildings.list[mode])do
  local row=cold_rows[mode+1][i+1]
  assert(row.id==building.id and json.encode(row.position)==json.encode({building.centerx,building.centery,building.z}),'Places building identity/position mismatch')
 end
end
local result={initial_mode=info.buildings.mode,pages={},owned={cold=cold,warm=warm,menu_preserved=true},building_rows={rows=cold_rows,cold_warm_equal=true,visible_names={}}}
local function save()write('places-native.json',json.encode(result))end
for _,caption in ipairs{'Zones','Locations','Stockpiles','Workshops','Farm plots','Siege engines'}do
 local found=false
 for _,line in ipairs(lines())do
  if line.y>=4 and line.y<=12 then
   local x=line.text:find(caption,1,true)
   if x then
    g.precise_mouse_x=(x-1)*8+4;g.precise_mouse_y=line.y*12+6;g.mouse_x=x-1;g.mouse_y=line.y
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
    gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
    settle();found=true;break
   end
  end
 end
 local page={caption=caption,found=found,mode=info.buildings.mode,lines=lines(),lists={}}
 for mode=0,5 do
  local entries={};for _,building in ipairs(info.buildings.list[mode])do entries[#entries+1]={id=building.id,type=building:getType(),position={building.centerx,building.centery,building.z}}end
  page.lists[#page.lists+1]={mode=mode,entries=entries,scroll=info.buildings.scrolling_position[mode]}
 end
 result.pages[#result.pages+1]=page;save();capture('places-'..caption:lower():gsub(' ','-'))
 assert(json.encode(probe())==json.encode(cold),'Owned Places lists depend on selected tab')
 assert(found,'Native Places tab missing: '..caption)
 if page.mode>=2 then
  local mode=page.mode;local rows=cold_rows[mode+1];local checked={}
  -- Discovery oracle only: page the native list to observe every existing name.
  -- Runtime row production never reads this menu or its scroll position.
  for first=0,#rows-1,15 do
   info.buildings.scrolling_position[mode]=math.min(first,math.max(0,#rows-15));settle()
   local actual=info.buildings.scrolling_position[mode]
   for visible=0,math.min(14,#rows-actual-1)do
    local index=actual+visible+1;local name=dfhack.utf2df(rows[index].name)
    local chars={};for x=13,13+#name-1 do chars[#chars+1]=string.char(dfhack.screen.readTile(x,15+visible*3).ch)end
    if table.concat(chars)~=name then
     result.name_mismatch={caption=caption,index=index,requested_first=first,actual_first=actual,expected=rows[index].name,observed=dfhack.df2utf(table.concat(chars)),lines=lines()};save()
     error('Native Places name mismatch: '..caption..' row '..index)
    end
    checked[index]=true
   end
  end
  for i=1,#rows do assert(checked[i],'Places name was not observed: '..caption..' row '..i)end
  result.building_rows.visible_names[#result.building_rows.visible_names+1]={mode=mode,count=#rows}
  info.buildings.scrolling_position[mode]=0;settle();save()
 end
end
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Places did not close')
result.closed=true;save();records[#records+1]={name='places-discovery',pages=#result.pages,closed=true}
