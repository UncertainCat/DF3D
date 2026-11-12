#pragma once
#include "justice_native.h"
#include "df/punishment.h"
#include <unordered_set>

namespace df3d_justice {
struct ConvictCrime {int32_t id=-1;std::string caption;std::optional<std::string> injuredParty;};
struct ConvictDetail {int32_t unitId=-1;std::vector<std::string> sentence;std::optional<std::string> officer;std::vector<ConvictCrime> crimes;};
// These selections/labels are inline in native widget builders. Keep only their
// semantic branches, invoking the standalone native caption/name/number routines.
// Never invoke the builders or use native unit lists, selection or punishment index.
inline bool convictsReady() {
    auto* world=df::global::world;auto* plot=df::global::plotinfo;
    if(!world || !plot || world->crimes.all.size()>1048576 || plot->punishments.size()>1048576)return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto at=[base](const void* p,size_t rva){return p==base+rva;};
    if(!at(&world->crimes.all,0x24e7d48) || !at(&world->units.all,0x23e50b0) ||
       !at(&plot->site_id,0x2393674) || !at(&plot->group_id,0x2393678) || !at(&plot->punishments,0x2393578))return false;
    static_assert(offsetof(df::crime,accused)==0x40 && offsetof(df::crime,victim)==0x70 && offsetof(df::crime,flags)==0xa0);
    static_assert(offsetof(df::crime,site)==0xb8 && offsetof(df::crime,entity)==0xbc);
    static_assert(offsetof(df::punishment,criminal)==0 && offsetof(df::punishment,officer)==4 &&
                  offsetof(df::punishment,beating)==8 && offsetof(df::punishment,hammer_strikes)==10 && offsetof(df::punishment,prison_counter)==12);
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xec3b0,0x115,UINT64_C(0xf53b8cf39899d109)},
            {0xec980,0x2e7,UINT64_C(0x2230db9b36ca4285)},
            {0xecc90,0x1df,UINT64_C(0x7e8b87af1025223a)},
            {0x470d67,0x3a,UINT64_C(0x03362a6114920064)},
            {0x470757,0x827,UINT64_C(0xd3944d9a7b7de020)},
            {0x471eb0,0x170,UINT64_C(0x6e219b3329eb6c78)},
            {0x472020,0x877,UINT64_C(0x88208a2ece102d6e)},
            {0x4728a0,0x217,UINT64_C(0xc4b146a02c0a5bb4)},
            {0x46f6d0,0x3c8,UINT64_C(0x5665ef9c4a897784)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
        };
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=pin.hash)return false;}
        return true;
    }();
    return pinned;
}
inline bool convictCrimeInScope(const df::crime& crime) {
    const auto* plot=df::global::plotinfo;
    return crime.flags.bits.discovered && crime.site==plot->site_id && crime.entity==plot->group_id;
}
inline std::optional<std::vector<CandidateFact>> convicts(std::string query={},std::vector<CandidateSort> sorts={{CandidateColumn::Category,false}}) {
    if(!convictsReady())return std::nullopt;
    // Native470829 inserts into an unordered collection; equal category keys
    // retain its iteration order. Use the native insertion/rehash routine on
    // our own MSVC container, never the Justice widget's roster or hash table.
    std::unordered_set<df::unit*> units;
    static_assert(sizeof(units)==0x40);
    if(units.bucket_count()!=8 || units.max_load_factor()!=1.0f)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct InsertResult {void* node=nullptr;bool inserted=false;uint8_t padding[7]{};};
    for(const auto* crime:df::global::world->crimes.all){if(!crime)return std::nullopt;
        if(convictCrimeInScope(*crime))if(auto* unit=df::unit::find(crime->accused)){
            InsertResult inserted;
            reinterpret_cast<void(*)(void*,InsertResult*,df::unit**)>(base+0xec980)(&units,&inserted,&unit);
        }}
    std::vector<CandidateFact> result;result.reserve(units.size());
    for(auto* unit:units)result.push_back({unit->id,0,0});
    return orderedCandidateFacts(result,std::move(query),std::move(sorts));
}
inline std::optional<ConvictDetail> convictDetail(int32_t unitId) {
    if(!convictsReady() || !df::unit::find(unitId))return std::nullopt;
    ConvictDetail result;result.unitId=unitId;
    for(const auto* crime:df::global::world->crimes.all){if(!crime)return std::nullopt;
        if(!convictCrimeInScope(*crime) || crime->accused!=unitId)continue;
        const auto title=caption(crime);const auto summary=caseSummary(crime);if(!title || !summary)return std::nullopt;
        result.crimes.push_back({crime->id,*title,summary->injuredParty});}
    if(result.crimes.empty())return std::nullopt;
    const df::punishment* selected=nullptr;
    const auto& punishments=df::global::plotinfo->punishments;
    for(auto i=punishments.rbegin();i!=punishments.rend();++i){if(!*i)return std::nullopt;if((*i)->criminal==unitId){selected=*i;break;}}
    if(!selected){result.sentence.push_back("No sentence pending.");return result;}
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto number=[base](int32_t value){std::string text;reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130)(value,&text);return text;};
    if(!selected->beating && !selected->hammer_strikes && !selected->prison_counter)result.sentence.push_back("No sentence pending.");
    if(selected->hammer_strikes>0)result.sentence.push_back(number(selected->hammer_strikes)+" hammerstrike"+(selected->hammer_strikes>1?"s":"")+".");
    if(selected->beating>0)result.sentence.push_back("Beating.");
    if(selected->prison_counter>0){const auto days=selected->prison_counter/120+1;result.sentence.push_back(number(days)+" day"+(days>1?"s":"")+" in prison.");}
    std::string officer="none assigned";
    if(auto* unit=df::unit::find(selected->officer)){
        if(!df3d_creature::inventoryDescriptionReady() || unit->inventory.size()>10000)return std::nullopt;
        for(const auto* entry:unit->inventory)if(!entry)return std::nullopt;
        df3d_creature::InventoryRandomRestore restore(base);df3d_creature::InventoryDescriptionContext owned(*unit);officer.clear();
        reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&officer,false);
        if(officer.size()>16384)return std::nullopt;
    }
    result.officer="Officer: "+officer+".";return result;
}
}
