-- Controlled semantic claim inputs in the owned paused clone. Native rendering
-- is the oracle; restore every vector and scalar before returning.
local out,view,probe,settle=...
local json=require('json')
local plot,world=df.global.plotinfo,df.global.world
local menu=df.global.game.main_interface.info.artifacts
menu.mode=0;menu.scroll_position[0]=0;settle()
local artifact,row_index
for _,destination in ipairs(probe('objects-destinations-probe')[1])do
 if destination.available then
  for index,value in ipairs(menu.list[0])do if value.id==destination.artifact_id then artifact=value;row_index=index;break end end
  if artifact then break end
 end
end
assert(artifact and row_index<16,'Claims fixture needs visible local artifact')
local id=artifact.id
local fortress=assert(plot.main.fortress_entity)
local civ=assert(df.historical_entity.find(plot.civ_id))
assert(civ~=fortress,'Claims fixture needs distinct fortress and civilization')
local backups,seen={},{}
local function save(vector,key)
 local _,address=df.sizeof(vector)
 if seen[address]then return end;seen[address]=true
 local old,clean={},{}
 for _,claim in ipairs(vector)do old[#old+1]=claim;if claim[key]~=id then clean[#clean+1]=claim end end
 backups[#backups+1]={vector=vector,old=old,clean=clean}
end
save(fortress.artifact_claims,'artifact_id');save(civ.artifact_claims,'artifact_id')
local figure,family
for _,resident in ipairs(fortress.nemesis)do
 local hf=resident.figure
 if hf and hf.info and hf.info.relationships then
  save(hf.info.relationships.artifact_claims,'artifact_id')
  for _,candidate in ipairs(world.family_info.family)do
   if candidate.hfid==hf.family_head_id then
    save(candidate.claims,'artifact')
    if not figure then figure=hf;family=candidate end
   end
  end
 end
end
assert(figure and family,'Claims fixture needs resident with family')
local function replace(vector,values)vector:resize(0);for _,value in ipairs(values)do vector:insert('#',value)end end
local function add(vector,claim,key)
 local index=0;while index<#vector and vector[index][key]<id do index=index+1 end
 vector:insert(index,claim)
end
local fort_claim=df.artifact_claim:new();fort_claim.artifact_id=id;fort_claim.renounce_event=-1;fort_claim.symbol_claim_id=-1
local civ_claim=df.artifact_claim:new();civ_claim.artifact_id=id;civ_claim.renounce_event=-1;civ_claim.symbol_claim_id=-1
local personal=df.relationship_profile_artifactst:new();personal.artifact_id=id;personal.renounce_event=-1
local inherited=df.family_artifact_claimst:new();inherited.artifact=id;inherited.renounced_heid=-1
local king=plot.king_arrived
local samples={}
local function reset()
 for _,backup in ipairs(backups)do replace(backup.vector,backup.clean)end
 plot.king_arrived=false
 fort_claim.renounce_event=-1;civ_claim.renounce_event=-1;personal.renounce_event=-1;inherited.renounced_heid=-1
end
local function observe(name)
 settle()
 local supplied
 for _,row in ipairs(probe('objects-ownership-probe')[1])do if row.artifact_id==id then supplied=row.ownership;break end end
 assert(supplied~=nil,'Controlled artifact missing from provider')
 local chars={}
 for x=74,137 do local ch=dfhack.screen.readTile(x,13+row_index*3).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 local native=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
 samples[#samples+1]={name=name,provider=supplied,native=native}
 local f=assert(io.open(out..'/objects-claims.json','w'));f:write(json.encode{artifact_id=id,figure_id=figure.id,family_id=family.hfid,cases=samples});f:close()
 assert(native==supplied,'Objects claim differs for '..name..': '..native..' / '..supplied)
end
local ok,err=xpcall(function()
 reset();observe('unclaimed')
 for kind=0,3 do
  reset();fort_claim.claim_type=kind;add(fortress.artifact_claims,fort_claim,'artifact_id');observe('fortress-'..kind)
  fort_claim.renounce_event=0;observe('fortress-renounced-'..kind)
  reset();civ_claim.claim_type=kind;add(civ.artifact_claims,civ_claim,'artifact_id');observe('civilization-before-king-'..kind)
  plot.king_arrived=true;observe('civilization-after-king-'..kind)
 end
 for kind=1,2 do
  reset();personal.type=kind;add(figure.info.relationships.artifact_claims,personal,'artifact_id');observe('personal-'..kind)
  personal.renounce_event=0;observe('personal-renounced-'..kind)
  reset();inherited.type=kind;add(family.claims,inherited,'artifact');observe('family-'..kind)
  inherited.renounced_heid=0;observe('family-renounced-'..kind)
 end
 reset();plot.king_arrived=true
 fort_claim.claim_type=2;civ_claim.claim_type=3;personal.type=1;inherited.type=2
 add(fortress.artifact_claims,fort_claim,'artifact_id');add(civ.artifact_claims,civ_claim,'artifact_id')
 add(figure.info.relationships.artifact_claims,personal,'artifact_id');add(family.claims,inherited,'artifact')
 observe('fortress-precedence');fort_claim.renounce_event=0;observe('civilization-precedence')
 civ_claim.renounce_event=0;observe('personal-precedence');personal.renounce_event=0;observe('family-fallback')
end,debug.traceback)
for _,backup in ipairs(backups)do replace(backup.vector,backup.old)end
plot.king_arrived=king
fort_claim:delete();civ_claim:delete();personal:delete();inherited:delete()
settle();assert(ok,err)
