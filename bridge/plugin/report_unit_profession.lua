-- Native Reports profession wording. Raw text wins over generic DFHack captions.
-- Evidence: fixtures/reports/unit_rows.json; e11 native profession comparisons.
return function(u)
 local U=dfhack.units
 if U.isAnimal(u)then return U.getProfessionName(u)end
 if u.custom_profession~='' then return u.custom_profession end
 local pid=U.getProfession(u)
 local full=U.getProfessionName(u)
 local base=U.getCasteProfessionName(u.race,u.caste,pid,false)
 if full~=base and full~='Agitated '..base then return full end
 if not df.profession[pid] or pid==df.profession.NONE then return ''end
 local prof,prefix='',''
 local foreign=u.race>=0 and u.race~=df.global.plotinfo.race_id
 local creature=df.creature_raw.find(u.race)
 local function age_names(child,baby)
  local text=pid==df.profession.CHILD and child[0] or pid==df.profession.BABY and baby[0] or ''
  if text~='' then foreign=false end
  return text
 end
 if creature then
  if u.caste>=0 and u.caste<#creature.caste then
   local caste=creature.caste[u.caste]
   prefix=caste.caste_name[0];prof=caste.caste_profession_name.singular[pid]
   if prof=='' then prof=age_names(caste.child_name,caste.baby_name)end
  end
  if prefix=='' then prefix=creature.name[0]end
  if prof=='' then
   prof=creature.profession_name.singular[pid]
   if prof=='' then prof=age_names(creature.general_child_name,creature.general_baby_name)end
  end
 end
 if prefix=='' then prefix='Animal'end
 if prof=='' then
  if pid==df.profession.TRAINED_WAR or pid==df.profession.TRAINED_HUNTER then
   prof=(pid==df.profession.TRAINED_WAR and 'War ' or 'Hunting ')..(foreign and prefix or 'Peasant');foreign=false
  elseif pid==df.profession.STANDARD then return full
  else
   prof=df.profession.attrs[pid].caption or df.profession[pid]
   -- DFHack's caption differs from the native Reports text for this profession.
   local native={Swordsmaster='Swordmaster',Diagnoser='Diagnostician'}
   prof=native[prof] or prof
  end
 end
 if foreign then prof=prefix..(prof~='' and ' '..prof or '')end
 if U.isAgitated(u)then prof='Agitated '..prof end
 return prof:sub(1,1):upper()..prof:sub(2)
end
