#pragma once
#include "farm_transaction.h"
#include <vector>
#include <unordered_set>

namespace df3d_production {
struct ItemContainerContentFacts {
    int16_t itemType=-1;
    std::string materialToken,colorToken;
    int8_t effectiveArmorLevel=0;
    bool metal=false,coal=false,containsPowder=false;
    bool rollsSheets=false,protectsFoldedSheets=false,containsWriting=false;
};
struct ItemContainerContentsFacts {
    bool container=false;
    std::vector<ItemContainerContentFacts> entries;
};
struct ItemInspectionAppearance { std::string materialToken,subtypeRaw,colorToken;int32_t stack=1;uint8_t flags=0;int8_t instrumentFamily=-1,instrumentPlaced=-1; };
inline bool validInspectionInstrument(const ItemInspectionAppearance& a,int32_t type) {
    return type==13 ? a.instrumentFamily>=0&&a.instrumentFamily<=3&&a.instrumentPlaced>=0&&a.instrumentPlaced<=1 : a.instrumentFamily==-1&&a.instrumentPlaced==-1;
}
enum class BuildingItemAction { Forbid, Dump, Melt, Hidden };
struct BuildingItemJob { int32_t id=-1,type=-1;uint32_t flags=0; };
struct ItemFacts {
    int32_t id=-1;
    std::string caption;
    uint32_t flags=0;
    int8_t countdown=0,delay=0;
    bool forbid=false,dump=false,melt=false,hidden=false,canDump=false,canMelt=false;
    std::vector<BuildingItemJob> jobs;
    int32_t itemType=-1;std::string materialToken,subtypeRaw;
};
struct BuildingContentsRow : ItemFacts { int32_t role=-1;std::optional<ItemInspectionAppearance> appearance; };
struct BuildingContentsSnapshot {
    int32_t buildingId=-1;
    uint64_t revision=0;
    bool completed=false,removing=false;
    std::vector<BuildingContentsRow> rows;
};
inline bool buildingItemValue(const ItemFacts& row,BuildingItemAction action) {
    switch(action) {
    case BuildingItemAction::Forbid:return row.forbid;
    case BuildingItemAction::Dump:return row.dump;
    case BuildingItemAction::Melt:return row.melt;
    case BuildingItemAction::Hidden:return row.hidden;
    }return false;
}
// Includes ordered membership, caption, eligibility, flags, stockpile delays and
// attached job identities/state. World/session epoch is checked by the caller.
inline uint64_t buildingContentsRevision(const BuildingContentsSnapshot& value) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto byte=[&](uint8_t n){hash^=n;hash*=UINT64_C(1099511628211);};
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){byte(uint8_t(n));n>>=8;}};
    number(value.buildingId);byte(value.completed);byte(value.removing);number(value.rows.size());
    for(const auto& row:value.rows) {
        number(row.id);number(row.role);number(row.caption.size());for(unsigned char c:row.caption)byte(c);
        number(row.flags);byte(row.countdown);byte(row.delay);
        number(row.itemType);
        for(const auto* text:{&row.materialToken,&row.subtypeRaw}){number(text->size());for(unsigned char c:*text)byte(c);}
        byte(row.forbid);byte(row.dump);byte(row.melt);byte(row.hidden);byte(row.canDump);byte(row.canMelt);
        byte(row.appearance.has_value());if(row.appearance){const auto& a=*row.appearance;
            for(const auto* text:{&a.materialToken,&a.subtypeRaw,&a.colorToken}){number(text->size());for(unsigned char c:*text)byte(c);}
            number(a.stack);byte(a.flags);byte(a.instrumentFamily);byte(a.instrumentPlaced);}
        number(row.jobs.size());for(const auto& job:row.jobs){number(job.id);number(job.type);number(job.flags);}
    }
    return (hash&INT64_MAX)?(hash&INT64_MAX):1;
}
inline bool validBuildingContents(const BuildingContentsSnapshot& value) {
    if(value.buildingId<0||!value.revision||value.revision!=buildingContentsRevision(value))return false;
    std::unordered_set<int32_t> ids;
    for(const auto& row:value.rows) {
        if(row.id<0||row.role<0||!ids.insert(row.id).second || row.itemType<0 || row.itemType>92 ||
           row.materialToken.size()>256 || row.subtypeRaw.size()>128)return false;
        if((row.itemType==13||row.itemType==30)&&!row.appearance)return false;
        if(row.appearance){const auto& a=*row.appearance;if(!validInspectionInstrument(a,row.itemType)||a.materialToken.empty()||a.materialToken!=row.materialToken||a.subtypeRaw!=row.subtypeRaw||a.colorToken.size()>128||a.stack<1||(a.flags&~96))return false;}
        for(const auto& job:row.jobs)if(job.id<0||job.type<0)return false;
    }
    return true;
}
struct BuildingContentsSlice {
    uint32_t cursor=0,nextCursor=0,total=0;
    // Captions are converted to transport encoding; revision remains that of
    // the complete native snapshot, not a hash of this presentation page.
    std::vector<BuildingContentsRow> rows;
};
template<class Convert>
std::optional<BuildingContentsSlice> pageBuildingContents(const BuildingContentsSnapshot& value,
    uint32_t cursor,uint64_t expected,Convert convert) {
    if(!validBuildingContents(value)||value.rows.size()>UINT32_MAX ||
       (cursor && !expected) || (expected && expected!=value.revision) ||
       (cursor>=value.rows.size() && (cursor || !value.rows.empty())))return std::nullopt;
    BuildingContentsSlice page;page.cursor=cursor;page.total=static_cast<uint32_t>(value.rows.size());
    size_t bytes=0;
    for(size_t i=cursor;i<value.rows.size() && page.rows.size()<64;++i) {
        auto caption=convert(value.rows[i].caption);
        if(caption.size()>128*1024-bytes)break;
        bytes+=caption.size();auto row=value.rows[i];row.caption=std::move(caption);page.rows.push_back(std::move(row));
    }
    if(page.rows.empty() && page.total)return std::nullopt;
    const uint32_t end=cursor+static_cast<uint32_t>(page.rows.size());
    page.nextCursor=end<page.total?end:0;return page;
}
// Apply=false promises no native entry. After entry only a fresh observation
// can establish completion; exceptions/lost targets are Unknown, never replayed.
// Native cleanup may legitimately alter other flags/jobs, so do not demand
// that the requested bit was the only changed fact.
template<class Apply,class Observe>
FarmEditResult<BuildingContentsSnapshot> finishBuildingItemEdit(
    const BuildingContentsSnapshot& before,uint64_t expected,int32_t itemId,
    BuildingItemAction action,bool desired,Apply apply,Observe observe,bool allowRemoving=false) {
    FarmEditResult<BuildingContentsSnapshot> result;
    const BuildingContentsRow* row=nullptr;
    try {
        if(!expected||!validBuildingContents(before)||!before.completed||(before.removing&&!allowRemoving))return result;
        if(before.revision!=expected){result.outcome=FarmEditOutcome::Stale;return result;}
        for(const auto& candidate:before.rows)if(candidate.id==itemId){row=&candidate;break;}
        if(!row)return result;
        switch(action) {
        case BuildingItemAction::Dump:if(!row->canDump)return result;break;
        case BuildingItemAction::Melt:if(!row->canMelt)return result;break;
        case BuildingItemAction::Forbid:case BuildingItemAction::Hidden:break;
        default:return result;
        }
        if(buildingItemValue(*row,action)==desired) {
            result.receipt=before;result.outcome=FarmEditOutcome::Completed;return result;
        }
    }catch(...){return result;}
    result.mutated=true;result.outcome=FarmEditOutcome::Unknown;
    try {
        if(!apply()){result.mutated=false;result.outcome=FarmEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after||!validBuildingContents(*after)||after->buildingId!=before.buildingId||
           !after->completed||after->removing!=before.removing)return result;
        for(const auto& candidate:after->rows)if(candidate.id==itemId) {
            if(buildingItemValue(candidate,action)!=desired)return result;
            result.receipt=std::move(after);result.outcome=FarmEditOutcome::Completed;return result;
        }
    }catch(...){result.receipt.reset();}
    return result;
}
}
