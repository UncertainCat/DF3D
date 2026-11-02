#pragma once
#include "work_order_details_native.h"
#include "location_details_native.h"
#include "df/image_creator_interfacest.h"
#include "df/historical_figure.h"
#include "df/historical_entity.h"
#include "df/world_site.h"

namespace df3d_production {
struct WorkOrderArtSubjects {
    uint64_t orderRevision=0,listRevision=0;
    int32_t kind=-1;
    std::vector<int32_t> ids;
};
inline bool workOrderArtSubjectsReady() {
    static const bool ready=[] {
        if(!workOrderDetailsReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x20f300,0x3a2,UINT64_C(0x7a58222f99e2a853)}, // historical figures
            {0x20f6b0,0x3dc,UINT64_C(0x9aec29c4191db1c7)}, // sites
            {0x20fa90,0x37c,UINT64_C(0x8972bb117b3367d0)}, // entities
            {0x1fc0c0,0x8c,UINT64_C(0xd79cbc6ebdc2073a)}, // native name comparator
            {0x1fb1c0,0x345,UINT64_C(0x2cdbd88b294d4dae)}, // owned master-row cleanup
            {0x201320,0x79,UINT64_C(0x9eedf99c8af9aefb)}, // figure caption composition
            {0x201976,0x60,UINT64_C(0xd99b90c0338c328e)}, // site caption composition
            {0x201fb6,0x62,UINT64_C(0xef66198fb280beac)}, // entity caption composition
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)}, // simple native name
            {0xc0f630,0x2c,UINT64_C(0x2f03e40b0a07e0bf)}, // historical identity
            {0x20a1df,0x94,UINT64_C(0xda14704e2a7596a2)}, // figure selection
            {0x20a515,0x94,UINT64_C(0x887e8ee07510f16a)}, // site selection
            {0x20a844,0x90,UINT64_C(0x21fb16abe2986637)}, // entity selection
            {0x20f179,0x91,UINT64_C(0xd457c7675c96d8cb)}, // artist choice
            {0x1ffced,0x216,UINT64_C(0xbccd02d40a931fd0)}, // order artwork heading composition
            {0x1fff6d,0x14,UINT64_C(0xd97688af8b65493a)}, // heading limit
            {0x1615350,0xc8,UINT64_C(0x227f3ddd70cde8fd)}, // root option literals
            {0x20fe10,0x778,UINT64_C(0x9d6f973893f52a9e)}, // existing images, owned filter/output
            {0x202605,0x5f,UINT64_C(0xead228bd984fbe29)}, // image caption composition
            {0x20ab8c,0xbf,UINT64_C(0x74673a4596594e8b)}, // image selection and requirement rebuild
            {0x202717,0x360,UINT64_C(0x3de07dad79e5516d)}, // image provenance labels
            {0x212ffb,0x99,UINT64_C(0xb33f7b9791fee483)}, // image preview inputs
            {0x1451b10,0x161c,UINT64_C(0x5afdbfca1604e13b)}, // semantic image description
            {0x8e7310,0x121,UINT64_C(0x672cfcd6c9373787)}, // owned text wrapping
            {0x8e7440,0x2d6,UINT64_C(0xe813a30176188ce5)},
            {0xbb9b0,0x74,UINT64_C(0x7532991bab65be09)}, // owned text cleanup
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// These leaves build/sort/filter subjects on an owned context. Neither the
// whole opener1ffae0 nor the mixed navigation/action dispatcher20ed00 is called.
inline std::optional<WorkOrderArtSubjects> nativeWorkOrderArtSubjects(df::manager_order& source,int32_t kind,const std::string& query={}) {
    if(kind<1 || kind>3 || query.size()>128 || !workOrderArtSubjectsReady())return std::nullopt;
    const auto details=nativeWorkOrderDetails(source);if(!details)return std::nullopt;
    bool supported=false;
    for(const auto& option:details->options)if(option.kind==1 || option.kind==3)supported=true;
    if(!supported)return std::nullopt;
    df::manager_order order=source;
    df::image_creator_interfacest context;
    context.context=df::image_creator_context_type::JOB_DETAILS_MAIN;
    context.current_option=df::image_creator_option_type(kind);
    context.ics.wq=&order;context.ics.jb=nullptr;
    context.ics.image_ent=df::global::plotinfo->main.fortress_entity;
    context.filter=query;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Cleanup {
        df::image_creator_interfacest& context;
        const uint8_t* base;
        ~Cleanup(){reinterpret_cast<void(*)(df::image_creator_interfacest*)>(base+0x1fb1c0)(&context);}
    } cleanup{context,base};
    WorkOrderArtSubjects result;result.kind=kind;result.orderRevision=details->revision;
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    const auto collect=[&](auto& rows,size_t rva) {
        using Rows=std::remove_reference_t<decltype(rows)>;
        reinterpret_cast<void(*)(df::image_creator_interfacest*,Rows*)>(base+rva)(&context,&rows);
        if(rows.size()>262144)return false;
        result.ids.reserve(rows.size());
        for(const auto* row:rows) {if(!row || row->id<0)return false;result.ids.push_back(row->id);}
        return true;
    };
    if(!(kind==1?collect(context.hf,0x20f300):kind==2?collect(context.st,0x20f6b0):collect(context.ent,0x20fa90)))return std::nullopt;
    uint64_t hash=details->revision;
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    add(kind);add(result.ids.size());for(auto id:result.ids)add(id);
    result.listRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    return result;
}
inline std::string nativeWorkOrderArtNameCaption(const df::language_name& name) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df::language_name owned=name;
    std::string caption,translated;
    reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&owned,&caption);
    reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&translated,true,false);
    caption+=reinterpret_cast<const char*>(base+0x1602dbc);
    caption+=translated;caption+=reinterpret_cast<const char*>(base+0x15e9718);
    return caption;
}
struct WorkOrderArtImages {
    uint64_t listRevision=0;
    std::vector<df::art_image*> rows;
};
inline std::optional<WorkOrderArtImages> nativeWorkOrderArtImages(df::manager_order& source,const std::string& query={}) {
    if(query.size()>128 || !workOrderArtSubjectsReady())return std::nullopt;
    const auto details=nativeWorkOrderDetails(source);if(!details)return std::nullopt;
    bool supported=false;for(const auto& option:details->options)if(option.kind==1 || option.kind==3)supported=true;
    if(!supported)return std::nullopt;
    df::image_creator_interfacest context;
    context.context=df::image_creator_context_type::JOB_DETAILS_MAIN;
    context.current_option=df::image_creator_option_type(5);context.filter=query;
    // With no historical-figure input the native leaf reads the fortress and
    // civilization image collections. It does not consult the open art menu.
    context.ics.hf=nullptr;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<void(*)(df::image_creator_interfacest*,std::vector<df::art_image*>*)>(base+0x20fe10)(&context,&context.art_image);
    if(context.art_image.size()>262144)return std::nullopt;
    WorkOrderArtImages result;result.rows=std::move(context.art_image);
    uint64_t hash=details->revision;
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    add(5);add(result.rows.size());
    for(const auto* image:result.rows){if(!image || image->id<0 || image->subid<0)return std::nullopt;add(image->id);add(image->subid);}
    result.listRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;return result;
}
inline std::optional<std::string> nativeWorkOrderArtSubjectCaption(int32_t kind,int32_t id) {
    if(!workOrderArtSubjectsReady() || !df::global::world)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    df::language_name* name=nullptr;
    if(kind==1) {
        auto* figure=df::historical_figure::find(id);if(!figure)return std::nullopt;
        name=&figure->name;
        auto* identity=reinterpret_cast<df::identity*(*)(df::historical_figure*)>(base+0xc0f630)(figure);
        if(identity)name=reinterpret_cast<df::language_name*(*)(df::identity*)>(base+0xc3a4f0)(identity);
    } else if(kind==2) {
        auto* site=df::world_site::find(id);if(!site)return std::nullopt;name=&site->name;
    } else if(kind==3) {
        auto* entity=df::historical_entity::find(id);if(!entity)return std::nullopt;name=&entity->name;
    }
    if(!name)return std::nullopt;
    return nativeWorkOrderArtNameCaption(*name);
}

inline WorkOrderDetailEditResult setWorkOrderArtSubject(df::manager_order& order,uint64_t revision,int32_t option,int32_t kind,int32_t id,uint64_t listRevision,const std::string& query={}) {
    WorkOrderDetailEditResult result;
    if(!workOrderArtSubjectsReady() || kind<0 || (kind>3 && kind!=5))return result;
    const auto before=nativeWorkOrderDetails(order);
    if(!before || option<0 || size_t(option)>=before->options.size())return result;
    if(!revision || revision!=before->revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    const auto optionKind=before->options[size_t(option)].kind;
    if(optionKind!=1 && optionKind!=3)return result;
    // The improvement Image entry applies its own type edit before opening art.
    if(optionKind==3 && int(order.specdata.improvement)!=0)return result;
    df::art_image* selectedImage=nullptr;
    if(kind==5) {
        const auto choices=nativeWorkOrderArtImages(order,query);if(!choices)return result;
        if(!listRevision || choices->listRevision!=listRevision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
        if(id<0 || size_t(id)>=choices->rows.size())return result;
        selectedImage=choices->rows[size_t(id)];
    } else if(kind==0) {
        if(id!=-1 || listRevision || !query.empty())return result;
    } else {
        const auto choices=nativeWorkOrderArtSubjects(order,kind,query);
        if(!choices)return result;
        if(!listRevision || choices->listRevision!=listRevision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
        if(std::find(choices->ids.begin(),choices->ids.end(),id)==choices->ids.end())return result;
    }
    result.outcome=WorkshopOrdersOutcome::Unknown;
    order.art_spec.type=df::job_art_specifier_type(selectedImage?3:kind-1);
    order.art_spec.id=selectedImage?selectedImage->id:id;
    if(selectedImage)order.art_spec.subid=selectedImage->subid;
    // Native related-subject actions leave subid intact; artist choice clears it.
    if(kind==0)order.art_spec.subid=-1;
    if(order.items)rebuildWorkOrderDetailRequirements(order);
    result.observation=nativeWorkOrderDetails(order);
    if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
    return result;
}
inline std::optional<std::string> nativeWorkOrderArtBadge(const df::art_image& image) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df::historical_entity* entities[]={df::global::plotinfo->main.fortress_entity,df::historical_entity::find(df::global::plotinfo->civ_id)};
    constexpr size_t labels[2][2]={{0x1615448,0x1615430},{0x1615468,0x1615458}};
    for(size_t source=0;source<2;++source)if(const auto* entity=entities[source]) {
        const auto& r=entity->resources;
        if(r.art_image_types.size()!=r.art_image_ids.size() || r.art_image_types.size()!=r.art_image_subids.size())return std::nullopt;
        for(size_t i=0;i<r.art_image_types.size();++i)if(r.art_image_ids[i]==image.id && r.art_image_subids[i]==image.subid) {
            const int type=int(r.art_image_types[i]);
            if(type<0 || type>1)return std::nullopt;
            return std::string(reinterpret_cast<const char*>(base+labels[source][type]));
        }
    }
    return std::nullopt;
}
inline std::optional<std::vector<std::string>> nativeWorkOrderArtPreview(const df::art_image& source,uint16_t columns) {
    if(!workOrderArtSubjectsReady() || !columns || columns>256)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df::art_image owned=source;std::string description;
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Describe=void(*)(df::world*,df::art_image*,std::string*,int32_t,bool,bool,int32_t,int16_t,int32_t,bool,bool);
    reinterpret_cast<Describe>(base+0x1451b10)(df::global::world,&owned,&description,0,true,true,-1,-1,-1,true,false);
    if(description.size()>65536)return std::nullopt;
    df::curses_text_boxst box;
    struct Cleanup {df::curses_text_boxst& box;const uint8_t* base;~Cleanup(){reinterpret_cast<void(*)(std::vector<std::string*>*)>(base+0xbb9b0)(&box.text);}} cleanup{box,base};
    reinterpret_cast<void(*)(df::curses_text_boxst*,std::string*,int32_t)>(base+0x8e7310)(&box,&description,columns);
    if(box.text.size()>128)return std::nullopt;
    std::vector<std::string> lines;
    for(const auto* line:box.text){if(!line || line->size()>2048)return std::nullopt;lines.push_back(*line);}
    return lines;
}
struct WorkOrderArtDraftElementValue {int16_t kind=0;int32_t id=-1,secondary=-1,quantity=1;};
struct WorkOrderArtDraftRelationshipValue {int32_t verb=-1;bool transitive=false;int32_t actor=-1,target=-1;};
struct WorkOrderArtDraftValue {
    std::vector<WorkOrderArtDraftElementValue> elements;
    std::vector<WorkOrderArtDraftRelationshipValue> relationships;
    std::optional<df::language_name> name;
};
struct WorkOrderArtDisplayRow {int32_t id;std::string caption;std::optional<std::string> badge;int32_t secondary=-1;};
struct WorkOrderArtNamePage {
    std::string nativeHeader,englishHeader,query;
    uint8_t component=0;uint32_t cursor=0,total=0,nextCursor=0;
    std::vector<df3d_area::LocationNameWord> choices;
};
struct WorkOrderArtPage {
    int16_t page=-1;std::string caption;
    std::vector<WorkOrderArtDisplayRow> rows;
    uint64_t listRevision=0;uint32_t total=0,nextCursor=0;
    int32_t hovered=-1;std::optional<std::vector<std::string>> preview;
    std::optional<WorkOrderArtDraftValue> draft;
    std::optional<std::vector<std::string>> draftDescription;
    std::optional<WorkOrderArtNamePage> name;
};
inline std::optional<WorkOrderArtPage> nativeWorkOrderArtPage(df::manager_order& order,int16_t page,const std::string& query,uint32_t cursor,uint64_t listRevision,int32_t hovered=-1,uint16_t columns=0) {
    if(!workOrderArtSubjectsReady())return std::nullopt;
    if(hovered>=0 && (page!=5 || !columns || !listRevision))return std::nullopt;
    const auto row=nativeWorkOrderRow(order,-1,true);if(!row)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    WorkOrderArtPage result;result.page=page;
    result.caption=reinterpret_cast<const char*>(base+0x1615548);result.caption+=row->caption;
    if(order.amount_total>0)result.caption+=" ("+std::to_string(order.amount_total)+")";
    if(result.caption.size()>78)result.caption.resize(78);
    if(page==-1) {
        if(!query.empty() || cursor || listRevision)return std::nullopt;
        constexpr std::pair<int32_t,size_t> options[]={{1,0x1615360},{2,0x16153c8},{3,0x16153a0},{5,0x16153f0},{6,0x16153d8},{0,0x1615400}};
        for(const auto& [id,rva]:options)result.rows.push_back({id,reinterpret_cast<const char*>(base+rva),std::nullopt});
        result.total=uint32_t(result.rows.size());return result;
    }
    if(page==5) {
        const auto images=nativeWorkOrderArtImages(order,query);
        if(!images || cursor>images->rows.size() || (listRevision && listRevision!=images->listRevision))return std::nullopt;
        result.listRevision=images->listRevision;result.total=uint32_t(images->rows.size());
        const auto end=std::min(size_t(cursor)+128,images->rows.size());
        for(size_t i=cursor;i<end;++i) {
            auto caption=nativeWorkOrderArtNameCaption(images->rows[i]->name);if(caption.size()>1024)return std::nullopt;
            // Images can share a chunk ID and occur in both native collections.
            // This filtered-list ordinal is guarded by the complete pair list.
            result.rows.push_back({int32_t(i),std::move(caption),nativeWorkOrderArtBadge(*images->rows[i])});
        }
        if(hovered>=0) {
            if(size_t(hovered)<cursor || size_t(hovered)>=end)return std::nullopt;
            result.preview=nativeWorkOrderArtPreview(*images->rows[size_t(hovered)],columns);
            if(!result.preview)return std::nullopt;result.hovered=hovered;
        }
        result.nextCursor=end<images->rows.size()?uint32_t(end):0;return result;
    }
    const auto subjects=nativeWorkOrderArtSubjects(order,page,query);
    if(!subjects || cursor>subjects->ids.size() || (listRevision && listRevision!=subjects->listRevision))return std::nullopt;
    result.listRevision=subjects->listRevision;result.total=uint32_t(subjects->ids.size());
    const auto end=std::min(size_t(cursor)+128,subjects->ids.size());
    for(size_t i=cursor;i<end;++i) {
        auto caption=nativeWorkOrderArtSubjectCaption(page,subjects->ids[i]);
        if(!caption || caption->size()>1024)return std::nullopt;
        result.rows.push_back({subjects->ids[i],std::move(*caption),std::nullopt});
    }
    result.nextCursor=end<subjects->ids.size()?uint32_t(end):0;return result;
}
inline WorkOrderDetailEditResult beginWorkOrderArt(df::manager_order& order,uint64_t revision,int32_t option) {
    WorkOrderDetailEditResult result;
    if(!workOrderArtSubjectsReady())return result;
    const auto before=nativeWorkOrderDetails(order);
    if(!before || option<0 || size_t(option)>=before->options.size())return result;
    if(!revision || revision!=before->revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    const auto kind=before->options[size_t(option)].kind;if(kind!=1 && kind!=3)return result;
    // Native21931f writes Image before entering the editor, without rebuilding
    // requirements or clearing the existing art specifier. Back retains this.
    result.outcome=WorkshopOrdersOutcome::Unknown;
    if(kind==3)order.specdata.improvement=df::improvement_type(0);
    result.observation=nativeWorkOrderDetails(order);
    if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
    return result;
}
}
