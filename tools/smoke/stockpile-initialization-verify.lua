-- Protected lane: commands arrive through the real Godot bridge driver.
local out,index=...
local json=require('json')
local function restore_historical()
 local h=_G.df3d_historical_fixture
 if not h then return end
 h.types:resize(h.type_count);h.indexes:resize(h.index_count)
 if h.type_count>0 then h.types[0]=h.old_type end
 if h.index_count>0 then h.indexes[0]=h.old_index end
 h.values:resize(#h.saved);for i,v in ipairs(h.saved)do h.values[i-1]=v end
 _G.df3d_historical_fixture=nil
end
if index=='historical_final' then restore_historical();print('SEMANTIC_PASS historical_final');return end
local f=assert(io.open(out..'/request-'..index..'.json','r'))
local request=json.decode(f:read('*a'));f:close()
if request.op=='historical_setup' or request.op=='historical_restore' then
 assert(df.global.pause_state)
 if request.op=='historical_restore' then restore_historical()
 else
  assert(not _G.df3d_historical_fixture,'historical fixture already active')
  local mapping={[2]=0,[6]=4,[7]=5,[8]=6,[9]=7,[10]=8,[11]=9,[12]=10,[13]=11,[14]=12,[15]=13,[16]=33,[17]=34,[18]=14,[19]=15,[20]=16,[73]=17,[76]=18,[77]=19,[78]=35,[79]=36,[80]=18,[81]=19,[82]=35,[83]=36,[107]=37,[108]=38}
  local slot=assert(mapping[request.mode]);local b=assert(df.building.find(request.id))
  local cat,field=request.field:match('^([^%.]+)%.(.+)$');local values=b.settings[cat][field]
  local types,indexes=df.global.world.raws.mat_table.organic_types[slot],df.global.world.raws.mat_table.organic_indexes[slot]
  local figure
  for i=#df.global.world.history.figures-1,0,-1 do local h=df.global.world.history.figures[i];if h.race>=0 and h.race<#df.global.world.raws.creatures.all then figure=h;break end end
  assert(figure)
  local saved={};for _,v in ipairs(values)do saved[#saved+1]=v end
  _G.df3d_historical_fixture={types=types,indexes=indexes,type_count=#types,index_count=#indexes,old_type=#types>0 and types[0],old_index=#indexes>0 and indexes[0],values=values,saved=saved}
  types:resize(math.max(1,#types));indexes:resize(math.max(1,#indexes));types[0]=222;indexes[0]=figure.id
  values:resize(1);values[0]=1
 end
 f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode{status='passed'});f:close()
 print('SEMANTIC_PASS '..request.op);return
end
if request.op=='summary_before' or request.op=='summary_rows'then
 assert(df.global.pause_state)
 local b=assert(df.building.find(request.id));assert(df.building_stockpilest:is_instance(b))
 local function snapshot(v)
  if type(v)~='userdata'then return tostring(v)end
  local parts={};for k,x in pairs(v)do if type(x)~='function' and tostring(k):sub(1,1)~='_'then parts[#parts+1]=tostring(k)..'='..snapshot(x)end end
  table.sort(parts);return '{'..table.concat(parts,';')..'}'
 end
 if request.op=='summary_before'then _G.df3d_summary_before=snapshot(b.settings)
 else
  assert(_G.df3d_summary_before==snapshot(b.settings),'summary read changed settings');_G.df3d_summary_before=nil
  local categories={'animals','food','furniture','corpses','refuse','stone','ammo','coins','bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
  local indexes={};local mask=b.settings.flags.whole & 0x1ffff
  for i,key in ipairs(categories)do indexes[key]=i;if key==request.list_key then mask=mask | (1 << (i-1))end end
  local text,code=dfhack.run_command_silent('df3d','stockpile-summary-read',tostring(b.id),tostring(mask));assert(code==0,text)
  local expected=json.decode(text);local state={[0]=1,[1]=3,[2]=2}
  local modes={['food/meat']=2,['food/fish']=3,['food/unprepared_fish']=4,['food/egg']=5,['food/plants']=6,['food/drink_plant']=7,['food/drink_animal']=8,['food/cheese_plant']=9,['food/cheese_animal']=10,['food/seeds']=11,['food/leaves']=12,['food/powder_plant']=13,['food/powder_creature']=14,['food/glob']=15,['food/glob_paste']=16,['food/glob_pressed']=17,['food/liquid_plant']=18,['food/liquid_animal']=19,['food/liquid_misc']=20,['leather/type']=73,['cloth/thread_silk']=76,['cloth/thread_plant']=77,['cloth/thread_yarn']=78,['cloth/thread_metal']=79,['cloth/cloth_silk']=80,['cloth/cloth_plant']=81,['cloth/cloth_yarn']=82,['cloth/cloth_metal']=83,['sheet/paper']=107,['sheet/parchment']=108,['stone/metal_ores']=40,['stone/economic']=41,['stone/other_stone']=42,['stone/clay']=43,['gems/rough_glass']=58,['gems/cut_glass']=59,['gems/rough_gem']=60,['gems/cut_gem']=61,['gems/cut_stone']=62,['furniture/stone']=23,['furniture/metal']=24,['ammo/metal']=47,['coins']=50,['bars_blocks/bars_metal']=52,['bars_blocks/blocks_stone']=54,['bars_blocks/blocks_metal']=55,['finished_goods/stone']=65,['finished_goods/metal']=66,['finished_goods/gem']=67,['weapons/metal']=89,['weapons/stone']=90,['armor/metal']=101,['furniture/type']=22,['refuse/type']=30,['finished_goods/type']=64,['wood']=85,['animals/animals']=0,['corpses']=28,['refuse/corpses']=31,['refuse/body_parts']=32,['refuse/skulls']=33,['refuse/bones']=34,['refuse/shells']=35,['refuse/teeth']=36,['refuse/horns']=37,['refuse/hair']=38,['furniture/quality_core']=26,['furniture/quality_total']=27,['ammo/quality_core']=48,['ammo/quality_total']=49,['finished_goods/quality_core']=69,['finished_goods/quality_total']=70,['weapons/quality_core']=92,['weapons/quality_total']=93,['armor/quality_core']=103,['armor/quality_total']=104,['furniture/other_materials']=25,['ammo/other_materials']=46,['bars_blocks/bars_other']=53,['bars_blocks/blocks_other']=56,['finished_goods/other_materials']=68,['weapons/other_materials']=91,['armor/other_materials']=102,['ammo/type']=45,['weapons/weapons']=87,['weapons/trap_components']=88,['armor/body']=95,['armor/head']=96,['armor/feet']=97,['armor/hands']=98,['armor/legs']=99,['armor/shield']=100,['finished_goods/color']=71,['leather/color']=74,['cloth/color']=84,['armor/color']=105}
  local seen={}
  for _,row in ipairs(request.rows)do
   assert(not seen[row.key],'duplicate summary key');seen[row.key]=true
   local value
   if row.kind==1 then value=state[expected.categories[assert(indexes[row.key])]]
   elseif row.kind==2 then value=state[expected.states[assert(modes[row.key])+1]]
   else
    local cat,field=row.key:match('^([^/]+)/(.+)$')
    if not cat then cat='misc';field=row.key=='organic' and 'allow_organic' or 'allow_inorganic'end
    value=b.settings[cat][field] and 2 or 1
   end
   assert(row.state==value and not row.estimated,'native summary differs '..row.key)
  end
  if request.list_key==''then
   assert(#request.rows==19,'root summary count')
   for _,key in ipairs(categories)do assert(seen[key],'missing root category')end
   assert(seen.organic and seen.inorganic,'missing allowances')
  elseif request.list_key=='food'then
   assert((seen['food/cheese_plant'] or false)==(#b.settings.food.cheese_plant>0),'plant cheese visibility')
   assert((seen['food/powder_creature'] or false)==(#b.settings.food.powder_creature>0),'animal powder visibility')
   assert(#request.rows==18+(seen['food/cheese_plant'] and 1 or 0)+(seen['food/powder_creature'] and 1 or 0),'Food summary count')
  end
 end
 local response=assert(io.open(out..'/response-'..index..'.json','w'));response:write(json.encode{status='passed'});response:close()
 print('SEMANTIC_PASS '..request.op);return
end
if request.op:match('^quality_') or request.op:match('^filter_') then
 assert(df.global.pause_state,'quality observation requires pause')
 local b=assert(df.building.find(request.id))
 if request.op=='filter_setup' or request.op=='filter_restore' then
  local category,field=request.field:match('^([^%.]+)%.(.+)$')
  local values=b.settings[category][field]
  if request.op=='filter_restore' then
   local saved=assert(_G.df3d_filter_saved,'missing filter fixture')
   assert(saved.id==request.id and saved.field==request.field,'wrong filter fixture')
   values:resize(#saved.values);for i,v in ipairs(saved.values)do values[i-1]=v end
   _G.df3d_filter_saved=nil
  else
   if not _G.df3d_filter_saved then
    local original={};for _,v in ipairs(values)do original[#original+1]=v end
    _G.df3d_filter_saved={id=request.id,field=request.field,values=original}
   end
   assert(_G.df3d_filter_saved.id==request.id and _G.df3d_filter_saved.field==request.field,'unrestored filter fixture')
   values:resize(request.count)
   for i=0,request.count-1 do values[i]=0 end
  end
  f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode{status='passed'});f:close()
  print('SEMANTIC_PASS '..request.op);return
 end
 local function snapshot(v)
  if type(v)~='userdata' then return v end
  local parts={}
  for k,x in pairs(v)do
   if type(x)~='function' and tostring(k):sub(1,1)~='_' then
    parts[#parts+1]=tostring(k)..'='..tostring(snapshot(x))
   end
  end
  table.sort(parts);return '{'..table.concat(parts,';')..'}'
 end
 local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(request.mode),request.query or '')
 assert(code==0,text);local rows=json.decode(text)
 if request.op=='quality_rows' or request.op=='filter_rows' then
  local visible={};for _,row in ipairs(rows)do if row.visible then visible[#visible+1]=row end end
  assert(#visible==#request.rows,'quality visible count')
  for i,row in ipairs(visible)do
   local actual=request.rows[i]
   assert(actual.index==row.index and actual.label==row.name and actual.state==(row.enabled and 2 or 1),'bridge quality row '..i)
   local suffix=row.field:match('^refuse%.(.*raw_hide)$')
   assert(actual.key==request.list_key..'/'..(suffix or row.index),'bridge quality identity')
  end
 elseif request.op=='quality_before' or request.op=='filter_before' then
  -- Build an independent expected settings snapshot, then restore before the
  -- bridge mutation. The oracle never supplies settings to the product.
  local original={}
  for _,row in ipairs(rows)do
   local category,field=row.field:match('^([^%.]+)%.(.+)$')
   local values=b.settings[category][field]
   local scalar=type(values)=='boolean'
   local value=scalar and values or not scalar and values[row.index]
   original[#original+1]={category=category,field=field,index=row.index,scalar=scalar,value=value}
   if row.visible and (request.row==nil or row.index==request.row and row.field==request.field) then
    if scalar then b.settings[category][field]=request.value==2
    elseif type(value)=='boolean' then values[row.index]=request.value==2
    else values[row.index]=request.value==2 and 1 or 0 end
   end
  end
  _G.df3d_quality_expected=snapshot(b.settings)
  for _,v in ipairs(original)do
   if v.scalar then b.settings[v.category][v.field]=v.value
   else b.settings[v.category][v.field][v.index]=v.value end
  end
 elseif request.op=='quality_after' or request.op=='filter_after' then
  assert(_G.df3d_quality_expected==snapshot(b.settings),'filtered edit changed unexpected settings')
  _G.df3d_quality_expected=nil
 else error('unknown quality operation')end
 f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode{status='passed'});f:close()
 print('SEMANTIC_PASS '..request.op..' '..request.mode);return
end
if request.op~='stockpile_initialization' then
 local script=debug.getinfo(1,'S').source:sub(2)
 local directory=assert(script:match('^(.*[/\\])'))
 return assert(loadfile(directory..'areas-acceptance-verify.lua'))(out,index)
end
assert(df.global.pause_state,'initialization observation requires pause')
local b=assert(df.building.find(request.id))
assert(df.building_stockpilest:is_instance(b))
assert(b.settings.misc.allow_organic and b.settings.misc.allow_inorganic,'constructor allowances missing')
assert(b.storage.max_barrels==0 and b.storage.max_bins==0 and b.storage.max_wheelbarrows==0,'unexpected creation containers')
local categories={'animals','food','furniture','corpses','refuse','stone','ammo','coins',
 'bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
for bit,key in ipairs(categories)do
 assert(b.settings.flags[key]==((request.categories & (1 << (bit-1)))~=0),'category '..key)
end
-- Each single-category initializer must agree with the preset service already
-- compared against native icon clicks. Compare every vector and fixed field.
local preset=request.categories==0 and 19 or nil
for bit=0,16 do if request.categories==(1 << bit)then preset=bit+2 end end
local comparisons={}
if preset then comparisons[1]={preset=preset}
else
 for bit,key in ipairs(categories)do
  if (request.categories & (1 << (bit-1)))~=0 then comparisons[#comparisons+1]={preset=bit+1,category=key}end
 end
end
for _,comparison in ipairs(comparisons)do
 local text,code=dfhack.run_command_silent('df3d','stockpile-preset-read',tostring(b.id),tostring(comparison.preset))
 assert(code==0,text);local expected=json.decode(text)
 if not comparison.category then assert(b.settings.flags.whole==expected.flags,'native preset flags differ')end
 for kind,fields in pairs{vectors=expected.vectors,fixed=expected.fixed}do
  for key,values in pairs(fields)do
   local cat,name=key:match('^([^%.]+)%.(.+)$');local actual=b.settings[cat][name]
   if not comparison.category or comparison.category==cat then
    if kind=='vectors' then assert(#actual==#values,key..' length') end
    if kind=='fixed' and #values==1 then assert(actual==values[1],key)
    else for i,value in ipairs(values)do assert(actual[i-1]==value,key..' value '..i)end end
   end
  end
 end
end
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode{status='passed'});f:close()
print('SEMANTIC_PASS initialization '..request.categories)
