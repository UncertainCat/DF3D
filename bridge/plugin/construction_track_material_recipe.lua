-- Partial Track recipe suitability, separate from flags/position/containment.
-- DF53.16 flags2=0x2840, native a28884 (isBuildMat) and a28972 (economic stone).
-- Native live evidence: material_candidates.json recipe_capture. Input facts
-- must come from item methods/material identities and plotinfo stone policy.
return function(facts)
    if type(facts)~='table' or type(facts.is_build_mat)~='boolean' then return nil end
    if not facts.is_build_mat then return false end
    if type(facts.type)~='string' or facts.type=='' then return nil end
    if facts.type~='BOULDER' then return true end
    if math.type(facts.material_type)~='integer' or math.type(facts.material_index)~='integer' then return nil end
    if facts.material_type~=0 or facts.material_index<0 then return true end
    if type(facts.economic_restricted)~='boolean' then return nil end
    return not facts.economic_restricted
end
