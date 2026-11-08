#pragma once
#include <array>
#include <optional>
#include <windows.h>
#include "df/global_objects.h"
#include "df/world.h"
#include "df/plotinfost.h"
#include "df/reaction.h"

namespace df3d_standing {
// Native4331ca..4334fa: automatic reaction availability and scalar effects.
// The menu handler itself is never called; inputs are simulation globals/raws.
struct WorkshopSetting {int32_t id;uint8_t value;bool available;};
using WorkshopSettings=std::array<WorkshopSetting,11>;
inline uint8_t* supportedBase() {
    static auto* checked=[]()->uint8_t* {
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        if(!base)return nullptr;
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>0x1000)return nullptr;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
           pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000)return nullptr;
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x330;++i){hash^=base[0x4331ca+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xd165a25c665d4e6d)?base:nullptr;
    }();
    return checked;
}
inline std::array<uint8_t*,11> workshopValues() {
    return {df::global::standing_orders_auto_loom,df::global::standing_orders_use_dyed_cloth,
        df::global::standing_orders_auto_collect_webs,df::global::standing_orders_auto_slaughter,
        df::global::standing_orders_auto_butcher,df::global::standing_orders_auto_fishery,
        df::global::standing_orders_auto_kitchen,df::global::standing_orders_auto_tan,
        df::global::standing_orders_auto_kiln,df::global::standing_orders_auto_smelter,
        df::global::standing_orders_auto_other};
}
inline std::optional<WorkshopSettings> workshopSettings() {
    auto* base=supportedBase();
    if(!base || !df::global::world || !df::global::plotinfo)return std::nullopt;
    constexpr std::array<size_t,11> addresses={0x18d6f3f,0x18d6f94,0x189c1f6,0x189c1f0,
        0x189c1ec,0x189c1f5,0x189c1ee,0x189c1f4,0x189c1e9,0x189c11c,0x189c1e8};
    const auto values=workshopValues();WorkshopSettings result{};
    for(size_t i=0;i<values.size();++i){
        if(values[i]!=base+addresses[i] || *values[i]>(i==0?2:1))return std::nullopt;
        result[i]={int32_t(i),*values[i],i<6};
    }
    // Native exposes automation only where an AUTOMATIC raw reaction uses the
    // corresponding workshop/furnace. This is not built-workshop existence.
    for(const auto* reaction:df::global::world->raws.reactions.reactions){
        if(!reaction)return std::nullopt;
        if(!reaction->flags.is_set(df::reaction_flags::AUTOMATIC))continue;
        if(reaction->building.type.size()!=reaction->building.subtype.size())return std::nullopt;
        for(size_t i=0;i<reaction->building.type.size();++i){
            const int type=int(reaction->building.type[i]),subtype=reaction->building.subtype[i];
            if(type==13){
                if(subtype==19)result[6].available=true;
                else if(subtype==12)result[7].available=true;
                else if(subtype==23)result[10].available=true;
            } else if(type==5){
                if(subtype==3)result[8].available=true;
                else if(subtype==1)result[9].available=true;
                else if(subtype==7)result[10].available=true;
            }
        }
    }
    return result;
}
enum class EditOutcome {Unavailable,Stale,Applied};
inline EditOutcome setWorkshop(int32_t id,int32_t expected,int32_t desired) {
    if(id<0 || id>=11 || desired<0 || desired>(id==0?2:1))return EditOutcome::Unavailable;
    const auto snapshot=workshopSettings();
    if(!snapshot || !(*snapshot)[id].available)return EditOutcome::Unavailable;
    if((*snapshot)[id].value!=expected)return EditOutcome::Stale;
    // Native's scalar branches have no gameplay side effects or notifications.
    // All preflight and allocations precede this single nonthrowing write.
    *workshopValues()[id]=uint8_t(desired);
    return EditOutcome::Applied;
}
// Native4334ff..433750 and switch tables434558..434598. These categories
// toggle simulation bytes inline; never invoke the surrounding menu handler.
struct CategorySetting {int32_t id;uint8_t value;bool visible;bool editable;};
struct CategorySettings {std::array<CategorySetting,10> rows{};size_t count=0;};
inline uint8_t* categoryBase() {
    static auto* checked=[]()->uint8_t* {
        auto* base=supportedBase();if(!base)return nullptr;
        uint64_t code=UINT64_C(14695981039346656037),table=code;
        for(size_t i=0;i<0x251;++i){code^=base[0x4334ff+i];code*=UINT64_C(1099511628211);}
        for(size_t i=0;i<0x40;++i){table^=base[0x434558+i];table*=UINT64_C(1099511628211);}
        return code==UINT64_C(0x95f6ceb18ac24581) && table==UINT64_C(0x3084a3ff50f8edc1)?base:nullptr;
    }();
    return checked;
}
inline std::array<uint8_t*,10> categoryValues(int32_t category) {
    if(category==1)return {df::global::standing_orders_gather_animals,
        df::global::standing_orders_gather_food,df::global::standing_orders_gather_furniture,
        df::global::standing_orders_gather_bodies,df::global::standing_orders_gather_minerals,
        df::global::standing_orders_gather_wood};
    if(category==2)return {df::global::standing_orders_gather_refuse,
        df::global::standing_orders_gather_refuse_outside,df::global::standing_orders_gather_vermin_remains,
        df::global::standing_orders_dump_corpses,df::global::standing_orders_dump_skulls,
        df::global::standing_orders_dump_bones,df::global::standing_orders_dump_shells,
        df::global::standing_orders_dump_skins,df::global::standing_orders_dump_hair,
        df::global::standing_orders_dump_other};
    return {};
}
inline void categoryFlags(int32_t category,CategorySettings& result) noexcept {
    if(category==2)for(size_t i=1;i<result.count;++i){
        result.rows[i].visible=result.rows[0].value!=0;
        result.rows[i].editable=result.rows[i].visible && (i!=2 || result.rows[1].value!=0);
    }
}
inline std::optional<CategorySettings> categorySettings(int32_t category) {
    auto* base=categoryBase();
    if(!base || !df::global::world || !df::global::plotinfo || (category!=1 && category!=2))return std::nullopt;
    constexpr std::array<size_t,10> hauling={0x189c11d,0x189c1e5,0x189c1e4,0x189c1f3,0x189c1e7,0x189c1ef};
    constexpr std::array<size_t,10> refuse={0x189c11e,0x18d6f1e,0x18d6f37,0x18d6f8e,0x18d6f2e,
        0x18d6f2f,0x18d6f8f,0x18d6f36,0x18d6f65,0x18d6f3e};
    const auto values=categoryValues(category);const auto& addresses=category==1?hauling:refuse;
    CategorySettings result;result.count=category==1?6:10;
    for(size_t i=0;i<result.count;++i){
        if(values[i]!=base+addresses[i] || *values[i]>1)return std::nullopt;
        result.rows[i]={int32_t(i),*values[i],true,true};
    }
    categoryFlags(category,result);
    return result;
}
inline EditOutcome setCategory(int32_t category,int32_t id,int32_t expected,int32_t desired,CategorySettings* receipt=nullptr) {
    if(id<0 || desired<0 || desired>1)return EditOutcome::Unavailable;
    auto snapshot=categorySettings(category);
    if(!snapshot || size_t(id)>=snapshot->count || !snapshot->rows[id].editable)return EditOutcome::Unavailable;
    if(snapshot->rows[id].value!=expected)return EditOutcome::Stale;
    // Complete preflight before the sole nonthrowing scalar effect.
    *categoryValues(category)[id]=uint8_t(desired);
    snapshot->rows[id].value=uint8_t(desired);categoryFlags(category,*snapshot);
    if(receipt)*receipt=*snapshot;
    return EditOutcome::Applied;
}

}
