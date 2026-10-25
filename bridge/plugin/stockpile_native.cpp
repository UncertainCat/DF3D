#include "stockpile_native.h"
#include "df/global_objects.h"
#include "df/building_stockpilest.h"
#include "df/custom_stockpile_interfacest.h"
#include "df/custom_stockpile_itemst.h"
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
}
std::optional<std::array<int16_t,3>> nativeStockpilePresetContainers(
    df::building_stockpilest& pile,int preset) {
    if(!df::global::world || preset<1 || preset>19)return std::nullopt;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=supported(base) &&
        hash(base+0x5587b0,0x79)==0x14b4f3f138690067ULL &&
        hash(base+0x57b770,0x113)==0x3fc5ac46eee9f334ULL &&
        hash(base+0x34a8d4,0x141)==0x444c389c4f7878d4ULL &&
        hash(base+0x35f0b8,0x4c)==0xf5f32f7dfd8f6deeULL;
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
    static constexpr size_t clears[]={0x30d350,0x30d540,0x30d560,0x30d5a0,
        0x30d5e0,0x30d5a0,0x30d560,0x30d5a0,0x30d620,0x30d620,0x30d640,
        0x30d660,0x30d720,0x30d5a0,0x30d760,0x30d780,0x30d740};
    void* fields[]={&owned.animals,&owned.food,&owned.furniture,&owned.corpses,
        &owned.refuse,&owned.stone,&owned.ammo,&owned.coins,&owned.bars_blocks,
        &owned.gems,&owned.finished_goods,&owned.leather,&owned.cloth,&owned.wood,
        &owned.weapons,&owned.armor,&owned.sheet};
    size_t index=0;while((uint32_t(1)<<index)!=category)++index;
    using Clear=void (*)(void*);
    reinterpret_cast<Clear>(base+clears[index])(fields[index]);
    return owned;
}
std::optional<std::vector<NativeStockpileRow>> nativeStockpileRows(
    df::stockpile_settings& owned,int mode,const std::string& filter,
    const std::vector<NativeStockpileSettingRange>& ranges) {
    if(!df::global::world || filter.size()>256)return std::nullopt;
    // Wood and the ten quality lists have no material/historical-cache path.
    switch(mode) {
      case 85:case 26:case 27:case 48:case 49:case 69:case 70:
      case 92:case 93:case 103:case 104:break;
      default:return std::nullopt;
    }
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=supported(base) &&
        hash(base+0x35fd70,0x77f0)==0x9826ec82d86ebf51ULL &&
        hash(base+0x35fb50,0x188)==0x0370358adf30598bULL &&
        hash(base+0x35fce0,0x89)==0x60a96499876e0c98ULL &&
        hash(base+0x14d880,0x5a)==0x4aa033209ea95fd2ULL &&
        hash(base+0x144d90,0xba)==0x97aed5d23117e68fULL &&
        hash(base+0x52d650,0x2b0)==0xcf43211ff8e2c344ULL &&
        hash(base+0x52cee0,0x19e)==0xc25c2d8a6eb9fcacULL &&
        hash(base+0x3bc400,0x14d)==0x038c68edadcc2b69ULL &&
        hash(base+0x6f290,0xe)==0x0b4b5eed70e95db6ULL;
    if(!compatible)return std::nullopt;
    static_assert(sizeof(df::custom_stockpile_interfacest)==0xf8);
    static_assert(sizeof(df::custom_stockpile_itemst)==0x60);
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
    reinterpret_cast<Build>(base+0x35fd70)(&rows.scratch,mode,0);
    if(rows.scratch.cur_spec_item_sz<0 ||
       size_t(rows.scratch.cur_spec_item_sz)>rows.scratch.spec_item.size())return std::nullopt;
    std::vector<NativeStockpileRow> result;
    result.reserve(rows.scratch.cur_spec_item_sz);
    for(int32_t i=0;i<rows.scratch.cur_spec_item_sz;++i) {
        const auto* row=rows.scratch.spec_item[i];
        if(!row)return std::nullopt;
        const auto pointer=reinterpret_cast<uintptr_t>(row->set_pointer);
        const NativeStockpileSettingRange* matched=nullptr;size_t index=0;
        for(const auto& range:ranges) {
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
std::optional<std::vector<NativeStockpileRow>> nativeStockpileWoodRows(
    const df::stockpile_settings& source,const std::string& filter) {
    if(source.wood.mats.size()>65536)return std::nullopt;
    auto owned=source;
    return nativeStockpileRows(owned,85,filter,{{"wood.mats",owned.wood.mats.data(),owned.wood.mats.size()}});
}
}
