#include "area_links.h"
#include "stockpile_native.h"
#include "df/global_objects.h"
#include "df/world.h"
#include "df/building_stockpilest.h"
#include "df/item.h"
#include "df/custom_stockpile_interfacest.h"
#include "df/custom_stockpile_itemst.h"
#include "df/inorganic_raw.h"
#include "df/plant_raw.h"
#include "df/creature_raw.h"
#include "df/itemdef_ammost.h"
#include "df/itemdef_armorst.h"
#include "df/itemdef_glovesst.h"
#include "df/itemdef_helmst.h"
#include "df/itemdef_instrumentst.h"
#include "df/itemdef_pantsst.h"
#include "df/itemdef_shieldst.h"
#include "df/itemdef_shoesst.h"
#include "df/itemdef_siegeammost.h"
#include "df/itemdef_toolst.h"
#include "df/itemdef_toyst.h"
#include "df/itemdef_trapcompst.h"
#include "df/itemdef_weaponst.h"
#include <algorithm>
#include <windows.h>
#include <cstdint>

namespace df3d_area {
namespace {
uint64_t hash(const uint8_t* bytes, size_t size) {
    uint64_t value=14695981039346656037ULL;
    while(size--){value^=*bytes++;value*=1099511628211ULL;}
    return value;
}
bool supported(const uint8_t* base) {
    const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return false;
    const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
    if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=0x8664 ||
       pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000)return false;
    // DF53.16 Steam: preset dispatch, category initialization, clear, its two
    // leaf clear helpers, food defaults, remaining category defaults, vector resize.
    // Category initialization reads world raw vectors only. Defaults write only
    // the supplied settings. No viewscreen, menu, cursor, RNG or search scratch.
    static constexpr struct {size_t rva,size;uint64_t digest;} spans[]={
        {0x30dde0,0x284,0x2416b7f890dcc5c8ULL},
        {0x30e070,0x8de,0x0b6339ac229308d2ULL},
        {0x30e950,0x30a,0xbf6b4d07a83d3047ULL},
        {0x30d3a0,0x1e0,0x1a07cecec065344eULL},
        {0x30d670,0x9f,0x157142509d361a48ULL},
        {0x589990,0x700,0x2cffdef38e85d382ULL},
        {0x58a090,0xba8,0x976d41b1575bf126ULL},
        {0x1b9fb0,0x7d,0x8d074f444d49cc3eULL},
    };
    for(const auto& span:spans)if(hash(base+span.rva,span.size)!=span.digest)return false;
    return true;
}
void categoryHeader(const uint8_t* base,df::stockpile_settings& owned,size_t index,bool enabled) {
    static constexpr size_t clears[]={0x30d350,0x30d540,0x30d560,0x30d5a0,
        0x30d5e0,0x30d5a0,0x30d560,0x30d5a0,0x30d620,0x30d620,0x30d640,
        0x30d660,0x30d720,0x30d5a0,0x30d760,0x30d780,0x30d740};
    static constexpr size_t fills[]={0x30d300,0x30d530,0x30d550,0x30d570,
        0x30d5d0,0x30d570,0x30d550,0x30d570,0x30d610,0x30d610,0x30d630,
        0x30d650,0x30d710,0x30d570,0x30d750,0x30d770,0x30d730};
    void* fields[]={&owned.animals,&owned.food,&owned.furniture,&owned.corpses,
        &owned.refuse,&owned.stone,&owned.ammo,&owned.coins,&owned.bars_blocks,
        &owned.gems,&owned.finished_goods,&owned.leather,&owned.cloth,&owned.wood,
        &owned.weapons,&owned.armor,&owned.sheet};
    using Fill=void (*)(void*);
    reinterpret_cast<Fill>(base+(enabled?fills[index]:clears[index]))(fields[index]);
}
}
std::optional<bool> nativeStockpileTileType(uint16_t tile) {
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    // Includes both branches and all immutable jump-table bytes. These leaves
    // are called by native create/repaint; neither reads UI nor writes memory.
    static const bool compatible=supported(base) &&
        hash(base+0x289050,0x2eb)==0x0d12be3ad912c079fULL &&
        hash(base+0x2c2f10,0x20)==0xee0f7c2a6109db61ULL;
    if(!compatible)return std::nullopt;
    using Predicate=bool (*)(uint16_t);
    return reinterpret_cast<Predicate>(base+0x289050)(tile) ||
        reinterpret_cast<Predicate>(base+0x2c2f10)(tile);
}
std::optional<int32_t> nativeStockpileTileCount(df::building_stockpilest& pile) {
    if(!df::global::world)return std::nullopt;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=supported(base) &&
        hash(base+0x5587b0,0x79)==0x14b4f3f138690067ULL &&
        hash(base+0x57b770,0x113)==0x3fc5ac46eee9f334ULL;
    if(!compatible || pile.x1<0 || pile.y1<0 || pile.z<0 || pile.z>32767 ||
       pile.x2<pile.x1 || pile.y2<pile.y1 || pile.x2>32767 || pile.y2>32767 ||
       int64_t(pile.x2-pile.x1+1)*(pile.y2-pile.y1+1)>65536)return std::nullopt;
    // Stockpile's two predicate virtuals in57b770 are constant true. Invoke its
    // coordinate/extent leaf directly with the actual pile, avoiding vtable hooks.
    // Without extents57b770 accepts the bounding rectangle.
    using Occupies=bool (*)(df::building_stockpilest*,int16_t,int16_t,int16_t);
    const auto occupies=reinterpret_cast<Occupies>(base+0x5587b0);
    int32_t count=0;
    for(int32_t y=pile.y1;y<=pile.y2;++y)for(int32_t x=pile.x1;x<=pile.x2;++x)
        count+=!pile.room.extents || occupies(&pile,int16_t(x),int16_t(y),int16_t(pile.z));
    return count;
}
bool nativeStockpileCreateReady() {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return false;
    static const bool compatible=supported(base) &&
        hash(base+0x30f090,0x23)==0x31e45e8c88a50ff0ULL &&
        hash(base+0x30f0d0,0xff)==0xcac520928ecc2d91ULL &&
        hash(base+0x54bb60,0x110)==0xad02785ff295fa9bULL &&
        hash(base+0x577040,0x3500)==0x758911d1932d14dbULL &&
        hash(base+0x57d930,0x2d)==0x81ea0ddf18781ceaULL;
    return compatible;
}
df::building_stockpilest* nativeStockpileAllocate() {
    if(!df::global::world || !nativeStockpileCreateReady())return nullptr;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Allocate=df::building_stockpilest* (*)();
    return reinterpret_cast<Allocate>(base+0x30f090)();
}
bool nativeStockpileComplete(df::building_stockpilest& pile) {
    if(!nativeStockpileCreateReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Complete=void (*)(df::building*,bool);
    reinterpret_cast<Complete>(base+0x577040)(&pile,true);
    pile.categorize(true);
    return true;
}
bool nativeStockpileTransferReady() {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return false;
    static const bool compatible=supported(base) &&
        hash(base+0xa82b00,0x107)==0x8e125972b5fb4fffULL &&
        hash(base+0x5587b0,0x79)==0x14b4f3f138690067ULL &&
        hash(base+0x587d80,0xc98)==0x0f7410a976032a15ULL &&
        hash(base+0x586ac0,0x205)==0x963ec0e2ff50cf12ULL &&
        hash(base+0x558550,0x13b)==0x60e1b99a5ab1f65dULL &&
        hash(base+0x5a78e0,0xce)==0x3d9bdaeb35702e06ULL &&
        hash(base+0x5873c0,0x130)==0x80766a7707ce5493ULL;
    return compatible;
}
std::optional<df::building_stockpilest*> nativeStockpileAt(int16_t x,int16_t y,int16_t z) {
    if(!df::global::world || !nativeStockpileTransferReady())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Find=df::building* (*)(int16_t,int16_t,int16_t);
    auto* owner=reinterpret_cast<Find>(base+0xa82b00)(x,y,z);
    return owner && owner->getType()==df::building_type::Stockpile ?
        static_cast<df::building_stockpilest*>(owner):nullptr;
}
bool nativeStockpileRemoveEmpty(df::building_stockpilest& pile) {
    if(!nativeStockpileTransferReady())return false;
    const auto count=nativeStockpileTileCount(pile);
    if(!count || *count)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Native354720 supplies false for destroy-items, insanify and damage.
    // The semantic destructor owns assignments, relationships and registration;
    // its generic selected-building cleanup is an effect, never a paint input.
    using Remove=void (*)(df::building*,bool,bool,bool);
    reinterpret_cast<Remove>(base+0x587d80)(&pile,false,false,false);
    return true;
}
bool nativeStockpileRepaintReady(df::building_stockpilest& pile) {
    const auto& storage=pile.storage;
    const size_t count=storage.container_item_id.size();
    if(count>32768 || storage.container_type.size()!=count ||
       storage.container_x.size()!=count || storage.container_y.size()!=count)return false;
    return nativeStockpileTileCount(pile).has_value();
}
bool nativeStockpileRepaintCleanup(df::building_stockpilest& pile) {
    const size_t entries=pile.storage.container_item_id.size();
    if(entries>32768 || pile.storage.container_type.size()!=entries ||
       pile.storage.container_x.size()!=entries || pile.storage.container_y.size()!=entries)return false;
    const auto count=nativeStockpileTileCount(pile);
    if(!count)return false;
    // Native3546ee..35472b retains the active empty pile, including assignments
    // and limits. Its interaction owner decides whether to regrow or remove it.
    if(!*count)return true;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Occupies=bool (*)(df::building_stockpilest*,int16_t,int16_t,int16_t);
    const auto occupies=reinterpret_cast<Occupies>(base+0x5587b0);
    auto& storage=pile.storage;
    // Native354817..354943 removes all four parallel entries in reverse order.
    // removeStockpileAssignment only clears the item; detachStockpileAssignment
    // also changes these vectors and would invalidate this traversal.
    for(size_t index=storage.container_item_id.size();index-->0;) {
        if(occupies(&pile,storage.container_x[index],storage.container_y[index],int16_t(pile.z)))continue;
        if(auto* item=df::item::find(storage.container_item_id[index]))item->removeStockpileAssignment();
        storage.container_type.erase(storage.container_type.begin()+index);
        storage.container_item_id.erase(storage.container_item_id.begin()+index);
        storage.container_x.erase(storage.container_x.begin()+index);
        storage.container_y.erase(storage.container_y.begin()+index);
    }
    // This clamp is inline in DF354a29..354acf, not a standalone entry point.
    // Count and assignment eligibility above come from DF's native predicate.
    const auto limit=static_cast<int16_t>(*count);
    storage.max_barrels=(std::min)(storage.max_barrels,limit);
    storage.max_bins=(std::min)(storage.max_bins,limit);
    storage.max_wheelbarrows=(std::min)(storage.max_wheelbarrows,limit);
    return true;
}
std::optional<std::array<int16_t,3>> nativeStockpilePresetContainers(
    df::building_stockpilest& pile,int preset) {
    if(preset<1 || preset>19)return std::nullopt;
    const auto observed=nativeStockpileTileCount(pile);
    if(!observed)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=hash(base+0x34a8d4,0x141)==0x444c389c4f7878d4ULL &&
        hash(base+0x35f0b8,0x4c)==0xf5f32f7dfd8f6deeULL;
    if(!compatible)return std::nullopt;
    const auto count=*observed;
    std::array<int16_t,3> limits{};
    // The inline native dispatch34a8d4..34aa15 follows the settings initializer.
    // Narrowing matches native int16 storage, including oversized native piles.
    if(preset==1)limits={int16_t(count/2),int16_t((count+1)/2),1};
    else if(preset==3)limits[0]=int16_t(count);
    else if(preset==7)limits[2]=1;
    else if((preset>=8 && preset<=14) || (preset>=16 && preset<=18))limits[1]=int16_t(count);
    return limits;
}
std::optional<df::stockpile_settings> nativeStockpilePreset(
    const df::stockpile_settings& source,int preset) {
    if(!df::global::world || preset<1 || preset>19)return std::nullopt;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=supported(base);
    if(!compatible)return std::nullopt;
    static_assert(sizeof(df::stockpile_settings)==0x7e0);
    // Wire order is category-bit order; native stockpile_list includes Ore at6.
    // Native All=19 and None=-1. The UI call site is34a77f/34a7aa.
    static constexpr int16_t modes[]={19,0,1,2,3,4,5,7,8,9,10,11,12,13,14,15,16,17,-1};
    auto owned=source;
    using Clear=void (*)(df::stockpile_settings*);
    using Initialize=void (*)(df::stockpile_settings*,int16_t);
    reinterpret_cast<Clear>(base+0x30e950)(&owned);
    reinterpret_cast<Initialize>(base+0x30dde0)(&owned,modes[preset-1]);
    return owned;
}
std::optional<df::stockpile_settings> nativeStockpileInitialSettings(uint32_t categories) {
    if(categories&~uint32_t(0x1ffff))return std::nullopt;
    // DF's stockpile constructor30f0d0 calls30d790: empty vectors/flags and
    // both misc allowances true. Generated defaults retain those allowances;
    // inactive fixed switches remain initialized instead of reading spare bytes.
    df::stockpile_settings initial;
    auto owned=nativeStockpilePreset(initial,19);
    if(!owned)return std::nullopt;
    using Initialize=void (*)(df::stockpile_settings*,uint32_t);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    reinterpret_cast<Initialize>(base+0x30e070)(&*owned,categories);
    return owned;
}
std::optional<df::stockpile_settings> nativeStockpileCategory(
    const df::stockpile_settings& source,uint32_t category) {
    if(!df::global::world || !category || (category&(category-1)) ||
       (category&~uint32_t(0x1ffff)))return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=supported(base) &&
        hash(base+0x30d350,0x440)==0xf4c028803a3e2f1dULL &&
        hash(base+0x35fdde,0x192)==0x2a2bc478f013cef1ULL;
    if(!compatible)return std::nullopt;
    auto owned=source;
    if(owned.flags.whole&category)return owned;
    using Initialize=void (*)(df::stockpile_settings*,uint32_t);
    reinterpret_cast<Initialize>(base+0x30e070)(&owned,category);
    // Category-selection prelude35fdde..35ff70. Every clear helper only writes
    // its supplied category. Shared default helpers are checked by supported().
    size_t index=0;while((uint32_t(1)<<index)!=category)++index;
    categoryHeader(base,owned,index,false);
    return owned;
}
std::optional<df::stockpile_settings> nativeStockpileHeader(
    const df::stockpile_settings& source,uint32_t category,bool enabled) {
    if(!df::global::world || (category&(category-1)) || (category&~uint32_t(0x1ffff)))return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=supported(base) &&
        hash(base+0x30d300,0x490)==0xee34eefa6f163a9bULL &&
        hash(base+0x3272e3,0x9fd)==0x7f51c1989311fa8dULL;
    if(!compatible)return std::nullopt;
    auto owned=source;
    if(category) {
        size_t index=0;while((uint32_t(1)<<index)!=category)++index;
        categoryHeader(base,owned,index,enabled);
    } else if(enabled) {
        // Global All calls the initializer directly, unlike a preset. In
        // particular existing Refuse/Corpses settings are not cleared first.
        using Initialize=void (*)(df::stockpile_settings*,int16_t);
        reinterpret_cast<Initialize>(base+0x30dde0)(&owned,19);
    } else {
        // Global None clears all category contents, retaining flags and misc.
        for(size_t index=0;index<17;++index)categoryHeader(base,owned,index,false);
    }
    return owned;
}
static bool nativeListCompatible(const uint8_t* base) {
    return supported(base) &&
        hash(base+0x14d16f0,0x91)==0x38ac9ecba29364f4ULL &&
        hash(base+0x14d7f0,0x5a)==0xdfbefbe76328d1c2ULL &&
        hash(base+0x14d850,0x22)==0xcc724b0919b345caULL &&
        hash(base+0x145b740,0x37)==0xc69a243bb9df4070ULL &&
        hash(base+0x6b8af0,0x96)==0x8f67f7a1b9d42698ULL &&
        hash(base+0x6f370,0xc)==0xe8009075ae23e49bULL &&
        hash(base+0x6f450,0xb)==0xab3f98567ea8847dULL &&
        hash(base+0x67e30,0x5)==0xa06f937403b4a5fdULL &&
        hash(base+0xd669f0,0x65)==0xfdd633716041814fULL &&
        hash(base+0x701e70,0x20e)==0xead0193006374e44ULL &&
        hash(base+0x701db0,0xba)==0x8fd2bf0e939933fcULL &&
        hash(base+0xa64cb0,0x45)==0x929e553cfe3f9c62ULL &&
        hash(base+0xa64d00,0x79)==0x82e1b1bb161f88d0ULL &&
        hash(base+0xf2680,0x54)==0xcaef8a6056b8eef2ULL &&
        hash(base+0x6ee00,0x8)==0x45953a731d07973cULL &&
        hash(base+0x6ee10,0x4)==0xcbb562da69740364ULL &&
        hash(base+0x6ee20,0x24)==0xc11133a82be341f7ULL &&
        hash(base+0x6ee50,0xc)==0xe8047875ae27a4aaULL &&
        hash(base+0x6f230,0xb)==0x902c1224d06de7deULL &&
        hash(base+0x6f240,0xa)==0xff5fd01446b306acULL &&
        hash(base+0x657b0,0x7)==0x8ed7b69d3403667eULL &&
        hash(base+0x6f580,0x1f)==0xdfeca05eb6f047a9ULL &&
        hash(base+0xa82c10,0x56ec)==0x66347214dfd39a0bULL &&
        hash(base+0x14d1790,0x181)==0x4a5b855077250003ULL &&
        hash(base+0x724a30,0xd9)==0x5121a9264bd432feULL &&
        hash(base+0x1f9bd0,0x8c)==0xe9d8573a55300bd7ULL &&
        hash(base+0x6f530,0x2d)==0xc2a3fd308b4fc92eULL &&
        hash(base+0x14d1920,0x459)==0xf48e28715360ed9aULL &&
        hash(base+0x14add70,0x12f)==0x1f897b15772d540ULL &&
        hash(base+0x145bee0,0x5e)==0x6abc4e374e372eefULL &&
        hash(base+0x14e1ec0,0xb68)==0x1d38184423ba8a35ULL &&
        hash(base+0x6f850,0x5f)==0x5ab94e1bc2548275ULL &&
        hash(base+0xb9b80,0x144)==0x91ddb6c319015f9bULL &&
        hash(base+0x707d0,0x59)==0xeaa671999c0fd514ULL &&
        hash(base+0x681f0,0xb8)==0x84219afebe998ea0ULL &&
        hash(base+0x68150,0x37)==0xffedcb68657803eaULL &&
        hash(base+0x35fd70,0x77f0)==0x9826ec82d86ebf51ULL &&
        hash(base+0x35fb50,0x188)==0x0370358adf30598bULL &&
        hash(base+0x35fce0,0x89)==0x60a96499876e0c98ULL &&
        hash(base+0x14d880,0x5a)==0x4aa033209ea95fd2ULL &&
        hash(base+0x144d90,0xba)==0x97aed5d23117e68fULL &&
        hash(base+0x52d650,0x2b0)==0xcf43211ff8e2c344ULL &&
        hash(base+0x52cee0,0x19e)==0xc25c2d8a6eb9fcacULL &&
        hash(base+0x3bc400,0x14d)==0x038c68edadcc2b69ULL &&
        hash(base+0x2240f0,0x8)==0x4bfd67e9e540ffc4ULL &&
        hash(base+0x1b9fa0,0x7)==0xa88a5a439c83b069ULL &&
        hash(base+0x6f520,0x3d)==0xaceb003bf538dbfcULL &&
        hash(base+0x6f290,0xe)==0x0b4b5eed70e95db6ULL &&
        hash(base+0x6f220,0x8)==0x2bba791d9cd7ac1dULL &&
        hash(base+0x6f5d0,0xc0)==0xd7cc734d277fe129ULL &&
        hash(base+0x6f560,0x20)==0xd0ebc9e82e46ffe8ULL &&
        hash(base+0xb9d10,0x13)==0x5ad8171f894aa0c8ULL &&
        hash(base+0x6f690,0x1d)==0x53c89dc946758be9ULL &&
        hash(base+0x6fa10,0x161)==0xdf2151da834b95e7ULL &&
        hash(base+0xe35c0,0x66)==0xab8dd56de421fbe9ULL &&
        hash(base+0xaa3bd0,0x1c3)==0xf9cd818efc6bad8ULL &&
        hash(base+0x256880,0xa7)==0xbe498be3e4e4a895ULL &&
        hash(base+0x6f8d0,0x10d)==0xcc29ed917c3d3bf4ULL &&
        hash(base+0x3c6a70,0x1d)==0x71d2ae7fe2bf2ddbULL &&
        hash(base+0x13bbf0,0x1e)==0x1bd597972a2ba0eULL &&
        hash(base+0x6f410,0x1d)==0xc4deaa9fd6b78e02ULL &&
        hash(base+0x287020,0x15b)==0xc5cbef45bac88ad3ULL &&
        hash(base+0x70bd0,0x15c)==0x4f81ccfaa39439f5ULL &&
        hash(base+0x70e20,0x117)==0x9aba69f846f6c10ULL &&
        hash(base+0x71830,0x88)==0x929730bf6bcaccccULL;
}
std::optional<NativeStockpileSummaries> nativeStockpileSummaries(
    const df::stockpile_settings& source,uint32_t categories) {
    if(!df::global::world || categories>0x1ffff)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    // DF's renderer calls55a6d0 for sublist state:0 none,1 mixed,2 all.
    // The entire dispatch table is fingerprinted with the routine. Its only
    // writes are local strings/stack; all material calls use inorganic type0.
    static const bool compatible=nativeListCompatible(base) &&
        hash(base+0x55a6d0,0x3934)==0xe8325494fbb505ecULL &&
        hash(base+0x6b8af0,0x96)==0x8f67f7a1b9d42698ULL;
    if(!compatible)return std::nullopt;
    auto owned=source;
    if(!(categories&0x1))owned.animals={};
    if(!(categories&0x2))owned.food={};
    if(!(categories&0x4))owned.furniture={};
    if(!(categories&0x8))owned.corpses={};
    if(!(categories&0x10))owned.refuse={};
    if(!(categories&0x20))owned.stone={};
    if(!(categories&0x40))owned.ammo={};
    if(!(categories&0x80))owned.coins={};
    if(!(categories&0x100))owned.bars_blocks={};
    if(!(categories&0x200))owned.gems={};
    if(!(categories&0x400))owned.finished_goods={};
    if(!(categories&0x800))owned.leather={};
    if(!(categories&0x1000))owned.cloth={};
    if(!(categories&0x2000))owned.wood={};
    if(!(categories&0x4000))owned.weapons={};
    if(!(categories&0x8000))owned.armor={};
    if(!(categories&0x10000))owned.sheet={};
    const auto& raws=df::global::world->raws;
    // Native bounds checks permit stale vector tails, but referenced raw
    // pointers and Plants' parallel organic index array are unchecked.
    const size_t creatures=(std::max)({owned.animals.enabled.size(),owned.corpses.corpses.size(),
        owned.refuse.corpses.size(),owned.refuse.body_parts.size(),owned.refuse.skulls.size(),
        owned.refuse.bones.size(),owned.refuse.shells.size(),owned.refuse.teeth.size(),
        owned.refuse.horns.size(),owned.refuse.hair.size()});
    for(size_t i=0;i<creatures && i<raws.creatures.all.size() && i<32768;++i)
        if(!raws.creatures.all[i])return std::nullopt;
    for(size_t i=0;i<owned.wood.mats.size() && i<raws.plants.all.size();++i)
        if(!raws.plants.all[i])return std::nullopt;
    const auto& types=raws.mat_table.organic_types[4];
    const auto& indexes=raws.mat_table.organic_indexes[4];
    const auto count=(std::min)(owned.food.plants.size(),types.size());
    if(indexes.size()<count)return std::nullopt;
    for(size_t i=0;i<count;++i)if(types[i]>=419 && types[i]<=618 && indexes[i]>=0 &&
        size_t(indexes[i])<raws.plants.all.size() && !raws.plants.all[indexes[i]])return std::nullopt;
    const size_t inorganic=(std::max)({owned.furniture.mats.size(),owned.stone.mats.size(),
        owned.ammo.mats.size(),owned.coins.mats.size(),owned.bars_blocks.bars_mats.size(),
        owned.bars_blocks.blocks_mats.size(),owned.gems.rough_mats.size(),owned.gems.cut_mats.size(),
        owned.finished_goods.mats.size(),owned.weapons.mats.size(),owned.armor.mats.size()});
    for(size_t i=0;i<inorganic && i<raws.inorganics.all.size();++i) {
        const auto* raw=raws.inorganics.all[i];if(!raw)return std::nullopt;
        if(i<owned.stone.mats.size())for(const auto* id:raw->material.reaction_product.id)
            if(!id)return std::nullopt;
    }
    // Native glass summary reads fixed slots3..5 without checking length.
    // A missing slot has no defined native summary; reject instead of reading
    // past storage or inventing a selected state. Ordinary vector tails remain.
    if((categories&0x200) && (owned.gems.rough_other_mats.size()<6 || owned.gems.cut_other_mats.size()<6))
        return std::nullopt;
    // The enum dispatches also read fixed slots without checking vector size:
    // Refuse's highest selected index is92; Finished goods' is89.
    if((categories&0x10) && owned.refuse.type.size()<93)return std::nullopt;
    if((categories&0x400) && owned.finished_goods.type.size()<90)return std::nullopt;
    NativeStockpileSummaries result;
    using Summarize=uint8_t (*)(df::stockpile_settings*,int32_t);
    const auto summarize=reinterpret_cast<Summarize>(base+0x55a6d0);
    static constexpr int first[]={0,2,22,28,30,40,45,50,52,58,64,73,76,85,87,95,107};
    static constexpr int last[] ={0,20,27,28,38,43,49,50,56,62,71,74,84,85,93,105,108};
    for(size_t category=0;category<17;++category) {
        const uint32_t bit=1u<<category;if(!(categories&bit))continue;
        bool on=false,off=false;
        const auto include=[&](uint8_t state) {on|=state!=0;off|=state!=2;};
        for(int mode=first[category];mode<=last[category];++mode) {
            const auto state=summarize(&owned,mode);if(state>2)return std::nullopt;
            result.states[mode]=state;
            // Native renderer37ebc6/37ec92 omits these two empty Food vectors
            // from the category aggregate; other empty lists contribute none.
            if(mode==9 && owned.food.cheese_plant.empty())continue;
            if(mode==14 && owned.food.powder_creature.empty())continue;
            include(state);
        }
        // Renderer37e9de..37facd combines these scalar controls with the native
        // sublist states. Dyed/undyed controls do not participate in root state.
        const auto scalar=[&](bool value) {include(value?2:0);};
        switch(category) {
          case 0:scalar(owned.animals.empty_cages);scalar(owned.animals.empty_traps);break;
          case 1:scalar(owned.food.prepared_meals);break;
          case 4:scalar(owned.refuse.fresh_raw_hide);scalar(owned.refuse.rotten_raw_hide);break;
          case 14:scalar(owned.weapons.usable);scalar(owned.weapons.unusable);break;
          case 15:scalar(owned.armor.usable);scalar(owned.armor.unusable);break;
          default:break;
        }
        result.categories[category]=(source.flags.whole&bit) && on ? (off?1:2) : 0;
    }
    return result;
}
std::optional<std::vector<NativeStockpileRow>> nativeStockpileRows(
    df::stockpile_settings& owned,int mode,const std::string& filter,
    const std::vector<NativeStockpileSettingRange>& ranges) {
    if(!df::global::world || filter.size()>256)return std::nullopt;
    // Category entry recursively builds its initial leaf, then performs the
    // native parent sort/filter pass. Validate that leaf's input domain while
    // passing the original mode to independently owned native scratch.
    const int buildMode=mode;
    switch(mode) {
      case 1:mode=2;break;
      case 21:mode=22;break;
      case 29:mode=30;break;
      case 39:mode=40;break;
      case 44:mode=45;break;
      case 51:mode=52;break;
      case 57:mode=60;break;
      case 63:mode=64;break;
      case 72:mode=73;break;
      case 75:mode=76;break;
      case 86:mode=87;break;
      case 94:mode=95;break;
      case 106:mode=107;break;
      default:break;
    }
    // Inorganic branches pass material type0, state0 and flags0 to14d1920;
    // bounds-checked14add70 reads raws/fallback material without historical lookup.
    // Gems use type0 plural formatting; glass uses builtin types3..5/index-1.
    // These branches have no historical-cache path. Color branches copy raw
    // descriptor names; constant branches use native labels and owned settings.
    switch(mode) {
      case 23:case 24:case 47:case 50:case 52:case 54:case 55:
      case 65:case 66:case 67:case 89:case 90:case 101:break;
      case 58:case 59:case 60:case 61:case 62:break;
      case 40:case 41:case 42:case 43:break;
      case 2:case 3:case 4:case 5:case 6:case 7:case 8:case 9:case 10:case 11:case 12:case 13:case 14:case 15:case 16:case 17:case 18:case 19:case 20:case 73:case 76:case 77:case 78:case 79:case 80:case 81:case 82:case 83:case 107:case 108:break;
      case 22:case 30:case 64:break;
      case 85:case 26:case 27:case 48:case 49:case 69:case 70:
      case 92:case 93:case 103:case 104:break;
      case 25:case 46:case 53:case 56:case 68:case 91:case 102:break;
      case 71:case 74:case 84:case 105:break;
      case 0:case 28:case 31:case 32:case 33:case 34:case 35:case 36:case 37:case 38:break;
      case 45:case 87:case 88:case 95:case 96:case 97:case 98:case 99:case 100:break;
      default:return std::nullopt;
    }
    // Typed raw branches index by stored settings length through an unchecked
    // native getter. Reject stale or missing raws before entry; preserve short
    // and empty settings instead of expanding them to the current raw count.
    const auto fits=[](const auto& values,const auto& raws) {
        if(values.size()>raws.size())return false;
        for(size_t i=0;i<values.size();++i)if(!raws[i])return false;
        return true;
    };
    const auto& raws=df::global::world->raws;
    const std::vector<char>* organic=nullptr;int organicCategory=-1;
    switch(mode) {
      case 2:organic=&owned.food.meat;organicCategory=0;break;
      case 3:organic=&owned.food.fish;organicCategory=1;break;
      case 4:organic=&owned.food.unprepared_fish;organicCategory=2;break;
      case 5:organic=&owned.food.egg;organicCategory=3;break;
      case 6:organic=&owned.food.plants;organicCategory=4;break;
      case 7:organic=&owned.food.drink_plant;organicCategory=5;break;
      case 8:organic=&owned.food.drink_animal;organicCategory=6;break;
      case 9:organic=&owned.food.cheese_plant;organicCategory=7;break;
      case 10:organic=&owned.food.cheese_animal;organicCategory=8;break;
      case 11:organic=&owned.food.seeds;organicCategory=9;break;
      case 12:organic=&owned.food.leaves;organicCategory=10;break;
      case 13:organic=&owned.food.powder_plant;organicCategory=11;break;
      case 14:organic=&owned.food.powder_creature;organicCategory=12;break;
      case 15:organic=&owned.food.glob;organicCategory=13;break;
      case 16:organic=&owned.food.glob_paste;organicCategory=33;break;
      case 17:organic=&owned.food.glob_pressed;organicCategory=34;break;
      case 18:organic=&owned.food.liquid_plant;organicCategory=14;break;
      case 19:organic=&owned.food.liquid_animal;organicCategory=15;break;
      case 20:organic=&owned.food.liquid_misc;organicCategory=16;break;
      case 73:organic=&owned.leather.mats;organicCategory=17;break;
      case 76:organic=&owned.cloth.thread_silk;organicCategory=18;break;
      case 77:organic=&owned.cloth.thread_plant;organicCategory=19;break;
      case 78:organic=&owned.cloth.thread_yarn;organicCategory=35;break;
      case 79:organic=&owned.cloth.thread_metal;organicCategory=36;break;
      case 80:organic=&owned.cloth.cloth_silk;organicCategory=18;break;
      case 81:organic=&owned.cloth.cloth_plant;organicCategory=19;break;
      case 82:organic=&owned.cloth.cloth_yarn;organicCategory=35;break;
      case 83:organic=&owned.cloth.cloth_metal;organicCategory=36;break;
      case 107:organic=&owned.sheet.paper;organicCategory=37;break;
      case 108:organic=&owned.sheet.parchment;organicCategory=38;break;
    }
    if(organic) {
        const auto& types=raws.mat_table.organic_types[organicCategory];
        const auto& indexes=raws.mat_table.organic_indexes[organicCategory];
        // Native d669f0 bounds only types; the paired index read is unchecked.
        const size_t used=(std::min)(organic->size(),types.size());
        if(indexes.size()<used)return std::nullopt;
        const auto creatureExists=[&](int32_t index) {
            return index<0 || size_t(index)>=raws.creatures.all.size() || raws.creatures.all[index];
        };
        for(size_t i=0;i<used;++i) {
            const int16_t type=types[i];const int32_t index=indexes[i];
            if(type==-1)continue;
            if(mode==3 || mode==4 || mode==5) {
                // These tables encode creature/caste, not material identity.
                if(!creatureExists(type))return std::nullopt;
                if(type>=0 && size_t(type)<raws.creatures.all.size()) {
                    const auto& castes=raws.creatures.all[type]->caste;
                    const int16_t caste=int16_t(index);
                    if(caste>=0 && size_t(caste)<castes.size() && !castes[caste])return std::nullopt;
                }
                continue;
            }
            // Historical material resolution can write DF's derived cache.
            // No runtime fallback may borrow that cache or native menu state.
            if(type>=219 && type<=418)return std::nullopt;
            if(type>=19 && type<=218) {
                if(!creatureExists(index))return std::nullopt;
                if(mode==2 && !creatureExists(int16_t(index)))return std::nullopt;
            }
            if(type>=419 && type<=618 && index>=0 && size_t(index)<raws.plants.all.size()) {
                const auto* plant=raws.plants.all[index];
                if(!plant)return std::nullopt;
                if(mode==12)for(const auto* growth:plant->growths)if(!growth)return std::nullopt;
            }
        }
    }
    // Stone's raw getter skips missing/stale indices. Its fired-material
    // predicate scans string pointers in reaction products without null checks.
    if(mode==42 || mode==43)
        for(size_t i=0;i<owned.stone.mats.size() && i<raws.inorganics.all.size();++i)
            if(const auto* raw=raws.inorganics.all[i])
                for(const auto* id:raw->material.reaction_product.id)if(!id)return std::nullopt;
    // Wood's int32 getter skips out-of-range indices, including stale tails.
    // A referenced in-range raw must still exist before entering native code.
    if(mode==85)for(size_t i=0;i<owned.wood.mats.size() && i<raws.plants.all.size();++i)
        if(!raws.plants.all[i])return std::nullopt;
    if(mode==22 || mode==30 || mode==64) {
        // Formatter subtype -1 must not match a loaded item definition. These
        // branches scan raw vectors even when no subtype was requested.
        const auto validTypes=[](const auto& values) {
            for(const auto* raw:values)if(!raw || raw->subtype<0)return false;
            return true;
        };
        const auto& d=raws.itemdefs;
        if(!validTypes(d.instruments) || !validTypes(d.toys) || !validTypes(d.tools) ||
           !validTypes(d.weapons) || !validTypes(d.ammo) || !validTypes(d.siege_ammo) ||
           !validTypes(d.armor) || !validTypes(d.gloves) || !validTypes(d.shields) ||
           !validTypes(d.shoes) || !validTypes(d.helms) || !validTypes(d.pants))return std::nullopt;
    }
    bool valid=true;
    switch(mode) {
      case 71:valid=fits(owned.finished_goods.color,raws.descriptors.colors);break;
      case 74:valid=fits(owned.leather.color,raws.descriptors.colors);break;
      case 84:valid=fits(owned.cloth.color,raws.descriptors.colors);break;
      case 105:valid=fits(owned.armor.color,raws.descriptors.colors);break;
      case 45:valid=fits(owned.ammo.type,raws.itemdefs.ammo);break;
      case 87:valid=fits(owned.weapons.weapon_type,raws.itemdefs.weapons);break;
      case 88:valid=fits(owned.weapons.trapcomp_type,raws.itemdefs.trapcomps);break;
      case 95:valid=fits(owned.armor.body,raws.itemdefs.armor);break;
      case 96:valid=fits(owned.armor.head,raws.itemdefs.helms);break;
      case 97:valid=fits(owned.armor.feet,raws.itemdefs.shoes);break;
      case 98:valid=fits(owned.armor.hands,raws.itemdefs.gloves);break;
      case 99:valid=fits(owned.armor.legs,raws.itemdefs.pants);break;
      case 100:valid=fits(owned.armor.shield,raws.itemdefs.shields);break;
    }
    // Creature helpers perform their own signed-16-bit index bounds checks.
    // Preserve their behavior for stale tails; reject only null raws that a
    // valid native index would dereference. No raw-count resizing is allowed.
    const std::vector<char>* creatures=nullptr;
    switch(mode) {
      case 0:creatures=&owned.animals.enabled;break;
      case 28:creatures=&owned.corpses.corpses;break;
      case 31:creatures=&owned.refuse.corpses;break;
      case 32:creatures=&owned.refuse.body_parts;break;
      case 33:creatures=&owned.refuse.skulls;break;
      case 34:creatures=&owned.refuse.bones;break;
      case 35:creatures=&owned.refuse.shells;break;
      case 36:creatures=&owned.refuse.teeth;break;
      case 37:creatures=&owned.refuse.horns;break;
      case 38:creatures=&owned.refuse.hair;break;
    }
    if(creatures)for(size_t i=0;i<creatures->size() && i<raws.creatures.all.size() && i<32768;++i)
        if(!raws.creatures.all[i])return std::nullopt;
    if(!valid)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=nativeListCompatible(base);
    if(!compatible)return std::nullopt;
    static_assert(sizeof(df::custom_stockpile_interfacest)==0xf8);
    static_assert(sizeof(df::custom_stockpile_itemst)==0x60);
    static_assert(sizeof(bool)==1); // Fixed settings ranges use byte indices.
    // Fixed enum branches assume full storage. Supply it only in owned scratch,
    // restore the caller's vector afterwards, and omit padded rows from output.
    struct IndexedBacking {
        std::vector<char>* target=nullptr;
        std::vector<char> saved;
        ~IndexedBacking(){if(target)target->swap(saved);}
    } backing;
    auto localRanges=ranges;
    size_t stored=0;const char* padded=nullptr;size_t paddedCount=0;
    std::vector<char>* types=nullptr;const char* typeField=nullptr;size_t required=0;
    if(mode==22){types=&owned.furniture.type;typeField="furniture.type";required=35;}
    if(mode==30){types=&owned.refuse.type;typeField="refuse.type";required=93;}
    if(mode==64){types=&owned.finished_goods.type;typeField="finished_goods.type";required=93;}
    // Glass loops over builtins but only emits the three glass slots3..5.
    if(mode==58){types=&owned.gems.rough_other_mats;typeField="gems.rough_other_mats";required=6;}
    if(mode==59){types=&owned.gems.cut_other_mats;typeField="gems.cut_other_mats";required=6;}
    if(types && types->size()<required) {
        stored=types->size();backing.saved=*types;backing.saved.resize(required,0);
        backing.target=types;types->swap(backing.saved);
        padded=types->data();paddedCount=types->size();
        bool found=false;
        for(auto& range:localRanges)if(range.field==typeField) {
            if(found || range.count!=stored)return std::nullopt;
            found=true;range.begin=padded;
        }
        if(!found)return std::nullopt;
    }
    struct Rows {
        df::custom_stockpile_interfacest scratch;
        ~Rows(){for(auto* row:scratch.spec_item)delete row;}
    } rows;
    rows.scratch.sp=&owned;
    rows.scratch.spec_filter=filter;
    // Wood reads TREE flags/plural names. Quality branches read fixed labels and
    // preserve native quality order. Flag0 skips category activation.
    // Never call open-wrapper35f3c0, which writes global UI/graphics state.
    using Build=void (*)(df::custom_stockpile_interfacest*,int32_t,uint32_t);
    reinterpret_cast<Build>(base+0x35fd70)(&rows.scratch,buildMode,0);
    if(rows.scratch.cur_spec_item_sz<0 ||
       size_t(rows.scratch.cur_spec_item_sz)>rows.scratch.spec_item.size())return std::nullopt;
    std::vector<NativeStockpileRow> result;
    result.reserve(rows.scratch.cur_spec_item_sz);
    for(int32_t i=0;i<rows.scratch.cur_spec_item_sz;++i) {
        const auto* row=rows.scratch.spec_item[i];
        if(!row)return std::nullopt;
        const auto pointer=reinterpret_cast<uintptr_t>(row->set_pointer);
        const NativeStockpileSettingRange* matched=nullptr;size_t index=0;
        if(padded) {
            const auto start=reinterpret_cast<uintptr_t>(padded);
            if(pointer>=start && pointer-start>=stored && pointer-start<paddedCount)continue;
        }
        for(const auto& range:localRanges) {
            const auto start=reinterpret_cast<uintptr_t>(range.begin);
            if(pointer>=start && pointer-start<range.count) {
                if(matched)return std::nullopt;
                matched=&range;index=size_t(pointer-start);
            }
        }
        if(!matched)return std::nullopt;
        result.push_back({index,row->name,*row->set_pointer!=0,row->on,matched->field});
    }
    return result;
}
std::optional<df::building*> nativeStockpileLinkTarget(df::building_stockpilest& source,
    int16_t x,int16_t y,int16_t z,bool give) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!df::global::world || !base || !supported(base))return std::nullopt;
    static const bool compatible=hash(base+0x5587b0,0x79)==0x14b4f3f138690067ULL &&
        hash(base+0x3c9ff0,0x9c)==0xabd985a880f5b6dcULL;
    if(!compatible)return std::nullopt;
    const auto& piles=give?source.links.give_to_pile:source.links.take_from_pile;
    const auto& workshops=give?source.links.give_to_workshop:source.links.take_from_workshop;
    if(!validStockpileLinkVector(piles,source.id) || !validStockpileLinkVector(workshops,source.id))return std::nullopt;
    using Contains=uint8_t (*)(df::building*,int16_t,int16_t,int16_t);
    using Find=int32_t (*)(int32_t,const void*);
    const auto contains=reinterpret_cast<Contains>(base+0x5587b0);
    const auto find=reinterpret_cast<Find>(base+0x3c9ff0);
    const auto occupies=[&](df::building* candidate) {
        if(candidate->id==source.id || !candidate->isSettingOccupancy() || candidate->z!=z)return false;
        if(candidate->isExtentShaped() && candidate->room.extents)
            return contains(candidate,x,y,z)!=0;
        return x>=candidate->x1 && x<=candidate->x2 && y>=candidate->y1 && y<=candidate->y2;
    };
    // Native3c2d14..3c3179: forward STOCKPILE pass, then forward IN_PLAY.
    // Unlike generic nativeStockpileAt, duplicates are skipped and the search
    // continues to another overlapping candidate. No link UI object is used.
    for(auto* candidate:df::global::world->buildings.other.STOCKPILE) {
        if(!candidate)return std::nullopt;
        if(occupies(candidate) && find(candidate->id,&piles)<0)return candidate;
    }
    for(auto* candidate:df::global::world->buildings.other.IN_PLAY) {
        if(!candidate)return std::nullopt;
        if(candidate->canLinkToStockpile() && occupies(candidate) && find(candidate->id,&workshops)<0)return candidate;
    }
    return static_cast<df::building*>(nullptr);
}
std::optional<bool> nativeStockpileLink(df::building& source,
    df::building_stockpilest& target,bool give,bool unlink) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base || !supported(base))return std::nullopt;
    static const bool compatible=hash(base+0xeb530,0xf8)==0xa72ce23f0725e6b0ULL &&
        hash(base+0x3c7390,0xba)==0xa5fdb7ea529d8904ULL &&
        hash(base+0x3c9ff0,0x9c)==0xabd985a880f5b6dcULL;
    if(!compatible || source.id==target.id)return std::nullopt;
    auto* original=source.getStockpileLinks();
    if(!original)return std::nullopt;
    const auto validLinks=[&](const auto& links,int32_t ownerId) {
        return validStockpileLinkVector(links.give_to_pile,ownerId) && validStockpileLinkVector(links.take_from_pile,ownerId) &&
            validStockpileLinkVector(links.give_to_workshop,ownerId) && validStockpileLinkVector(links.take_from_workshop,ownerId);
    };
    if(!validLinks(*original,source.id) || !validLinks(target.links,target.id))return std::nullopt;
    using Find=int32_t (*)(int32_t,const void*);
    using Insert=int32_t (*)(df::building*,void*);
    using Erase=void (*)(df::building*,void*);
    const auto find=reinterpret_cast<Find>(base+0x3c9ff0);
    const auto insert=reinterpret_cast<Insert>(base+0xeb530);
    const auto erase=reinterpret_cast<Erase>(base+0x3c7390);
    const auto& current=give?original->give_to_pile:original->take_from_pile;
    // The native picker tests the requested direction before changing either
    // end, including before removing the opposite direction.
    if(!unlink && find(target.id,&current)>=0)return false;
    auto first=*original;auto second=target.links;
    auto& forward=give?first.give_to_pile:first.take_from_pile;
    auto& opposite=give?first.take_from_pile:first.give_to_pile;
    const auto prepare=[&](auto& reverse,auto& reverseOpposite) -> std::optional<bool> {
        if(!unlink) {
            if(forward.size()==1024 || (reverse.size()==1024 && find(source.id,&reverse)<0))return std::nullopt;
            // Native insertion's allocation branch is never entered. All
            // allocation and possible exceptions precede publication.
            forward.reserve(forward.size()+1);reverse.reserve(reverse.size()+1);
            insert(&target,&forward);erase(&target,&opposite);
            insert(&source,&reverse);erase(&source,&reverseOpposite);
        } else {
            erase(&target,&forward);erase(&source,&reverse);
        }
        using std::swap;
        swap(*original,first);swap(target.links,second);
        return true;
    };
    if(source.getType()==df::building_type::Stockpile)
        return give?prepare(second.take_from_pile,second.give_to_pile):
            prepare(second.give_to_pile,second.take_from_pile);
    return give?prepare(second.take_from_workshop,second.give_to_workshop):
        prepare(second.give_to_workshop,second.take_from_workshop);
}
std::optional<std::vector<NativeStockpileRow>> nativeStockpileWoodRows(
    const df::stockpile_settings& source,const std::string& filter) {
    if(source.wood.mats.size()>65536)return std::nullopt;
    auto owned=source;
    return nativeStockpileRows(owned,85,filter,{{"wood.mats",owned.wood.mats.data(),owned.wood.mats.size()}});
}
}
