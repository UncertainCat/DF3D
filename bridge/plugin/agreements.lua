-- Read-only agreement browser. Native unapproved IDs identify pending decisions.
-- Cached main_interface.petitions rows are deliberately never consulted.
local scan
local function cut(s,limit)
 if #s<=limit then return s,true end
 local n=limit
 while n>0 and s:byte(n+1)>=128 and s:byte(n+1)<192 do n=n-1 end
 return s:sub(1,n),false
end
local function membership(v)
 if #v>4096 then return nil end
 local out={};for i=0,#v-1 do out[v[i]]=true end;return out
end
local function name(obj)
 if not obj then return 'Unavailable identity' end
 return dfhack.translation.translateName(obj.name,true)
end
local function row(agr,pending,continuing,site)
 local v={id=agr.id,not_approved=agr.flags.petition_not_accepted,concluded=agr.flags.convicted_accepted,
 continuing=continuing[agr.id] or false,complete=true,details={},parties={},reason=''}
 v.status=pending[agr.id] and 0 or (v.concluded and 3 or (v.not_approved and 2 or 1))
 local omitted_terms=false
 local relevant=pending[agr.id] or continuing[agr.id] or false
 local function text(s)
  local result,ok=cut(dfhack.df2utf(s:sub(1,2048)),2048)
  ok=ok and #s<=2048
  if not ok then v.complete=false end
  return result
 end
 if #agr.details>8 or #agr.parties>8 then v.complete=false end
 for i=0,math.min(#agr.details,8)-1 do
  local d=agr.details[i]
  local n={id=d.id,kind=d.type,site_id=-1,year=d.year,year_tick=d.year_tick,
   applicant_party=-1,government_party=-1,location_type=-1,tier=-1,profession=-1,deity_type=-1,deity_id=-1}
  local kind=df.agreement_details_type[d.type] or 'Unknown'
  n.description=kind
  if kind~='Location' then v.complete=false;omitted_terms=true end
  -- Never dereference a union arm before checking its discriminator.
  if kind=='Location' or kind=='Residency' or kind=='Citizenship' or kind=='Parley' then
   local data=d.data[kind]
   if data then
    n.site_id=data.site;n.applicant_party=kind=='Parley' and data.asker or data.applicant
    n.government_party=kind=='Parley' and data.target or data.government
    if data.site==site then relevant=true end
    if kind=='Location' then
     n.location_type=data.type;n.tier=data.tier;n.profession=data.profession
     n.deity_type=data.deity_type;n.deity_id=data.deity_data.practice_id
     local typ=df.abstract_building_type[data.type] or 'Unknown location'
     n.description=typ..' tier '..tostring(data.tier)
     if typ=='GUILDHALL' then n.description=n.description..' for '..(df.profession[data.profession] or 'unknown profession') end
     if typ=='TEMPLE' then
      local practice=df.religious_practice_type[data.deity_type]
      local target
      if practice=='WORSHIP_HFID' then target=df.historical_figure.find(n.deity_id)
      elseif practice=='RELIGION_ENID' then target=df.historical_entity.find(n.deity_id)
      else v.complete=false end
      n.description=n.description..' / '..(target and name(target) or 'Unknown religious practice')
     end
    end
   else v.complete=false end
  end
  n.description=text(n.description);v.details[#v.details+1]=n
 end
 if not relevant then return nil end
 local names_left=8
 local function member_name(obj)
  if names_left<=0 then v.complete=false;return nil end
  names_left=names_left-1
  local raw=name(obj)
  if #raw>256 then v.complete=false;raw=raw:sub(1,256) end
  return raw
 end
 for i=0,math.min(#agr.parties,8)-1 do
  local p=agr.parties[i];local n={id=p.id,entity_ids={},histfig_ids={},name=''};local names={}
  if #p.entity_ids>32 or #p.histfig_ids>32 then v.complete=false end
  for j=0,math.min(#p.entity_ids,32)-1 do
   local id=p.entity_ids[j];n.entity_ids[#n.entity_ids+1]=id
   if names_left>0 then names[#names+1]=member_name(df.historical_entity.find(id)) else v.complete=false end
  end
  for j=0,math.min(#p.histfig_ids,32)-1 do
   local id=p.histfig_ids[j];n.histfig_ids[#n.histfig_ids+1]=id
   if names_left>0 then names[#names+1]=member_name(df.historical_figure.find(id)) else v.complete=false end
  end
  n.name=text(table.concat(names,', '));v.parties[#v.parties+1]=n
 end
 -- Summary is already UTF-8; do not convert it a second time.
 v.summary=v.details[1] and v.details[1].description or 'Agreement without details'
 if omitted_terms then v.reason='Partial record: some native subject terms are not yet displayed'
 elseif not v.complete then v.reason='Partial record: native data, names or text are unavailable or exceed display limits' end
 if v.status==0 then v.reason=v.reason..(v.reason~='' and '; ' or '')..'Pending native petition; response controls are not yet verified' end
 return v
end
return function(request)
 local a=request.agreement;local p=df.global.plotinfo
 local pending,continuing=membership(p.petitions),membership(p.continuing_agreement_id)
 if not pending or not continuing then return {ok=false,message='Agreement membership exceeds supported limit'} end
 local function result(rows,cursor)
  return {ok=true,message='Native agreements',agreements=rows,next_before_id=cursor,pending_only=a.pending_only,
   detail='Pending means a native unapproved petition. Accepted and concluded are native states; no denial or expiry is inferred.'}
 end
 if request.action==37 then
  local agr=df.agreement.find(a.id);local value=agr and row(agr,pending,continuing,p.site_id)
  if not value then return {ok=false,message='Agreement is unavailable or unrelated to this fortress'} end
  return result({value},-1)
 end
 local source=df.global.world.agreements.all
 if not scan or scan.seq~=request.seq then scan={seq=request.seq,before=a.before_id,rows={},bytes=0,query=a.query:lower()} end
 local lo,hi=0,#source
 if scan.before>=0 then
  while lo<hi do local mid=(lo+hi)//2;if source[mid].id<scan.before then lo=mid+1 else hi=mid end end
 else lo=#source end
 local index=lo-1;local inspected=0
 -- Full decoding is independently bounded: at most16 records and128 member names/update.
 while index>=0 and inspected<16 do
  local agr=source[index];local value
  if not a.pending_only or pending[agr.id] then value=row(agr,pending,continuing,p.site_id) end
  if value then
   local search=value.summary
   for _,party in ipairs(value.parties)do search=search..' '..party.name end
   for _,detail in ipairs(value.details)do search=search..' '..detail.description end
   if scan.query=='' or tostring(value.id)==scan.query or search:lower():find(scan.query,1,true) then
    local bytes=#search+#value.reason
    if #scan.rows>=16 or scan.bytes+bytes>120000 then local out=result(scan.rows,scan.before);scan=nil;return out end
    scan.rows[#scan.rows+1]=value;scan.bytes=scan.bytes+bytes
   end
  end
  scan.before=agr.id;index=index-1;inspected=inspected+1
 end
 if index>=0 and #scan.rows>=16 then local out=result(scan.rows,scan.before);scan=nil;return out end
 if index>=0 then return {ok=true,pending=true,message='Searching native agreements'} end
 local out=result(scan.rows,-1);scan=nil;return out
end
