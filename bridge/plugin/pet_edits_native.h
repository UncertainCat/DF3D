#pragma once
#include "pet_controls_native.h"
#include "df/item_petst.h"
#include "df/training_assignment.h"

namespace df3d_residents {
enum class PetEditOutcome {Applied,Rejected,Stale,Unavailable,Unknown};
struct PetEditState {PetControls controls;std::array<bool,6> values{};uint64_t revision=0;};
inline bool petEditsSupported() {
    static const bool ready=[] {
        if(!petControlsSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x3d0ca0,0xdb,UINT64_C(0xf48fea20c54d0143)},
            {0x3d0e50,0xdb,UINT64_C(0x84921bf0fa440e9c)},
            {0x3d0c40,0x2e,UINT64_C(0x798f77116b6b9de1)},
            {0x3d0a90,0xd8,UINT64_C(0x9a213ac9057a0a78)},
            {0x3d1280,0x130,UINT64_C(0x54ace1e60ce1a7b5)},
            {0x3d1460,0x130,UINT64_C(0xc5101784dd2aac24)},
            {0x142c110,0xe2,UINT64_C(0x56672cf6b85a16ac)},
            {0x142c200,0xe2,UINT64_C(0x3df11a9d7aa026a8)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
inline std::optional<PetEditState> petEditState(int kind,int32_t id) {
    if(!petEditsSupported() || (kind!=0 && kind!=1))return std::nullopt;
    CreatureReference entry{};
    if(kind==0)entry.unit=df::unit::find(id);
    else {entry.item=df::item::find(id);entry.kind=1;}
    const auto controls=petControls(entry);if(!controls)return std::nullopt;
    PetEditState result;result.controls=*controls;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(unsigned i=0;i<8;++i){hash^=value&255;hash*=UINT64_C(1099511628211);value>>=8;}};
    add(kind);add(id);
    if(kind==0) {
        const auto* unit=entry.unit;
        result.values={bool(unit->flags2.bits.slaughter),bool(unit->flags3.bits.available_for_adoption),bool(unit->flags3.bits.marked_for_gelding)};
        add(unit->hist_figure_id);add(unit->race);add(unit->caste);
        add(unit->flags1.whole);add(unit->flags2.whole);add(unit->flags3.whole);
        const auto* training=df::training_assignment::find(id);
        add(training!=nullptr);
        if(training) {
            add(training->trainer_id);add(training->flags.whole);
            result.values[4]=training->flags.bits.train_war;
            result.values[5]=training->flags.bits.train_hunt;
        }
    } else {
        auto* pet=virtual_cast<df::item_petst>(entry.item);if(!pet)return std::nullopt;
        result.values[1]=pet->pet_flags.bits.available_for_adoption;
        add(pet->getType());add(pet->getRace());add(pet->getCaste());add(pet->owner_id);
        add(pet->flags.whole);add(pet->pet_flags.whole);
    }
    for(const auto& caption:controls->captions){add(caption.size());for(unsigned char ch:caption)add(ch);}
    for(auto owner:controls->owners)add(owner);
    for(auto action:controls->actions)add(action);
    result.revision=hash&uint64_t(INT64_MAX);if(!result.revision)result.revision=1;
    return result;
}
namespace pet_detail {
struct RefreshEntry {CreatureReference target;std::weak_ptr<void> row;};
struct RefreshContext {std::array<std::byte,0x6a0> prefix{};std::vector<RefreshEntry> pending;};
struct Input {void* unused=nullptr;void* target=nullptr;std::weak_ptr<RefreshContext> list;std::weak_ptr<void> row;};
static_assert(sizeof(RefreshEntry)==32);
static_assert(offsetof(RefreshContext,pending)==0x6a0);
static_assert(offsetof(Input,target)==8 && offsetof(Input,list)==0x10 && offsetof(Input,row)==0x20);
}
inline PetEditOutcome setPetAction(int kind,int32_t id,uint64_t revision,int action,bool desired) {
    if(!petEditsSupported())return PetEditOutcome::Unavailable;
    if(action<0 || action>5 || action==3 || (kind==1 && action!=1) || !revision)return PetEditOutcome::Rejected;
    const auto members=orderedCreatures(1,0,false);if(!members)return PetEditOutcome::Unavailable;
    if(std::none_of(members->begin(),members->end(),[&](const auto& row){return row.kind==kind && row.id==id;}))return PetEditOutcome::Rejected;
    const auto before=petEditState(kind,id);if(!before)return PetEditOutcome::Rejected;
    if(before->revision!=revision)return PetEditOutcome::Stale;
    if(before->values[action]==desired || std::find(before->controls.actions.begin(),before->controls.actions.end(),action)==before->controls.actions.end())return PetEditOutcome::Rejected;
    // The native callback's weak list locks this owned context. Reserve the one
    // deferred refresh before changing gameplay state; no native list is used.
    auto refresh=std::make_shared<pet_detail::RefreshContext>();refresh->pending.reserve(1);
    pet_detail::Input input;
    input.target=kind==0?static_cast<void*>(df::unit::find(id)):static_cast<void*>(df::item::find(id));
    input.list=refresh;
    alignas(16) std::array<std::byte,0x158> glyphScratch{};
    auto* glyphPointer=glyphScratch.data();
    // Training routines update assignments and invalidate native training activity
    // caches across active units. Their only presentation output is this owned
    // glyph scratch; do not replace the call with an assignment flag write.
    constexpr size_t unitActions[]={0x3d0ca0,0x3d0e50,0x3d0c40,0,0x3d1460,0x3d1280};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Apply=bool (*)(pet_detail::Input*,void*);
    try {
        const bool applied=reinterpret_cast<Apply>(const_cast<uint8_t*>(base+(kind==1?0x3d0a90:unitActions[action])))(&input,&glyphPointer);
        const auto after=petEditState(kind,id);
        const bool refreshValid=action>=2?refresh->pending.empty():
            refresh->pending.size()==1 && refresh->pending[0].target.kind==kind &&
            (kind==0?static_cast<void*>(refresh->pending[0].target.unit):static_cast<void*>(refresh->pending[0].target.item))==input.target;
        return applied && refreshValid && after && after->values[action]==desired?PetEditOutcome::Applied:PetEditOutcome::Unknown;
    } catch(...) {return PetEditOutcome::Unknown;}
}
}
