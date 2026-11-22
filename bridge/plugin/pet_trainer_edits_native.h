#pragma once
#include "pet_edits_native.h"
#include "pet_trainers_native.h"

namespace df3d_residents {
enum class TrainerMode {None,Any,Unassigned,Individual};
inline bool petTrainerEditsSupported() {
    static const bool ready=[] {
        if(!petEditsSupported() || !petTrainersSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x36eda0,0x1ab,UINT64_C(0xdab95aecbfffa9cf)},
            {0x36ef50,0x1ab,UINT64_C(0xfe67eff9d1cce267)},
            {0x36f100,0x1a4,UINT64_C(0x5dd6b6ad3394d5cb)},
            {0x36f2b0,0x1cd,UINT64_C(0x5b8b33180b4fed3b)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
namespace pet_detail {
struct TrainerClose {std::array<std::byte,0x178> prefix{};uint8_t closed=0;};
// Any stores row/list in the opposite order to None and Unassigned.
struct GenericTrainerInput {std::weak_ptr<void> close,second,third;df::unit* animal=nullptr;};
struct IndividualTrainerInput {df::unit* trainer=nullptr;df::unit* animal=nullptr;std::weak_ptr<void> close,row,list;};
static_assert(offsetof(TrainerClose,closed)==0x178);
static_assert(offsetof(GenericTrainerInput,animal)==0x30);
static_assert(offsetof(IndividualTrainerInput,close)==0x10 && offsetof(IndividualTrainerInput,list)==0x30);
}
inline PetEditOutcome setPetTrainer(int32_t animalId,uint64_t revision,TrainerMode mode,int32_t trainerId) {
    if(!petTrainerEditsSupported())return PetEditOutcome::Unavailable;
    const auto value=int(mode);
    if(!revision || value<0 || value>3 || (mode==TrainerMode::Individual?trainerId<0:trainerId!=-1))return PetEditOutcome::Rejected;
    const auto members=orderedCreatures(1,0,false);if(!members)return PetEditOutcome::Unavailable;
    if(std::none_of(members->begin(),members->end(),[&](const auto& row){return row.kind==0 && row.id==animalId;}))return PetEditOutcome::Rejected;
    const auto before=petEditState(0,animalId);if(!before)return PetEditOutcome::Rejected;
    if(before->revision!=revision)return PetEditOutcome::Stale;
    if(std::find(before->controls.actions.begin(),before->controls.actions.end(),3)==before->controls.actions.end())return PetEditOutcome::Rejected;
    if(mode==TrainerMode::Individual) {
        const auto choices=petTrainers(animalId);if(!choices)return PetEditOutcome::Unavailable;
        if(std::none_of(choices->begin(),choices->end(),[&](const auto& row){return row.id==trainerId;}))return PetEditOutcome::Rejected;
    }
    const auto* previous=df::training_assignment::find(animalId);
    const uint32_t flags=previous?previous->flags.whole:0;
    const uint32_t desiredMode=mode==TrainerMode::Any?1:mode==TrainerMode::Unassigned?2:0;
    if(mode==TrainerMode::None?!previous:previous && previous->trainer_id==trainerId && (flags&3)==desiredMode)return PetEditOutcome::Rejected;
    auto close=std::make_shared<pet_detail::TrainerClose>();
    auto refresh=std::make_shared<pet_detail::RefreshContext>();refresh->pending.reserve(1);
    auto* animal=df::unit::find(animalId);
    pet_detail::GenericTrainerInput generic;generic.close=close;generic.animal=animal;
    if(mode==TrainerMode::Any)generic.third=refresh;else generic.second=refresh;
    pet_detail::IndividualTrainerInput individual;
    individual.trainer=mode==TrainerMode::Individual?df::unit::find(trainerId):nullptr;
    individual.animal=animal;individual.close=close;individual.list=refresh;
    constexpr size_t actions[]={0x36f100,0x36eda0,0x36ef50,0x36f2b0};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Apply=bool (*)(void*);
    try {
        const bool applied=reinterpret_cast<Apply>(const_cast<uint8_t*>(base+actions[value]))(
            mode==TrainerMode::Individual?static_cast<void*>(&individual):static_cast<void*>(&generic));
        const auto* after=df::training_assignment::find(animalId);
        const bool matches=mode==TrainerMode::None?!after:
            after && after->trainer_id==trainerId && after->flags.whole==((flags&~uint32_t(3))|desiredMode);
        return applied && matches && close->closed==1 && refresh->pending.size()==1 &&
            refresh->pending[0].target.kind==0 && refresh->pending[0].target.unit==animal?PetEditOutcome::Applied:PetEditOutcome::Unknown;
    } catch(...) {return PetEditOutcome::Unknown;}
}
}
