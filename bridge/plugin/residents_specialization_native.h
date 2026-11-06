#pragma once
#include "residents_order_native.h"
#include "location_staff_mutation_native.h"

namespace df3d_residents {
struct Specialization { bool onlyAssigned=false;uint64_t revision=0; };
enum class SpecializationOutcome { Applied, Rejected, Stale, Unavailable, Unknown };
inline bool specializationSupported() {
    static const bool ready=[] {
        if(!orderingSupported() || !df3d_area::staffMutationFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x3d;++i){hash^=base[0x1431c60+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x847f3e61256a3cba);
    }();return ready;
}
inline std::optional<Specialization> specialization(df::unit* unit) {
    if(!unit || !specializationSupported())return std::nullopt;
    Specialization result;result.onlyAssigned=unit->flags4.bits.only_do_assigned_jobs;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(unsigned i=0;i<8;++i){hash^=value&255;hash*=UINT64_C(1099511628211);value>>=8;}};
    add(unit->id);add(unit->hist_figure_id);add(unit->race);add(unit->caste);add(int(unit->profession));
    add(result.onlyAssigned);for(bool labor:unit->status.labors)add(labor);
    result.revision=hash&uint64_t(INT64_MAX);if(!result.revision)result.revision=1;
    return result;
}
inline SpecializationOutcome setSpecialization(int32_t id,uint64_t revision,bool onlyAssigned) {
    if(!specializationSupported())return SpecializationOutcome::Unavailable;
    const auto ids=orderedResidents(0,false);
    if(!ids)return SpecializationOutcome::Unavailable;
    if(!revision || std::find(ids->begin(),ids->end(),id)==ids->end())return SpecializationOutcome::Rejected;
    auto* unit=df::unit::find(id);const auto before=specialization(unit);
    if(!before)return SpecializationOutcome::Rejected;
    if(before->revision!=revision)return SpecializationOutcome::Stale;
    if(before->onlyAssigned==onlyAssigned)return SpecializationOutcome::Rejected;
    // Native Residents action1431c60 reads only this owned input's unit at+8,
    // toggles flags4 bit10, then calls the pinned labor recalculation4390d0.
    // No widget, live callback object, menu state or rendering is involved.
    struct Input {void* unused=nullptr;df::unit* unit=nullptr;} input{nullptr,unit};
    static_assert(offsetof(Input,unit)==8);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Apply=bool (*)(Input*);
    try {
        const bool applied=reinterpret_cast<Apply>(const_cast<uint8_t*>(base+0x1431c60))(&input);
        return applied && unit->flags4.bits.only_do_assigned_jobs==onlyAssigned?
            SpecializationOutcome::Applied:SpecializationOutcome::Unknown;
    } catch(...) {return SpecializationOutcome::Unknown;}
}
}
