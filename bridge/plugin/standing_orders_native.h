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
// Additional scalar branches for Forbidding, Petitions and Other. The
// thirteen standingorder_* symbol aliases are independently verified by native
// click/readback captures; generated DFHack pointers for those names are absent.
inline uint8_t* extendedBase() {
    static auto* checked=[]()->uint8_t* {
        auto* base=categoryBase();if(!base)return nullptr;
        uint64_t hash0=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x31b;++i){hash0^=base[0x433750+i];hash0*=UINT64_C(1099511628211);}
        if(hash0!=UINT64_C(0x9aba5ed88022c9d3))return nullptr;
        uint64_t hash1=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x1a7;++i){hash1^=base[0x4342e7+i];hash1*=UINT64_C(1099511628211);}
        if(hash1!=UINT64_C(0x960e6742933c537d))return nullptr;
        uint64_t hash2=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x5c;++i){hash2^=base[0x434598+i];hash2*=UINT64_C(1099511628211);}
        if(hash2!=UINT64_C(0xf0d60142667bc370))return nullptr;
        return base;
    }();
    return checked;
}
inline size_t categoryCount(int32_t category) noexcept {
    switch(category){case 1:case 4:return 6;case 2:case 3:return 10;case 6:return 7;default:return 0;}
}
inline uint8_t categoryMax(int32_t category,int32_t id) noexcept {
    return category==3 || category==4?2:category==6 && id==0?3:1;
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
    auto* base=extendedBase();if(!base)return {};
    if(category==3)return {df::global::standing_orders_forbid_used_ammo,df::global::standing_orders_forbid_own_dead,df::global::standing_orders_forbid_own_dead_items,df::global::standing_orders_forbid_other_nohunt,df::global::standing_orders_forbid_other_dead_items,base+0x189c1ed,base+0x189c1eb,base+0x189c1f7,base+0x189c1f2,base+0x189c1ea};
    if(category==4)return {base+0x189c29d,base+0x189c295,base+0x189c29c,base+0x189c29e,base+0x189c297,base+0x189c296};
    if(category==6)return {df::global::standing_orders_job_cancel_announce,base+0x18d6f67,base+0x18d6f0f,df::global::standing_orders_farmer_harvest,df::global::standing_orders_mix_food,df::global::standing_orders_zoneonly_drink,df::global::standing_orders_zoneonly_fish};
    return {};
}
inline void categoryFlags(int32_t category,CategorySettings& result) noexcept {
    if(category==2)for(size_t i=1;i<result.count;++i){
        result.rows[i].visible=result.rows[0].value!=0;
        result.rows[i].editable=result.rows[i].visible && (i!=2 || result.rows[1].value!=0);
    }
}
inline std::optional<CategorySettings> categorySettings(int32_t category) {
    auto* base=category>=3?extendedBase():categoryBase();
    if(!base || !df::global::world || !df::global::plotinfo || !categoryCount(category))return std::nullopt;
    constexpr std::array<size_t,10> hauling={0x189c11d,0x189c1e5,0x189c1e4,0x189c1f3,0x189c1e7,0x189c1ef};
    constexpr std::array<size_t,10> refuse={0x189c11e,0x18d6f1e,0x18d6f37,0x18d6f8e,0x18d6f2e,
        0x18d6f2f,0x18d6f8f,0x18d6f36,0x18d6f65,0x18d6f3e};
    constexpr std::array<size_t,10> forbidding={0x189c1f1,0x18d6f1f,0x18d6f66,0x18d6f1d,0x189c11f,0x189c1ed,0x189c1eb,0x189c1f7,0x189c1f2,0x189c1ea};
    constexpr std::array<size_t,10> petitions={0x189c29d,0x189c295,0x189c29c,0x189c29e,0x189c297,0x189c296};
    constexpr std::array<size_t,10> other={0x189c117,0x18d6f67,0x18d6f0f,0x189c1e6,0x189c116,0x18d6f64,0x18d6f1c};
    const auto values=categoryValues(category);const auto& addresses=category==1?hauling:category==2?refuse:category==3?forbidding:category==4?petitions:other;
    CategorySettings result;result.count=categoryCount(category);
    for(size_t i=0;i<result.count;++i){
        if(values[i]!=base+addresses[i] || *values[i]>categoryMax(category,int32_t(i)))return std::nullopt;
        result.rows[i]={int32_t(i),*values[i],true,true};
    }
    categoryFlags(category,result);
    return result;
}
inline EditOutcome setCategory(int32_t category,int32_t id,int32_t expected,int32_t desired,CategorySettings* receipt=nullptr) {
    if(id<0 || desired<0 || desired>categoryMax(category,id))return EditOutcome::Unavailable;
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
