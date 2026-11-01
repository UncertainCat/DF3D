#pragma once
#include "zone_native.h"
#include "df/squad_order.h"
#include "df/squad_routine_schedulest.h"
#include "df/squad_month_positionst.h"
#include "df/squad_schedule_order.h"
namespace df3d_creature {
struct SquadPage {
    int32_t id=-1,color=7;
    std::string caption="No squad assigned",shortName,order;
    std::array<uint8_t,7> symbol{};
};
inline std::optional<SquadPage> militarySquad(df::unit* unit) {
    if(!unit || !df::global::world)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
        {0x13cc1d0,0x224,UINT64_C(0xc9ff3ea4503393a7)},
        {0x67050,0x3,UINT64_C(0x62941518298855c4)},
        {0xede350,0x31b,UINT64_C(0x1fddbdca853294d0)},
        {0x488690,0xb1,UINT64_C(0x37b34cb16e196cdf)},
        {0x67b90,0x6,UINT64_C(0xf24ae2dac3164c16)},
        {0x10f2a90,0x72,UINT64_C(0xa393ae8bc2d628c5)},
        {0x421210,0xa2,UINT64_C(0x93796c0dfbfb44e9)},
        {0x67540,0x6,UINT64_C(0x2505ef84b8531c22)},
        {0x10f2ea0,0x101,UINT64_C(0x80d7e1ddc0358a26)},
        {0x4883f0,0xb7,UINT64_C(0xfba996c993c0afd3)},
        {0x67860,0x6,UINT64_C(0xa3dbcb2d9d6ef034)},
        {0x10f2950,0x96,UINT64_C(0x8283d54b26db9956)},
        {0x488540,0xb7,UINT64_C(0x302ee8633be00635)},
        {0x67a50,0x6,UINT64_C(0xfef8c40540640013)},
        {0x10f29f0,0x96,UINT64_C(0xc42ba9bdd6c6dd97)},
        {0x4882a0,0xb1,UINT64_C(0x17e12822d78dd27a)},
        {0x67530,0x6,UINT64_C(0xe59b01b045c53219)},
        {0x10f28b0,0x9b,UINT64_C(0xcb1f0047929b5b32)},
        {0x421020,0x11d,UINT64_C(0xffe23025b913c457)},
        {0x67500,0x6,UINT64_C(0x31b5d0af35a4361f)},
        {0x10f2b10,0x33c,UINT64_C(0x4afd219dfc8537a7)},
        {0x10f2e50,0x46,UINT64_C(0xe96016f43a1f9c3d)},
        {0x30f9b0,0xa5,UINT64_C(0x5295bfa8d17161f4)},
        {0x66e90,0x3,UINT64_C(0x58389c18233078ff)},
        {0x10f2800,0xa8,UINT64_C(0xde79b5604a82f41f)},
        {0x30fc40,0x76,UINT64_C(0xfc5af81da01de430)},
        {0x67520,0x6,UINT64_C(0x18580e5a3b056825)},
        {0x10f31d0,0x93,UINT64_C(0xa26dfb3f63922350)},
        {0x1bba20,0xa5,UINT64_C(0x24fafea47f29c343)},
        {0x671f0,0x6,UINT64_C(0x8a7e08d8a2d0223a)},
        {0x10f2ff0,0x170,UINT64_C(0x325f0dd1eb32ede3)},
        {0x1bbb20,0xa5,UINT64_C(0x477fb0ff2a8ae091)},
        {0x67270,0x6,UINT64_C(0x7dce27ae257f083d)},
        {0x10f3160,0x6a,UINT64_C(0xfb09eb2503eeafb0)},
        {0x1bb7a0,0xa5,UINT64_C(0x11c89c53ecdb5533)},
        {0x676d0,0x6,UINT64_C(0x972bea03201dd637)},
        {0x10f2fb0,0x3e,UINT64_C(0x239c795fa6222258)},
        {0x4214d0,0x70,UINT64_C(0x5fa3a464872dad58)},
        {0x67a40,0x6,UINT64_C(0x0ba8a52fbdb51a10)},
        {0x10f3270,0x15,UINT64_C(0x5eba20eb5bd32245)},
        };
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return std::nullopt;
    SquadPage page;auto* squad=df::squad::find(unit->military.squad_id);
    if(!squad)return page;
    // The native resolver consumes world squad records and the simulation date,
    // never view_sheets. Its unchecked schedule edges are validated before entry.
    const auto validOrder=[base](df::squad_order* order) {
        if(!order)return false;
        auto** table=*reinterpret_cast<void***>(order);
        constexpr size_t tables[]={0x1641ca0,0x163bf58,0x1641dc0,0x1641f90,0x1641d30,0x163c9b8,0x162df90,0x162e578,0x1603290,0x1603320,0x1603200,0x163c630};
        const auto rva=reinterpret_cast<uint8_t*>(table)-base;
        return std::find(std::begin(tables),std::end(tables),size_t(rva))!=std::end(tables) && table[14]==base+0x67050;
    };
    for(auto* order:squad->orders)if(!validOrder(order))return std::nullopt;
    const auto position=unit->military.squad_position;
    if(position>=0 && size_t(position)<squad->positions.size() && squad->positions[position]) {
        for(auto* order:squad->positions[position]->orders)if(!validOrder(order))return std::nullopt;
        const auto routine=squad->cur_routine_idx;
        if(routine>=0 && size_t(routine)<squad->schedule.routine.size()) {
            auto* schedule=squad->schedule.routine[routine];
            if(!schedule || !df::global::cur_season || !df::global::cur_season_tick)return std::nullopt;
            const int season=*df::global::cur_season,tick=*df::global::cur_season_tick;
            if(season<0 || season>3 || tick<0 || tick>=10080)return std::nullopt;
            const auto& month=schedule->month[season*3+tick/3360];
            if(size_t(position)>=month.order_assignments.size() || !month.order_assignments[position])return std::nullopt;
            for(auto* order:month.orders)if(!order || !validOrder(order->order))return std::nullopt;
        }
    }
    auto name=df3d_area::nativeZoneSquadName(*squad);if(!name)return std::nullopt;
    page.id=squad->id;page.caption=std::move(*name);page.shortName=page.caption;
    if(squad->alias.empty() && page.shortName.size()>4)
        reinterpret_cast<void(*)(std::string*)>(base+0xede350)(&page.shortName);
    auto* order=reinterpret_cast<df::squad_order*(*)(df::unit*)>(base+0x13cc1d0)(unit);
    if(order) {
        if(!validOrder(order))return std::nullopt;
        // Native getDescription caches some captions. Clone owns that scratch.
        std::unique_ptr<df::squad_order> owned(order->clone());if(!owned)return std::nullopt;
        page.color=int(owned->getType())==1?12:10;owned->getDescription(&page.order);
    } else page.order="No orders"; // Native17bc0f, literal1600dd8.
    if(page.order.size()>512)return std::nullopt;
    auto symbol=df3d_area::nativeZoneSquadSymbol(*squad);if(!symbol)return std::nullopt;
    page.symbol=*symbol;return page;
}
}
