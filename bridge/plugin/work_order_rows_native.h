#pragma once
#include "work_order_catalog_native.h"
#include "df/manager_order_condition_item.h"
#include "df/manager_order_condition_order.h"

namespace df3d_production {
enum class NativeWorkOrderPhase : uint8_t { Active=1, Waiting, Checking, Ready };
struct NativeWorkOrderRow {
    int32_t id=-1,workshopId=-1,position=-1,finishedYear=-1,finishedTick=-1,maxWorkshops=0;
    int16_t total=0,remaining=0,matType=-1;
    int32_t matIndex=-1;
    uint32_t materialCategory=0;
    int8_t frequency=0;
    bool validated=false,active=false,validationRequired=false,detailsAvailable=false;
    NativeWorkOrderPhase phase=NativeWorkOrderPhase::Ready;
    uint64_t revision=0;
    std::string caption;
    std::vector<df::manager_order_condition_item> itemConditions;
    std::vector<df::manager_order_condition_order> orderConditions;
};
struct NativeWorkOrderPage {
    uint64_t revision=0;
    uint32_t total=0,nextCursor=0;
    std::vector<NativeWorkOrderRow> rows;
};
inline bool workOrderRowsSupported() {
    static const bool ready=[] {
        if(!workOrderCatalogSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1889f7,0x4e9,UINT64_C(0xe29e242e0b9cec4a)}, // phase branches
            {0x188772,0xcc,UINT64_C(0xc7837322ac1ef8e5)}, // caption inputs
            {0x14e390,0x7c,UINT64_C(0xb8a8a91a69a0fa86)}, // blank template art
            {0x189294,0x10,UINT64_C(0xd9286ad1fc626d1f)}, // validation indicator
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// Safe-point observation. Native keeps phase selection inline in its renderer;
// compose those semantic branches from simulation records, not menu row caches.
// d15cf0 initializes the order's own requirements, as native row observation does.
inline std::optional<NativeWorkOrderRow> nativeWorkOrderRow(df::manager_order& order,int32_t position) {
    if(!workOrderRowsSupported() || !df::global::world || !df::global::plotinfo ||
       !df::global::cur_year || !df::global::cur_year_tick || order.id<0 ||
       order.reaction_name.size()>128 || order.item_conditions.size()+order.order_conditions.size()>64)return std::nullopt;
    static_assert(offsetof(df::manager_order,frequency)==0x58);
    static_assert(offsetof(df::manager_order,finished_year)==0x5c);
    static_assert(offsetof(df::manager_order,finished_year_tick)==0x60);
    NativeWorkOrderRow row;
    row.id=order.id;row.workshopId=order.workshop_id;row.position=position;
    row.total=order.amount_total;row.remaining=order.amount_left;row.frequency=int8_t(order.frequency);
    row.validated=order.status.bits.validated;row.active=order.status.bits.active;
    row.finishedYear=order.finished_year;row.finishedTick=order.finished_year_tick;row.maxWorkshops=order.max_workshops;
    row.matType=order.mat_type;row.matIndex=order.mat_index;row.materialCategory=order.material_category.whole;
    row.validationRequired=df::global::plotinfo->tasks.population>=20;
    const bool future=order.finished_year>*df::global::cur_year ||
        (order.finished_year==*df::global::cur_year && order.finished_year_tick>*df::global::cur_year_tick);
    if(row.active)row.phase=NativeWorkOrderPhase::Active;
    else if(future && order.frequency>=df::workquota_frequency_type::Monthly && order.frequency<=df::workquota_frequency_type::Yearly)row.phase=NativeWorkOrderPhase::Waiting;
    else if(!order.item_conditions.empty() || !order.order_conditions.empty())row.phase=NativeWorkOrderPhase::Checking;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Details=bool (*)(df::manager_order*);
    {
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        row.detailsAvailable=reinterpret_cast<Details>(base+0xd15cf0)(&order);
    }
    df::job captionInput;
    captionInput.job_type=order.job_type;captionInput.reaction_name=order.reaction_name;
    captionInput.item_type=order.item_type;captionInput.item_subtype=order.item_subtype;
    captionInput.mat_type=order.mat_type;captionInput.mat_index=order.mat_index;
    captionInput.specflag=order.specflag;captionInput.specdata=order.specdata;captionInput.material_category=order.material_category;
    // Native188772 uses a blank template and does not copy the order's art fields.
    captionInput.art_spec.type=df::job_art_specifier_type(-1);captionInput.art_spec.id=-1;captionInput.art_spec.subid=-1;
    const auto caption=workshopJobCaption(captionInput);if(!caption || caption->size()>512)return std::nullopt;
    row.caption=*caption;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    const auto text=[&](const std::string& value){add(value.size());for(unsigned char c:value){hash^=c;hash*=UINT64_C(1099511628211);}};
    add(order.id);add(int(order.job_type));text(order.reaction_name);add(int(order.item_type));add(order.item_subtype);
    add(order.mat_type);add(order.mat_index);add(order.specflag.whole);add(order.specdata.hist_figure_id);add(order.material_category.whole);
    add(int(order.art_spec.type));add(order.art_spec.id);add(order.art_spec.subid);
    add(row.total);add(row.remaining);add(order.status.whole);add(row.frequency);add(row.finishedYear);add(row.finishedTick);
    add(row.workshopId);add(row.maxWorkshops);add(int(row.phase));add(row.validationRequired);add(row.detailsAvailable);
    add(order.item_conditions.size());add(order.order_conditions.size());
    for(const auto* c:order.item_conditions) {
        if(!c || c->reaction_class.size()>128 || c->has_material_reaction_product.size()>128 || c->contains.size()>64)return std::nullopt;
        add(int(c->compare_type));add(c->compare_val);add(int(c->item_type));add(c->item_subtype);add(c->mat_type);add(c->mat_index);
        add(c->flags1.whole);add(c->flags2.whole);add(c->flags3.whole);add(c->flags4);add(c->flags5);
        text(c->reaction_class);text(c->has_material_reaction_product);add(c->metal_ore);add(c->min_dimension);
        add(c->contains.size());for(auto id:c->contains)add(id);
        add(c->reaction_id);add(int(c->has_tool_use));add(c->dye_color);row.itemConditions.push_back(*c);
    }
    for(const auto* c:order.order_conditions) {
        if(!c)return std::nullopt;
        add(c->order_id);add(int(c->condition));add(c->flags.whole);row.orderConditions.push_back(*c);
    }
    row.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    return row;
}

inline std::optional<NativeWorkOrderPage> nativeWorkshopOrderPage(df::building* building,uint32_t cursor,uint64_t revision) {
    const auto profile=workshopOrdersProfile(building);
    if(!profile || !workOrderRowsSupported() || cursor>profile->orderIds.size() ||
       (cursor && !revision) || (revision && revision!=profile->revision))return std::nullopt;
    NativeWorkOrderPage page;page.revision=profile->revision;page.total=uint32_t(profile->orderIds.size());
    const size_t end=std::min(size_t(page.total),size_t(cursor)+16);
    size_t index=0,conditions=0;int32_t position=0;
    for(auto* order:df::global::world->manager_orders.all) {
        if(order && order->workshop_id==building->id) {
            if(index>=cursor && index<end) {
                auto row=nativeWorkOrderRow(*order,position);if(!row)return std::nullopt;
                const size_t count=row->itemConditions.size()+row->orderConditions.size();
                if(conditions+count>128)break;
                conditions+=count;page.rows.push_back(std::move(*row));
            }
            ++index;
        }
        ++position;
    }
    if(page.rows.empty() && cursor<page.total)return std::nullopt;
    const auto next=cursor+uint32_t(page.rows.size());
    page.nextCursor=next<page.total?next:0;
    return page;
}
}
