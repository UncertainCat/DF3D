-- Protected inventory only. Temporary knowledge admission is not natural gameplay evidence.
local out,records,admit_layered=...
local json=require('json')
local levels=assert(df.global.plotinfo.main.fortress_entity.training_knowledge).level
local raws=df.global.world.raws.creatures.all;local original={};local races={}
for _,level in ipairs(levels)do original[#original+1]=level end
for race,raw in ipairs(raws)do
 local trainable=false
 for _,caste in ipairs(raw.caste)do if caste.flags.PET or caste.flags.PET_EXOTIC then trainable=true;break end end
 if trainable or (original[race+1] or 0)~=0 then races[#races+1]=race end
end
local function caches()
 local result={}
 for _,race in ipairs(races)do
  local raw=raws[race];local values={}
  local function capture(graphics)
   if not graphics then return end
   local entry={cells={},icons={},templates={}}
   for _,column in ipairs(graphics.layer_unitless_texpos[102])do for _,cell in ipairs(column)do
    local list={};for _,tile in ipairs(cell)do list[#list+1]=tile end;entry.cells[#entry.cells+1]=list
   end end
   for _,tile in ipairs(graphics.layer_unitless_sheet_icon_texpos[102])do entry.icons[#entry.icons+1]=tile end
   for _,set in ipairs(graphics.graphics_layer_set)do entry.templates[#entry.templates+1]=set.layer_set_template_token end
   values[#values+1]=entry
  end
  capture(raw.graphics);for _,caste in ipairs(raw.caste)do capture(caste.caste_graphics)end
  result[tostring(race)]=values
 end
 return json.encode(result)
end
local before=caches();local result={original_entries=#original,candidate_species=#races,raws=#raws}
local ok,err=xpcall(function()
 levels:resize(#raws)
 for race=0,#raws-1 do levels[race]=0 end
 for _,race in ipairs(races)do levels[race]=math.max(1,original[race+1] or 0)end
 local text,rc=dfhack.run_command_silent('df3d','pet-training-probe','art');assert(rc==0,text)
 result.rows=json.decode(text).rows;assert(#result.rows==#races)
 local original_tiles={}
 for _,page in ipairs(df.global.texture.page)do for _,tile in ipairs(page.texpos)do if tile>0 then original_tiles[tile]=true end end end
 result.original_tiles=0;result.layered=0;result.unresolved={}
 for _,row in ipairs(result.rows)do
  row.raw_id=raws[row.race].creature_id
  if row.layered_fallback and row.layered_resolved then result.layered=result.layered+1
  elseif row.art_tile and original_tiles[row.art_tile] then result.original_tiles=result.original_tiles+1
  else result.unresolved[#result.unresolved+1]=row end
 end
 result.caches_unchanged=caches()==before;assert(result.caches_unchanged,'Species audit changed graphics cache/template metadata')
end,debug.traceback)
levels:resize(#original);for i,level in ipairs(original)do levels[i-1]=level end
result.knowledge_restored=#levels==#original
for i,level in ipairs(original)do result.knowledge_restored=result.knowledge_restored and levels[i-1]==level end
assert(result.knowledge_restored,'Species audit failed to restore knowledge')
result.success=ok;result.error=ok and nil or err
local f=assert(io.open(out..'/species-art-audit.json','w'));f:write(json.encode(result));f:close()
assert(ok,err)
records[#records+1]={name='species-art-audit',species=#races,unresolved=#result.unresolved,knowledge_restored=true,caches_unchanged=true}

if admit_layered then
 levels:resize(#raws);for race=0,#raws-1 do levels[race]=0 end
 local admitted={}
 for _,row in ipairs(result.rows)do if row.layered_fallback and row.layered_resolved then levels[row.race]=row.level;admitted[#admitted+1]=row.raw_id end end
 return function()
  levels:resize(#original);for i,level in ipairs(original)do levels[i-1]=level end
  for i,level in ipairs(original)do assert(levels[i-1]==level)end
  local f=assert(io.open(out..'/species-layered-restored.json','w'));f:write(json.encode{species=admitted,restored=true});f:close()
 end
end
