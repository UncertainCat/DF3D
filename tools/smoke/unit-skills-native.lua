-- Read native Skills presentation in the owned paused unsaved diagnostic.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local function row(y)
 local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256)or' 'end
 return table.concat(text)
end
local function click(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function select(name,first,last)
 for y=first,last do local x=row(y):find(name,1,true);if x then click((x-1)*8+4,y*12+10);return end end
 error('Missing native Skills tab '..name)
end
local pages={}
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected creature sheet')
 select('Skills',15,16)
 for _,name in ipairs{'Labor','Combat','Social','Other skills','Knowledge'}do
  select(name,17,20)
  local page={name=name,tab=sheet.unit_skill_active_tab,first=sheet.scroll_position_unit_skill,skills={},values={},rust_values={},lines={}}
  for _,v in ipairs(sheet.unit_skill)do page.skills[#page.skills+1]=v end
  for _,v in ipairs(sheet.unit_skill_val)do page.values[#page.values+1]=v end
  for _,v in ipairs(sheet.unit_skill_val_w_rust)do page.rust_values[#page.rust_values+1]=v end
  page.knowledge_types={};page.knowledge_ids={};page.knowledge_bits={}
  for _,v in ipairs(sheet.unit_knowledge_type)do page.knowledge_types[#page.knowledge_types+1]=v end
  for _,v in ipairs(sheet.unit_knowledge_id)do page.knowledge_ids[#page.knowledge_ids+1]=v end
  for _,v in ipairs(sheet.unit_knowledge_bits)do page.knowledge_bits[#page.knowledge_bits+1]=v end
  if os.getenv('DF3D_UNIT_SKILLS_PROBE')=='1'then
   local guards={}
   local function guard(address,size)
    if size==0 then return end;assert(size>0 and size<1048576)
    local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
    guards[#guards+1]={bytes=bytes,address=address,size=size}
   end
   local function object(value)if value then local size,address=df.sizeof(value);guard(address,size)end end
   local function vector(value)
    local _,address=df.sizeof(value);local first=df.reinterpret_cast('uint64_t',address).value
    guard(first,df.reinterpret_cast('uint64_t',address+8).value-first)
   end
   local original_cache=unit.enemy.histfig_vector_idx;unit.enemy.histfig_vector_idx=-1
   object(unit);object(sheet);object(df.global.plotinfo)
   local soul=unit.status.current_soul;object(soul)
   if soul then vector(soul.skills);for _,skill in ipairs(soul.skills)do object(skill)end end
   local hf=df.historical_figure.find(unit.hist_figure_id);object(hf)
   if hf then object(hf.info);if hf.info then
    local known=hf.info.known_info;object(known)
    if known then object(known.knowledge);for _,field in ipairs{'known_poetic_forms','known_musical_forms','known_dance_forms','known_written_contents'}do vector(known[field])end end
   end end
   for _,field in ipairs{'unit_skill','unit_skill_val','unit_skill_val_w_rust','unit_knowledge_type','unit_knowledge_id','unit_knowledge_bits'}do vector(sheet[field])end
   local base=dfhack.internal.getImageBase()
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
   local text,status=dfhack.run_command_silent('df3d','unit-skills-page-probe',tostring(unit.id),tostring(page.tab))
   local unchanged=true
   for _,g in ipairs(guards)do if dfhack.internal.memcmp(g.bytes,g.address,g.size)~=0 then unchanged=false end;df.delete(g.bytes)end
   unit.enemy.histfig_vector_idx=original_cache
   assert(status==0,text);assert(unchanged,'Skills probe changed source/UI/random state')
   page.probe=json.decode(text);page.probe_guards_unchanged=true;page.cold_source_cache_preserved=true
   for _,field in ipairs{'skills','values','rust_values','knowledge_types','knowledge_ids','knowledge_bits'}do assert(json.encode(page[field])==json.encode(page.probe[field]),'Skills probe differs: '..name..' '..field)end
  end
  for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
  pages[#pages+1]=page;capture('unit-skills-'..name:lower():gsub(' ','-'))
 end
end,debug.traceback)
select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Skills reference advanced simulation')
local result={success=ok,unit_id=unit.id,pages=pages,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-skills-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
