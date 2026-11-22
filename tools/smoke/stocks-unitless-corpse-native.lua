-- Controlled missing-unit fixture in the paused disposable clone only.
local out,probe,run=...
local json=require('json');local corpse=assert(df.item.find(47852))
local original=corpse.unit_id
assert(df.global.pause_state and df.unit.find(original))
local frame=df.global.world.frame_counter
local function caches()
 local raw=df.creature_raw.find(corpse.race);local result={}
 local function copy(g)
  if not g then return end
  local row={cells={},icons={},templates={}}
  for _,column in ipairs(g.layer_unitless_texpos[102])do for _,cell in ipairs(column)do
   local values={};for _,value in ipairs(cell)do values[#values+1]=value end;row.cells[#row.cells+1]=values
  end end
  for _,value in ipairs(g.layer_unitless_sheet_icon_texpos[102])do row.icons[#row.icons+1]=value end
  for _,set in ipairs(g.graphics_layer_set)do row.templates[#row.templates+1]=set.layer_set_template_token end
  result[#result+1]=row
 end
 copy(raw.graphics);for _,caste in ipairs(raw.caste)do copy(caste.caste_graphics)end
 return json.encode(result)
end
local facts={item_id=corpse.id,original_unit=original,controlled_unresolved_unit=true}
return dfhack.with_finalize(function()
 corpse.unit_id=original;facts.restored=corpse.unit_id==original
 local f=assert(io.open(out..'/stocks-unitless-corpse.json','w'));f:write(json.encode(facts));f:close()
 assert(facts.restored and df.global.pause_state and df.global.world.frame_counter==frame)
end,function()
 corpse.unit_id=2147483647;assert(not df.unit.find(corpse.unit_id))
 local before=caches();probe('item-inspect-probe',tostring(corpse.id))
 facts.provider_caches_unchanged=before==caches();assert(facts.provider_caches_unchanged)
 return run()
end)
