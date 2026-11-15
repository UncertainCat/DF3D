#include "tile_description_native.h"
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <array>
#include <cstring>
#include "DataDefs.h"
#include "modules/Maps.h"
#include "MiscUtils.h"
#include "df/world.h"
#include "df/tile_designation.h"
#include "df/global_objects.h"
#include "df/lookinfost.h"
#include "df/item.h"
#include "df/unit.h"
#include "df/building.h"
#include "df/map_block.h"
#include "df/vermin.h"
#include "df/proj_itemst.h"
#include "df/flow_info.h"
#include "df/fire.h"
#include "df/campfire.h"
#include "df/block_square_event_material_spatterst.h"
#include "df/block_square_event_item_spatterst.h"
#include "df/block_square_event_type.h"
#include "df/block_square_event_spoorst.h"
#include "df/adventurest.h"


namespace df3d_hover {
namespace {
uint64_t fingerprint(const uint8_t* p, size_t n) {
    uint64_t h=14695981039346656037ULL;
    while(n--) { h^=*p++; h*=1099511628211ULL; }
    return h;
}
// Native geological fallbacks may draw from MT; plant detail seeds SplitMix.
// Restore all streams as well as their selected index, including twisted buffers.
struct RandomRestore {
    uint8_t* base;
    std::array<uint8_t,0x6180> mt;
    std::array<uint8_t,40> indices;
    int16_t stream;
    uint64_t split;
    explicit RandomRestore(uint8_t* b):base(b) {
        std::memcpy(mt.data(),b+0x234e990,mt.size());
        std::memcpy(indices.data(),b+0x2131b30,indices.size());
        std::memcpy(&stream,b+0x2159084,sizeof(stream));
        std::memcpy(&split,b+0x18adf98,sizeof(split));
    }
    ~RandomRestore() {
        std::memcpy(base+0x234e990,mt.data(),mt.size());
        std::memcpy(base+0x2131b30,indices.data(),indices.size());
        std::memcpy(base+0x2159084,&stream,sizeof(stream));
        std::memcpy(base+0x18adf98,&split,sizeof(split));
    }
};
}
std::optional<std::string> terrain(int32_t x,int32_t y,int32_t z,bool plantDetail) {
    if(x<0 || y<0 || z<0 || x>32767 || y>32767 || z>32767 || !DFHack::Maps::IsValid())return {};
    auto* block=DFHack::Maps::getTileBlock(x,y,z);
    const auto* designation=DFHack::Maps::getTileDesignation(x,y,z);
    if(!block || !designation || designation->bits.hidden)return {};
    auto* b=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[b] {
        if(!b)return false;
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(b);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return false;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(b+dos->e_lfanew);
        return pe->Signature==IMAGE_NT_SIGNATURE && pe->FileHeader.Machine==0x8664 &&
            pe->FileHeader.TimeDateStamp==0x6a70a6d9 && pe->OptionalHeader.SizeOfImage==0x2711000 &&
            fingerprint(b+0xe7d330,0x61c0)==0xbfe6727a40f5633bULL;
    }();
    if(!supported)return {};
    RandomRestore restore(b);
    std::string result;
    using Describe=void (*)(df::world*,std::string*,int16_t,int16_t,int16_t,bool);
    // Hover passes true; the planned-engraving heading passes false (158ef5).
    reinterpret_cast<Describe>(b+0xe7d330)(df::global::world,&result,int16_t(x),int16_t(y),int16_t(z),plantDetail);
    if(result.size()>4096)return {};
    return DF2UTF(result);
}
std::optional<Description> object(ObjectKind kind,int32_t id) {
    if(id<0 || !DFHack::Maps::IsValid())return {};
    auto* b=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[b] {
        if(!b)return false;
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(b);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return false;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(b+dos->e_lfanew);
        return pe->Signature==IMAGE_NT_SIGNATURE && pe->FileHeader.Machine==0x8664 &&
            pe->FileHeader.TimeDateStamp==0x6a70a6d9 && pe->OptionalHeader.SizeOfImage==0x2711000 &&
            fingerprint(b+0x406860,0x1c80)==0xf348678d63efe8b2ULL;
    }();
    if(!supported)return {};
    df::lookinfost entry;
    entry.pos=df::coord(-30000,-30000,-30000);
    switch(kind) {
    case ObjectKind::Item:
        if(!df::item::find(id))return {};
        entry.type=df::look_info_type::Item;entry.data.item.item_id=id;break;
    case ObjectKind::Unit:
        if(!df::unit::find(id))return {};
        entry.type=df::look_info_type::Unit;entry.data.unit.unit_id=id;break;
    case ObjectKind::Building:
        if(!df::building::find(id))return {};
        entry.type=df::look_info_type::Building;entry.data.building.bld_id=id;break;
    default:return {};
    }
    RandomRestore restore(b);
    reinterpret_cast<void (*)(df::lookinfost*)>(b+0x406860)(&entry);
    auto text=DF2UTF(entry.display_str);
    if(text.size()>4096 || entry.cf<0 || entry.cf>7 || entry.cb<0 || entry.cb>7 || entry.cbr<0 || entry.cbr>1)return {};
    return Description{std::move(text),entry.cf,entry.cb,entry.cbr!=0};
}
std::optional<std::vector<Description>> collect(int32_t x,int32_t y,int32_t z) {
    if(x<0 || y<0 || z<0 || x>32767 || y>32767 || z>32767 || !DFHack::Maps::IsValid())return {};
    auto* block=DFHack::Maps::getTileBlock(x,y,z);
    if(!block || block->designation[x&15][y&15].bits.hidden)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // The terrain query performs the PE and terrain routine checks first.
    if(!terrain(x,y,z))return {};
    static const bool supported=
        fingerprint(base+0x406860,0x1c80)==0xf348678d63efe8b2ULL &&
        fingerprint(base+0x137bd50,0x2d0)==0xdee22d5bacd12bc9ULL &&
        fingerprint(base+0x14da20,0x12c)==0xe4024d0451e33fb3ULL &&
        fingerprint(base+0x5587b0,0x79)==0x14b4f3f138690067ULL &&
        fingerprint(base+0x141920,0x100)==0x3c7e006e064d00eeULL &&
        fingerprint(base+0x5317f0,0x7f)==0xd5e294eafa062045ULL;
    if(!supported)return {};
    RandomRestore restore(base);
    const df::coord pos{uint16_t(x),uint16_t(y),uint16_t(z)};
    auto* world=df::global::world;
    const auto designation=block->designation[x&15][y&15];
    std::vector<Description> rows;
    size_t bytes=0;bool valid=true;
    auto append=[&](df::lookinfost entry,int32_t id=-1) {
        if(!valid)return;
        reinterpret_cast<void (*)(df::lookinfost*)>(base+0x406860)(&entry);
        auto text=DF2UTF(entry.display_str);bytes+=text.size();
        if(rows.size()>=4096 || bytes>320*1024 || text.size()>4096 ||
           entry.cf<0 || entry.cf>7 || entry.cb<0 || entry.cb>7 || entry.cbr<0 || entry.cbr>1) {valid=false;return;}
        rows.push_back({std::move(text),entry.cf,entry.cb,entry.cbr!=0,uint8_t(entry.type),id});
    };
    auto entry=[](df::look_info_type kind) {
        df::lookinfost result;result.type=kind;result.pos=df::coord(-30000,-30000,-30000);return result;
    };
    // Native 408c43: active-unit vector order, native hidden and footprint predicates.
    for(auto* unit:world->units.active) {
        if(!unit || (unit->flags1.whole & 0x2000002))continue;
        if(reinterpret_cast<bool (*)(df::unit*)>(base+0x137bd50)(unit))continue;
        if(!reinterpret_cast<bool (*)(df::unit*,int16_t,int16_t,int16_t)>(base+0x14da20)(unit,int16_t(x),int16_t(y),int16_t(z)))continue;
        auto e=entry(df::look_info_type::Unit);e.data.unit.unit_id=unit->id;append(e,unit->id);
    }
    for(auto* vermin:world->event.vermin) {
        if(!vermin || !vermin->visible || vermin->pos!=pos)continue;
        auto e=entry(df::look_info_type::Vermin);
        e.data.vermin.race=vermin->race;e.data.vermin.caste=vermin->caste;
        e.data.vermin.item_id=vermin->item?vermin->item->id:-1;
        e.data.vermin.flag=vermin->flags.whole;e.data.vermin.number=vermin->amount;append(e);
    }
    auto items=[&](bool garbage) {
        for(auto id:block->items) {
            auto* item=df::item::find(id);
            if(!item || bool(item->flags.bits.garbage_collect)!=garbage || item->pos!=pos)continue;
            auto e=entry(df::look_info_type::Item);e.data.item.item_id=id;append(e,id);
        }
    };
    items(false);
    for(auto* link=world->projectiles.all.next;link;link=link->next) {
        auto* projectile=link->item;
        if(!projectile || (projectile->flags.whole&0x20) || projectile->getType()!=df::projectile_type::Item || projectile->cur_pos!=pos)continue;
        auto* item=static_cast<df::proj_itemst*>(projectile)->item;if(!item)continue;
        auto e=entry(df::look_info_type::Item);e.data.item.item_id=item->id;append(e,item->id);
    }
    for(auto* building:world->buildings.all) {
        // Normal fortress hover's isVisibleInUI branch is !isHidden. Native
        // hide/unhide menu overrides are deliberately not runtime inputs.
        if(!building || !building->isSettingOccupancy() || building->isHidden() || building->z!=z)continue;
        if(building->isExtentShaped() && building->room.extents) {
            if(!reinterpret_cast<bool (*)(df::building*,int16_t,int16_t,int16_t)>(base+0x5587b0)(building,int16_t(x),int16_t(y),int16_t(z)))continue;
        } else if(x<building->x1 || x>building->x2 || y<building->y1 || y>building->y2)continue;
        auto e=entry(df::look_info_type::Building);e.data.building.bld_id=building->id;append(e,building->id);
    }
    // Native a53730 returns this block's flow vector for valid coordinates.
    for(auto* flow:block->flows) {
        if(!flow || (flow->flags.whole&1) || int(flow->type)<0 || int(flow->type)>13 || flow->pos!=pos)continue;
        auto e=entry(df::look_info_type::Flow);e.data.flow.type=int16_t(flow->type);
        e.data.flow.subtype=flow->mat_type;e.data.flow.sstype=flow->mat_index;
        e.data.flow.guide_id=flow->guide_id;e.data.flow.flag.whole=designation.bits.subterranean?1:0;append(e);
    }
    for(auto* fire:world->event.fires)if(fire && fire->pos==pos)append(entry(df::look_info_type::Fire));
    for(auto* fire:world->event.campfires)if(fire && fire->pos==pos)append(entry(df::look_info_type::Campfire));
    auto floor=entry(df::look_info_type::Floor);floor.pos=pos;append(floor);
    const auto depth=reinterpret_cast<int8_t (*)(df::world*,int16_t,int16_t,int16_t)>(base+0x141920)(world,int16_t(x),int16_t(y),int16_t(z));
    if(depth>0) {
        if(designation.bits.liquid_type==df::tile_liquid::Magma) {
            auto e=entry(df::look_info_type::Magma);e.data.liquid_magma.amount=depth;
            e.data.liquid_magma.flag.whole=designation.bits.subterranean?1:0;append(e);
        } else {
            auto e=entry(df::look_info_type::Water);e.data.liquid_water.amount=depth;
            e.data.liquid_water.flag.whole=(designation.bits.water_stagnant?1:0)|(designation.bits.water_salt?2:0);append(e);
        }
    }
    for(auto it=block->block_events.rbegin();it!=block->block_events.rend();++it) {
        auto* event=*it;if(!event)continue;
        auto e=entry(df::look_info_type::Spatter);int amount=0;
        e.data.spatter.i_type=df::item_type::NONE;e.data.spatter.i_subtype=-1;
        if(event->getType()==df::block_square_event_type::material_spatter) {
            auto* spatter=static_cast<df::block_square_event_material_spatterst*>(event);
            amount=spatter->amount[x&15][y&15];e.data.spatter.mat=spatter->mat_type;
            e.data.spatter.matg=spatter->mat_index;e.data.spatter.matstate=spatter->mat_state;
        } else if(event->getType()==df::block_square_event_type::item_spatter) {
            auto* spatter=static_cast<df::block_square_event_item_spatterst*>(event);
            amount=spatter->amount[x&15][y&15];e.data.spatter.i_type=spatter->item_type;
            e.data.spatter.i_subtype=spatter->item_subtype;e.data.spatter.mat=spatter->mattype;
            e.data.spatter.matg=spatter->matindex;e.data.spatter.matstate=df::matter_state::Solid;
        }
        if(amount>0) {e.data.spatter.extent=amount>=100?3:amount>=50?2:1;append(e);}
    }
    // Native 409de8 uses encountered-track knowledge, populated by perception
    // at 14ab48f..14ab5d3. These coordinates are semantic player knowledge,
    // not the tracking menu's selection, visibility count or viewing_spoor.
    // 5317f0 reads the first present spoor event at the supplied block cell.
    if(designation.bits.pile && df::global::adventure) {
        auto* spoor=reinterpret_cast<df::block_square_event_spoorst* (*)(df::map_block*,int16_t,int16_t)>(base+0x5317f0)(block,int16_t(x&15),int16_t(y&15));
        if(spoor) {
            const auto& knowledge=*df::global::adventure;
            for(size_t i=0;i<knowledge.tracks_x.size();++i) {
                if(int64_t(knowledge.tracks_x[i])-int64_t(world->map.region_x)*48!=x ||
                   int64_t(knowledge.tracks_y[i])-int64_t(world->map.region_y)*48!=y ||
                   int64_t(knowledge.tracks_z[i])-world->map.region_z!=z)continue;
                auto e=entry(df::look_info_type::Spoor);e.pos=pos;
                const auto& info=spoor->info;
                e.data.spoor.flag=info.flags[x&15][y&15];e.data.spoor.type=info.type[x&15][y&15];
                e.data.spoor.id1=info.id1[x&15][y&15];e.data.spoor.id2=info.race[x&15][y&15];
                e.data.spoor.id3=info.caste[x&15][y&15];append(e);break;
            }
        }
    }
    items(true);
    if(!valid)return {};
    return rows;
}

}
