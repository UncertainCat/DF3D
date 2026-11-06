#pragma once
#include "work_detail_native.h"

namespace df3d_production {
namespace work_detail_settings {
// Native42e6e0 constructs widgets. Read its pinned immutable catalog constants
// into owned storage instead; no widget/global menu fields enter this API.
inline constexpr size_t catalogBlocks[]={0x178c160,0x178b8e0,0x178b990,0x178b920,
    0x178b960,0x178b9b0,0x178bb20,0x178bad0,0x178b9d0,0x178baf0,0x178ba20,
    0x178ba40,0x178ba60,0x178c150,0x178bb30,0x178baa0,0x178bba0,0x178bac0,
    0x178b6b0,0x178b750,0x178bb50,0x178b860};
inline bool supported() {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x42ec5f,0x169,UINT64_C(0x84c004d6a6dc04a0)},
            {0xacb830,0x974,UINT64_C(0xa33615d873c273c5)},
            {0x468ec0,0x1c,UINT64_C(0x40f27d3575ba78d0)},
            {0x469020,0x127,UINT64_C(0xa3f5871c834384f5)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=pin.hash)return false;}
        uint64_t h=UINT64_C(14695981039346656037);
        for(size_t rva:catalogBlocks)for(size_t i=0;i<16;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}
        return h==UINT64_C(0xb93cbfd32e0034cc);
    }();return ready;
}
inline std::vector<int32_t> catalog() {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    std::vector<int32_t> ids;ids.reserve(91);
    for(size_t rva:catalogBlocks)for(size_t i=0;i<4;++i){int32_t id;std::memcpy(&id,base+rva+i*4,4);ids.push_back(id);}
    ids.insert(ids.end(),{75,79,80});return ids;
}
}
struct WorkDetailSetting {int32_t id;std::string caption;};
inline std::optional<std::vector<WorkDetailSetting>> nativeWorkDetailSettings() {
    if(!work_detail_settings::supported())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    std::vector<WorkDetailSetting> result;result.reserve(91);
    for(int32_t id:work_detail_settings::catalog()) {
        std::string caption;reinterpret_cast<void(*)(std::string*,int32_t)>(base+0xacb830)(&caption,id);
        if(caption.empty() || caption.size()>512)return std::nullopt;
        result.push_back({id,std::move(caption)});
    }
    return result;
}
// Definition-only operation. The native leaf does not recalculate workers;
// callers own revision checks and commit policy. This also supports local
// independent drafts/probes without touching a live simulation definition.
inline bool nativeWorkDetailToggle(std::array<bool,94>& allowed,int32_t id) {
    if(!work_detail_settings::supported())return false;
    auto ids=work_detail_settings::catalog();
    if(std::find(ids.begin(),ids.end(),id)==ids.end())return false;
    struct Context {
        std::array<std::byte,0x1b8> padding{};
        std::vector<int32_t> ids;
        bool* allowed;
    } context{{},std::move(ids),allowed.data()};
    static_assert(offsetof(Context,ids)==0x1b8 && offsetof(Context,allowed)==0x1d0);
    struct Closure {uintptr_t padding=0;Context* context;int32_t id;};
    static_assert(offsetof(Closure,context)==8 && offsetof(Closure,id)==0x10);
    Closure closure{0,&context,id};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    return reinterpret_cast<bool(*)(Closure*,int32_t)>(base+(id<0?0x469020:0x468ec0))(&closure,0);
}
}
