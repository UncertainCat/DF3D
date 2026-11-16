-- Diagnostic only: controlled semantic flags/references in an unsaved paused lane.
local trade,record=...
local own=assert(trade.good[1][0]);local merchant=assert(trade.good[0][0])
local originals={own.flags.whole,merchant.flags.whole};local refs={};local mandates={};local labels={}
local function add_ref(kind)
 local ref=df[kind]:new();ref.entity_id=df.global.plotinfo.main.fortress_entity.id
 own.general_refs:insert('#',ref);refs[#refs+1]=ref;return ref
end
local function remove_ref(ref)
 for i,value in ipairs(own.general_refs)do if value==ref then own.general_refs:erase(i);break end end
 for i,value in ipairs(refs)do if value==ref then table.remove(refs,i);break end end
 ref:delete()
end
local function ban(item)
 local value=df.mandate:new();value.mode=0;value.item_type=item:getType();value.item_subtype=-1;value.mat_type=-1;value.mat_index=-1;value.timeout_limit=1200
 df.global.world.mandates.all:insert('#',value);mandates[#mandates+1]=value
end
local function capture(label,expected)
 local row=record('row-facts-'..label);local found
 for _,item in ipairs(row.projection_provider.display[2].rows)do if item.id==own.id then found=item;break end end
 assert(found and found.disposition==expected,'Unexpected owned disposition: '..label)
 labels[#labels+1]={label=label,id=own.id,disposition=found.disposition}
end
local ok,err=xpcall(function()
 own.flags.foreign=false;capture('local',0)
 own.flags.foreign=true;capture('imported',1)
 ban(own);capture('restricted',2)
 local stolen=add_ref('general_ref_entity_stolenst');capture('stolen-over-restricted',3)
 local offered=add_ref('general_ref_entity_offeredst');capture('offered-over-stolen',4)
 remove_ref(offered);capture('stolen-restored',3)
 remove_ref(stolen);capture('restriction-restored',2)
 ban(merchant);merchant.flags.foreign=false
 local row=record('row-facts-merchant-ban')
 for _,item in ipairs(row.projection_provider.display[1].rows)do if item.id==merchant.id then assert(item.disposition==0,'Merchant side incorrectly applies export restriction')end end
end,debug.traceback)
for i=#refs,1,-1 do remove_ref(refs[i])end
for _,value in ipairs(mandates)do
 for i,actual in ipairs(df.global.world.mandates.all)do if actual==value then df.global.world.mandates.all:erase(i);break end end
 value:delete()
end
own.flags.whole=originals[1];merchant.flags.whole=originals[2]
if not ok then error(err)end
return {cases=labels,merchant_export_ignored=true,restored=true}
