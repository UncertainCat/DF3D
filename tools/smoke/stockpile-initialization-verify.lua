-- Protected lane: commands arrive through the real Godot bridge driver.
local out,index=...
local json=require('json')
local f=assert(io.open(out..'/request-'..index..'.json','r'))
local request=json.decode(f:read('*a'));f:close()
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
