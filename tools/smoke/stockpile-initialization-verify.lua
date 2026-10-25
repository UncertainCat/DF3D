-- Protected lane: commands arrive through the real Godot bridge driver.
local out,index=...
local json=require('json')
local f=assert(io.open(out..'/request-'..index..'.json','r'))
local request=json.decode(f:read('*a'));f:close()
if request.op:match('^quality_') or request.op:match('^filter_') then
 assert(df.global.pause_state,'quality observation requires pause')
 local b=assert(df.building.find(request.id))
 if request.op=='filter_setup' then
  local category,field=request.field:match('^([^%.]+)%.(.+)$')
  b.settings[category][field]:resize(request.count)
  for i=0,request.count-1 do b.settings[category][field][i]=0 end
  f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode{status='passed'});f:close()
  print('SEMANTIC_PASS filter_setup');return
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
