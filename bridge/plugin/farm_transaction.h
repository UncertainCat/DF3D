#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

namespace df3d_production {
// Pointer-free content revision; transport world epoch remains a separate key.
template<class Snapshot> uint64_t farmRevision(const Snapshot& snapshot) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto byte=[&](uint8_t value){hash^=value;hash*=UINT64_C(1099511628211);};
    const auto number=[&](uint64_t value){for(int i=0;i<8;++i){byte(uint8_t(value));value>>=8;}};
    for(const auto* text:{&snapshot.customName,&snapshot.headerName}) {number(text->size());for(unsigned char c:*text)byte(c);}
    byte(snapshot.removing);byte(snapshot.removalSuspended);byte(snapshot.removalHasWorker);
    number(snapshot.buildingId);number(snapshot.selectedSeason);number(snapshot.currentSeason);
    number(snapshot.currentFertilization);number(snapshot.maxFertilization);
    number(snapshot.pendingFertilization);byte(snapshot.seasonalFertilization);
    for(auto crop:snapshot.seasonalCrops)number(crop);
    number(snapshot.choices.size());
    for(const auto& row:snapshot.choices) {
        number(row.id);number(row.name.size());for(unsigned char c:row.name)byte(c);
        byte(row.seedsAvailable);byte(row.currentSeasonWarning);
        number(row.rawId.size());for(unsigned char c:row.rawId)byte(c);
    }
    return (hash&INT64_MAX)?(hash&INT64_MAX):1;
}

enum class FarmEditOutcome : uint8_t { Rejected, Completed, Stale, Unknown };
template<class Snapshot> struct FarmEditResult {
    FarmEditOutcome outcome=FarmEditOutcome::Rejected;
    bool mutated=false;
    std::optional<Snapshot> receipt;
};

// Removal and cancellation are explicit opposite intents, never a toggle.
// Apply=false promises no effect; any exception after entry is Unknown. Native
// removal may retire fertilizer jobs; cancellation clears every building job.
// Callers validate a visible completed farm and the current epoch at a safe point.
template<class Snapshot,class Apply,class Observe,class Valid>
FarmEditResult<Snapshot> finishFarmRemoval(const Snapshot& before,uint64_t expectedRevision,
                                          bool remove,Apply apply,Observe observe,Valid valid) {
    FarmEditResult<Snapshot> result;
    try {
        if(!expectedRevision || !valid(before) || before.pendingFertilization<0 ||
           (!before.removing && (before.removalSuspended || before.removalHasWorker)))return result;
    } catch(...) {return result;}
    if(before.revision!=expectedRevision){result.outcome=FarmEditOutcome::Stale;return result;}
    if(before.removing==remove)return result;
    result.mutated=true;result.outcome=FarmEditOutcome::Unknown;
    try {
        if(!apply()){result.mutated=false;result.outcome=FarmEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after || !valid(*after) || after->removing!=remove ||
           after->pendingFertilization<0 || after->pendingFertilization>before.pendingFertilization ||
           (!remove && (after->removalSuspended || after->removalHasWorker || after->pendingFertilization!=0)))return result;
        auto unchanged=*after;
        unchanged.removing=before.removing;unchanged.removalSuspended=before.removalSuspended;
        unchanged.removalHasWorker=before.removalHasWorker;
        unchanged.pendingFertilization=before.pendingFertilization;
        if(farmRevision(unchanged)!=farmRevision(before))return result;
        result.receipt=std::move(after);result.outcome=FarmEditOutcome::Completed;
    } catch(...) {result.receipt.reset();}
    return result;
}

// Native8bb3eb..8bb4ae assigns a changed local draft directly to building.name.
// Its text-input helpers own SDL/global input state and must not run here.
// Convert must return a lossless CP437 encoding, or nullopt. It is read-only;
// Apply receives owned bytes and false must mean no effect began. Callers still
// validate the current epoch, visible completed farm and exact target at a safe point.
template<class Snapshot,class Convert,class Apply,class Observe,class Valid>
FarmEditResult<Snapshot> finishFarmRename(const Snapshot& before,uint64_t expectedRevision,
                                         const std::string& requested,Convert convert,
                                         Apply apply,Observe observe,Valid valid) {
    FarmEditResult<Snapshot> result;
    std::optional<std::string> bytes;
    try {
        if(!expectedRevision || !valid(before) || before.removing || requested.size()>90 ||
           requested.find('\0')!=std::string::npos)return result;
        bytes=convert(requested);
        if(!bytes || bytes->size()>30 || bytes->find('\0')!=std::string::npos)return result;
    } catch(...) {return result;}
    if(before.revision!=expectedRevision){result.outcome=FarmEditOutcome::Stale;return result;}
    if(before.customName==requested) {
        try {result.receipt=before;result.outcome=FarmEditOutcome::Completed;} catch(...) {}
        return result;
    }
    result.mutated=true;result.outcome=FarmEditOutcome::Unknown;
    try {
        if(!apply(*bytes)){result.mutated=false;result.outcome=FarmEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after || !valid(*after) || after->customName!=requested || after->headerName.empty())return result;
        // At this safe point a rename may change only the raw/formatted names.
        // Compare every other semantic field, including choices and removal facts.
        auto unchanged=*after;unchanged.customName=before.customName;unchanged.headerName=before.headerName;
        if(farmRevision(unchanged)!=farmRevision(before))return result;
        result.receipt=std::move(after);result.outcome=FarmEditOutcome::Completed;
    } catch(...) {result.receipt.reset();}
    return result;
}

// Called at one DF safe point with a freshly observed receipt. Apply's false
// or nullopt must mean no effects began (the setFarmCrop contract). Exceptions
// after entry, or failed post-effect observation, are Unknown with no authority.
// No callback is retried. Transport must also check the producer/world epoch.
template<class Snapshot,class Apply,class Observe,class Valid>
FarmEditResult<Snapshot> finishFarmEdit(const Snapshot& before,uint64_t expectedRevision,int32_t crop,
                                      Apply apply,Observe observe,Valid valid) {
    FarmEditResult<Snapshot> result;
    try {
        if(!expectedRevision || !valid(before) || crop < -1 || crop>32767 ||
           before.selectedSeason<0 || before.selectedSeason>3 || before.seasonalCrops.size()!=4)return result;
    } catch(...) {return result;}
    if(before.revision!=expectedRevision){result.outcome=FarmEditOutcome::Stale;return result;}
    result.mutated=true;result.outcome=FarmEditOutcome::Unknown;
    try {
        const auto accepted=apply();
        if(!accepted || !*accepted){result.mutated=false;result.outcome=FarmEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after || !valid(*after) || after->buildingId!=before.buildingId ||
           after->selectedSeason!=before.selectedSeason || after->currentSeason!=before.currentSeason ||
           after->seasonalCrops.size()!=4 || after->seasonalCrops[before.selectedSeason]!=crop)return result;
        for(int i=0;i<4;++i)if(i!=before.selectedSeason && after->seasonalCrops[i]!=before.seasonalCrops[i])return result;
        result.receipt=std::move(after);result.outcome=FarmEditOutcome::Completed;
    } catch(...) {result.receipt.reset();}
    return result;
}
// seasonal=-1 activates the native immediate checkbox; 0/1 sets seasonal intent.
template<class Snapshot,class Apply,class Observe,class Valid>
FarmEditResult<Snapshot> finishFarmFertilization(const Snapshot& before,uint64_t expectedRevision,int seasonal,
                                                Apply apply,Observe observe,Valid valid) {
    FarmEditResult<Snapshot> result;
    try {
        if(!expectedRevision || !valid(before) || seasonal < -1 || seasonal>1)return result;
    } catch(...) {return result;}
    if(before.revision!=expectedRevision){result.outcome=FarmEditOutcome::Stale;return result;}
    result.mutated=true;result.outcome=FarmEditOutcome::Unknown;
    try {
        if(!apply()){result.mutated=false;result.outcome=FarmEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after || !valid(*after) || after->buildingId!=before.buildingId ||
           after->selectedSeason!=before.selectedSeason || after->currentSeason!=before.currentSeason ||
           after->seasonalCrops!=before.seasonalCrops || after->currentFertilization!=before.currentFertilization ||
           after->maxFertilization!=before.maxFertilization)return result;
        if(seasonal>=0) {
            if(after->seasonalFertilization!=(seasonal!=0) || after->pendingFertilization!=before.pendingFertilization)return result;
        } else {
            if(after->seasonalFertilization!=before.seasonalFertilization)return result;
            const int64_t remaining=int64_t(before.maxFertilization)-before.currentFertilization;
            if(before.pendingFertilization>=remaining) {
                if(after->pendingFertilization!=0)return result;
            } else if(after->pendingFertilization!=remaining && after->pendingFertilization!=before.pendingFertilization)return result;
            // Native scheduling can finish without creating jobs if no footprint
            // position qualifies. Completion reports observed facts, not progress.
        }
        result.receipt=std::move(after);result.outcome=FarmEditOutcome::Completed;
    } catch(...) {result.receipt.reset();}
    return result;
}

}
