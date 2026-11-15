#pragma once
#include "work_order_art_native.h"
#include "df/artifact_record.h"
#include "df/plant_raw.h"
#include "df/descriptor_shape.h"
#include "df/general_ref_entity_art_image.h"
#include "df/art_image_element_creaturest.h"
#include "df/art_image_element_plantst.h"
#include "df/art_image_element_treest.h"
#include "df/art_image_element_shapest.h"
#include "df/art_image_element_itemst.h"
#include "df/art_image_property_transitive_verbst.h"
#include "df/art_image_property_intransitive_verbst.h"

namespace df3d_production {
struct WorkOrderArtNameQuery {uint8_t component=0;std::string query;uint32_t cursor=0;};
struct WorkOrderArtNameEdit {uint8_t mode=0;int32_t target=-1,displayed=-1,word=-1,part=-1;std::string query;};
inline bool workOrderArtDraftReady() {
    static const bool ready=[] {
        if(!workOrderArtSubjectsReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x210590,0x440,UINT64_C(0x4092b1dad3ddc3d6)},
            {0x2109d0,0x314,UINT64_C(0x9ea4c0c7c7f61cd1)},
            {0x210cf0,0x31f,UINT64_C(0xdb2d7411bc2db4c)},
            {0x211010,0x514,UINT64_C(0x586ab97d44575fec)},
            {0x211530,0x6a2,UINT64_C(0x4640166c015df4eb)},
            {0x211be0,0x3de,UINT64_C(0x7d610bdd71d26a1)},
            {0x211fc0,0x5e6,UINT64_C(0xa837431f77b5dff)},
            {0x144470,0xf6,UINT64_C(0xce6270559be3a0c1)},
            {0x143a10,0x20,UINT64_C(0xfc652224220fb89a)},
            {0x143da0,0x15,UINT64_C(0x101174986420b2b6)},
            {0x143e00,0x15,UINT64_C(0x48bbee0baab3381f)},
            {0x143f40,0x1d,UINT64_C(0x161954ffb6262908)},
            {0x143c70,0x28,UINT64_C(0xeaef3b4de11c8ecf)},
            {0x1441b0,0x4c,UINT64_C(0x41279e8781812b71)},
            {0x1443a0,0x4c,UINT64_C(0x7985235f11b7c066)},
            {0x20b80d,0x7e,UINT64_C(0x17911822ad1ef599)}, // creature fields
            {0x20bb45,0x66,UINT64_C(0xfa2c03762eff5c6b)}, // figure fields
            {0x20be46,0x50,UINT64_C(0x4dc875c22b8cf854)}, // plant fields
            {0x20c182,0x50,UINT64_C(0xb60f387d8e0e952e)}, // tree fields
            {0x20c44b,0x68,UINT64_C(0x8551e2cf31aac2f2)}, // shape fields
            {0x20c721,0x7d,UINT64_C(0xf91a1cdd53b60ef5)}, // object fields
            {0x20c9a4,0x9f,UINT64_C(0x7012efd38fa3a9c6)}, // artifact fields
            {0x20ce7b,0x4e,UINT64_C(0xd3256d44d3aaab60)}, // intransitive relationship
            {0x20d0de,0x48,UINT64_C(0x7bebf5ffcf0ab734)}, // transitive relationship
            {0x20d316,0x164,UINT64_C(0x41882ec1646f5ddb)}, // delete and index repair
            {0xaa3bd0,0x1c3,UINT64_C(0x0f9cd818efc6bad8)}, // creature name
            {0xf2680,0x60,UINT64_C(0x5360a35851800412)}, // caste sex
            {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)}, // native capitalization
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)}, // object description
            {0x1fb510,0xba4,UINT64_C(0xd2fd405d945fae9c)}, // relationship caption
            {0x2044a8,0xb2,UINT64_C(0x31ab93c55097545c)}, // creature caption inputs
            {0x206ab7,0xae,UINT64_C(0x2762c6436f3f35c1)}, // shape caption composition
            {0x2074eb,0x80,UINT64_C(0xacf5bd1a997364f5)}, // object caption inputs
            {0x207f90,0x68,UINT64_C(0xc5c42ebd05959f17)}, // artifact caption composition
            {0x2089cf,0x2c,UINT64_C(0x2dec2f1ac7e5e8ae)}, // actor/target caption inputs
            {0x2091ac,0x5f,UINT64_C(0x2b19dbb2f88221a8)}, // element/property deletion captions
            {0x931860,0x2f9,UINT64_C(0x3f40974d82863764)}, // owned entity name generation
            {0xa92860,0x17cb,UINT64_C(0x627504395969e689)},
            {0x200009,0xc,UINT64_C(0x280ebec615979b82)}, // artwork name category
            {0x1453130,0xf8,UINT64_C(0x8908ab4dc6f55824)}, // world image allocation
            {0x1fa4b0,0x1b3,UINT64_C(0x112cd66c38d24083)}, // owned image deep copy
            {0x1fa3d0,0xe,UINT64_C(0xc117a55367e0c2ac)}, // entity artwork reference
            {0x20b02b,0x2ba,UINT64_C(0xbb08464ccb024519)}, // image registration effects
            {0x71f30,0x53,UINT64_C(0x5eb4fcfbdedb7745)}, // native bounded symbol selection
            {0x1fe5c0,0x1382,UINT64_C(0x3326cd7614642632)}, // shared name component edits
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// Private draft nodes and native list scratch have one owner. No native menu
// is opened, borrowed, or retained. Creating/editing this object cannot install
// an image in the world or change an order; that is a separate Done operation.
// Its lifetime is one bridge safe point; only semantic draft values may persist.
class WorkOrderArtDraft {
    const uint8_t* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df::image_creator_interfacest context;
    WorkOrderArtDraft(df::image_creator_context_type type) {
        context.context=type;
        context.ics.image_ent=df::global::plotinfo->main.fortress_entity;
    }
    template<class T> T* construct(size_t rva) {
        auto* memory=reinterpret_cast<void*(*)(size_t)>(base+0x1539690)(sizeof(T));
        return reinterpret_cast<T*(*)(void*)>(base+rva)(memory);
    }
public:
    WorkOrderArtDraft(const WorkOrderArtDraft&)=delete;
    WorkOrderArtDraft& operator=(const WorkOrderArtDraft&)=delete;
    static std::unique_ptr<WorkOrderArtDraft> create(df::image_creator_context_type type=df::image_creator_context_type::JOB_DETAILS_MAIN) {
        if(!df::global::world || !df::global::plotinfo || !workOrderArtDraftReady())return {};
        return std::unique_ptr<WorkOrderArtDraft>(new WorkOrderArtDraft(type));
    }
    ~WorkOrderArtDraft() {
        reinterpret_cast<void(*)(df::art_image*)>(base+0x144470)(&context.new_image);
        reinterpret_cast<void(*)(df::image_creator_interfacest*)>(base+0x1fb1c0)(&context);
        using Text=decltype(context.art_box.text);
        const auto clear=reinterpret_cast<void(*)(Text*)>(base+0xbb9b0);
        clear(&context.art_box.text);clear(&context.selected_box.text);
    }
    const df::art_image& image() const {return context.new_image;}
    bool generateName() {
        auto* entity=df::global::plotinfo->main.fortress_entity;if(!entity)return false;
        reinterpret_cast<void(*)(df::historical_entity*,df::language_name*,int16_t)>(base+0x931860)(entity,&context.new_image.name,11);
        return true;
    }
    bool canInstall() const {
        const auto* entity=df::global::plotinfo->main.fortress_entity;
        if(!entity || context.new_image.elements.empty())return false;
        const auto& r=entity->resources;const auto n=r.art_image_types.size();
        return n<INT32_MAX && r.art_image_ids.size()==n && r.art_image_subids.size()==n && r.art_image_char.size()==n &&
            r.foreground_color_curses.size()==n && r.background_color_curses.size()==n && r.foreground_color_curses_bright.size()==n &&
            r.foreground_color.size()==n && r.background_color.size()==n;
    }
    // Caller has crossed the uncertain-outcome boundary before this first world
    // write. Native20b02b..20b2a5 registers a commissioned image and its symbol.
    df::art_image* install() {
        int32_t id=-1;int16_t subid=-1;
        auto* image=reinterpret_cast<df::art_image*(*)(df::world*,int32_t*,int16_t*)>(base+0x1453130)(df::global::world,&id,&subid);
        if(!image)return nullptr;
        context.new_image.id=id;context.new_image.subid=subid;
        reinterpret_cast<void(*)(df::art_image*,df::art_image*)>(base+0x1fa4b0)(image,&context.new_image);
        auto* entity=df::global::plotinfo->main.fortress_entity;auto& r=entity->resources;
        image->spec_ref_type=df::specific_ref_type(24);image->quality=df::item_quality(0);
        auto* ref=construct<df::general_ref_entity_art_image>(0x1fa3d0);
        ref->entity_id=entity->id;ref->index=int32_t(r.art_image_types.size());image->ref=ref;
        r.art_image_types.push_back(df::entity_art_image_type(1));r.art_image_ids.push_back(id);r.art_image_subids.push_back(subid);
        std::vector<uint8_t> symbols;int32_t best=0;
        for(auto* e:image->elements) {
            uint8_t symbol=0;int32_t priority=0;e->getSymbol(&symbol,&priority);
            if(priority>best){best=priority;symbols.clear();}
            if(priority==best)symbols.push_back(symbol);
        }
        uint8_t symbol=8;
        if(!symbols.empty())symbol=symbols[size_t(reinterpret_cast<int32_t(*)(int32_t)>(base+0x71f30)(int32_t(symbols.size())))];
        if(symbol==0 || symbol==32 || symbol==255)symbol=8;
        r.art_image_char.push_back(symbol);
        r.foreground_color.push_back(-1);r.background_color.push_back(-1);
        r.foreground_color_curses.push_back(df::curses_color(7));r.foreground_color_curses_bright.push_back(1);r.background_color_curses.push_back(df::curses_color(7));
        return image;
    }
    bool setName(const df::language_name& name) {
        const auto& words=df::global::world->raws.language.words;
        const auto& translations=df::global::world->raws.language.translations;
        if(name.first_name.size()>4096 || name.nickname.size()>4096 || name.language < -1 ||
           (name.language>=0 && (size_t(name.language)>=translations.size() || !translations[size_t(name.language)])))return false;
        for(size_t i=0;i<7;++i)if(name.words[i] < -1 || int(name.parts_of_speech[i])<0 || int(name.parts_of_speech[i])>8 ||
           (name.words[i]>=0 && (size_t(name.words[i])>=words.size() || !words[size_t(name.words[i])])))return false;
        context.new_image.name=name;return true;
    }
    bool editName(uint8_t mode,int target,int displayed,int word,int part,const std::string& query) {
        if(mode>3 || query.size()>4096)return false;
        if(mode==3)return target==-1 && displayed==-1 && word==-1 && part==-1 && query.empty() && generateName();
        if(target<0 || target>6 || displayed<0 || displayed>6)return false;
        if(mode==1) {
            const auto choices=df3d_area::observeNativeLocationNameWords(uint8_t(displayed),query);
            if(target!=displayed || !choices || std::none_of(choices->begin(),choices->end(),[&](const auto& row){return row.word==word && row.partOfSpeech==part;}))return false;
        } else if(mode==2) {
            const auto choice=df3d_area::chooseNativeLocationNameWord(uint8_t(displayed),query);
            if(!choice)return false;word=choice->word;part=choice->partOfSpeech;
        } else {word=-1;part=0;}
        context.new_image.name.words[size_t(target)]=word;
        context.new_image.name.parts_of_speech[size_t(target)]=df::part_of_speech(part);return true;
    }
    std::optional<WorkOrderArtNamePage> namePage(uint8_t component,const std::string& query,uint32_t cursor) {
        const auto& name=context.new_image.name;df3d_area::LocationNameValue value;
        value.firstNameCp437=name.first_name;value.nicknameCp437=name.nickname;value.words=name.words;
        for(size_t i=0;i<7;++i)value.parts[i]=int16_t(name.parts_of_speech[i]);
        value.language=name.language;value.type=int16_t(name.type);value.hasName=name.has_name;
        const auto text=df3d_area::formatNativeLocationName(value);
        const auto choices=df3d_area::observeNativeLocationNameWords(component,query,name.language);
        if(!text || !choices || choices->size()>262144 || cursor>choices->size())return std::nullopt;
        WorkOrderArtNamePage page;page.nativeHeader=text->native;page.englishHeader=text->english;
        page.component=component;page.query=query;page.cursor=cursor;page.total=uint32_t(choices->size());
        const auto end=std::min(choices->size(),size_t(cursor)+128);
        page.choices.assign(choices->begin()+cursor,choices->begin()+end);page.nextCursor=end<choices->size()?uint32_t(end):0;
        return page;
    }
    std::optional<std::string> draftRowCaption(size_t index) {
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        auto& image=context.new_image;std::string result;
        if(index<image.elements.size())image.elements[index]->getName(&result,true,true,false);
        else {
            index-=image.elements.size();if(index>=image.properties.size())return std::nullopt;
            image.properties[index]->getName(&result,&image,true,false);
        }
        reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&result);
        if(result.size()>1024)return std::nullopt;return result;
    }
    std::optional<std::vector<std::string>> preview(uint16_t columns) const {
        if(!columns || columns>256)return std::nullopt;
        // Native2125b0 leaves the draft description empty until an element exists.
        if(context.new_image.elements.empty())return std::vector<std::string>{};
        return nativeWorkOrderArtPreview(context.new_image,columns);
    }
    // Full native captions; viewport clipping is the presentation's job.
    // Call only for a pair returned by choices(), never an arbitrary raw index.
    std::optional<std::string> choiceCaption(int32_t kind,int32_t id,int32_t secondary) const {
        std::string result;
        const auto capitalize=[&]{reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&result);};
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        switch(kind) {
        case 7: {
            reinterpret_cast<void(*)(int16_t,std::string*,bool,int16_t)>(base+0xaa3bd0)(int16_t(id),&result,false,int16_t(secondary));
            capitalize();
            const auto sex=reinterpret_cast<uint8_t(*)(void*,int16_t,int16_t)>(base+0xf2680)(&df::global::world->raws.creatures,int16_t(id),int16_t(secondary));
            if(sex==0 || sex==1){result+=reinterpret_cast<const char*>(base+0x15e90d8);result+=char(sex==1?0x0b:0x0c);}
            break;
        }
        case 8:return nativeWorkOrderArtSubjectCaption(1,id);
        case 9:case 10: {
            auto* plant=df::plant_raw::find(id);if(!plant)return std::nullopt;
            result=plant->name;capitalize();break;
        }
        case 11: {
            auto* shape=df::descriptor_shape::find(id);if(!shape)return std::nullopt;
            if(secondary>=0){if(size_t(secondary)>=shape->adj.size() || !shape->adj[size_t(secondary)])return std::nullopt;result=*shape->adj[size_t(secondary)];result+=reinterpret_cast<const char*>(base+0x15e873c);}
            result+=shape->name;capitalize();break;
        }
        case 12: {
            using Describe=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
            reinterpret_cast<Describe>(base+0xa82c10)(&result,int16_t(id),int16_t(secondary),-1,-1,1,0,false,nullptr,-1,-1,true,0,0);
            capitalize();break;
        }
        case 13: {
            auto* artifact=df::artifact_record::find(id);if(!artifact)return std::nullopt;
            result=artifact->name.has_name?nativeWorkOrderArtNameCaption(artifact->name):reinterpret_cast<const char*>(base+0x1615748);break;
        }
        case 14:reinterpret_cast<void(*)(std::string*,int32_t,bool)>(base+0x1fb510)(&result,id,secondary!=0);break;
        default:return std::nullopt;
        }
        if(result.size()>1024)return std::nullopt;
        return result;
    }
    // Return semantic IDs in precisely the native filtered order. Secondary IDs
    // distinguish castes, shape adjectives, item subtypes, and verb transitivity.
    std::optional<std::vector<std::pair<int32_t,int32_t>>> choices(int32_t kind,const std::string& query) {
        if(kind<7 || kind>14 || query.size()>128)return std::nullopt;
        context.current_option=df::image_creator_option_type(kind);context.filter=query;
        std::vector<std::pair<int32_t,int32_t>> result;
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        const auto single=[&](auto& rows,size_t rva) {
            using Rows=std::remove_reference_t<decltype(rows)>;
            reinterpret_cast<void(*)(df::image_creator_interfacest*,Rows*)>(base+rva)(&context,&rows);
            if(rows.size()>262144)return false;
            for(auto value:rows)result.emplace_back(value,-1);
            return true;
        };
        const auto paired=[&](auto& rows,auto& secondary,size_t rva) {
            using Rows=std::remove_reference_t<decltype(rows)>;
            using Secondary=std::remove_reference_t<decltype(secondary)>;
            reinterpret_cast<void(*)(df::image_creator_interfacest*,Rows*,Secondary*)>(base+rva)(&context,&rows,&secondary);
            if(rows.size()>262144 || rows.size()!=secondary.size())return false;
            for(size_t i=0;i<rows.size();++i)result.emplace_back(rows[i],secondary[i]);
            return true;
        };
        switch(kind) {
        case 7:if(!paired(context.new_image_race,context.new_image_caste,0x210590))return std::nullopt;break;
        case 8:
            reinterpret_cast<void(*)(df::image_creator_interfacest*,std::vector<df::historical_figure*>*)>(base+0x20f300)(&context,&context.new_image_hf);
            if(context.new_image_hf.size()>262144)return std::nullopt;
            for(auto* figure:context.new_image_hf){if(!figure)return std::nullopt;result.emplace_back(figure->id,-1);}break;
        case 9:if(!single(context.new_image_plant,0x2109d0))return std::nullopt;break;
        case 10:if(!single(context.new_image_tree,0x210cf0))return std::nullopt;break;
        case 11:if(!paired(context.new_image_shape,context.new_image_shape_adj,0x211010))return std::nullopt;break;
        case 12:if(!paired(context.new_image_item,context.new_image_item_subtype,0x211530))return std::nullopt;break;
        case 13:
            reinterpret_cast<void(*)(df::image_creator_interfacest*,std::vector<df::artifact_record*>*)>(base+0x211be0)(&context,&context.new_image_artifact);
            if(context.new_image_artifact.size()>262144)return std::nullopt;
            for(auto* artifact:context.new_image_artifact){if(!artifact)return std::nullopt;result.emplace_back(artifact->id,-1);}break;
        case 14:
            reinterpret_cast<void(*)(df::image_creator_interfacest*)>(base+0x211fc0)(&context);
            if(context.new_image_property.size()>262144 || context.new_image_property.size()!=context.new_image_property_transitive.size())return std::nullopt;
            for(size_t i=0;i<context.new_image_property.size();++i)result.emplace_back(context.new_image_property[i],context.new_image_property_transitive[i]?1:0);
            break;
        }
        return result;
    }
    bool addElement(int32_t kind,int32_t id,int32_t secondary,int32_t quantity) {
        if(kind<7 || kind>13 || quantity<0 || quantity>1000000000 || context.new_image.elements.size()>=256)return false;
        const auto rows=choices(kind,{});
        if(!rows || std::find(rows->begin(),rows->end(),std::make_pair(id,secondary))==rows->end())return false;
        std::unique_ptr<df::art_image_element> element;
        if(kind==7 || kind==8) {
            auto* row=construct<df::art_image_element_creaturest>(0x143a10);element.reset(row);
            if(kind==7){row->race=id;row->caste=int16_t(secondary);row->histfig=-1;}
            else {auto* figure=df::historical_figure::find(id);if(!figure)return false;row->race=figure->race;row->caste=figure->caste;row->histfig=id;}
        } else if(kind==9) {
            auto* row=construct<df::art_image_element_plantst>(0x143da0);element.reset(row);row->plant_id=id;
        } else if(kind==10) {
            auto* row=construct<df::art_image_element_treest>(0x143e00);element.reset(row);row->plant_id=id;
        } else if(kind==11) {
            auto* row=construct<df::art_image_element_shapest>(0x143f40);element.reset(row);row->shape_id=id;row->shape_adj=int16_t(secondary);
        } else {
            auto* row=construct<df::art_image_element_itemst>(0x143c70);element.reset(row);
            if(kind==12){row->item_type=df::item_type(id);row->item_subtype=int16_t(secondary);}
            else {
                auto* artifact=df::artifact_record::find(id);if(!artifact)return false;
                row->item_id=id;
                if(auto* item=artifact->item){row->item_type=item->getType();row->item_subtype=item->getSubtype();row->mat_type=item->getMaterial();row->mat_index=int16_t(item->getMaterialIndex());row->flags=item->flags;}
            }
        }
        element->count=quantity>0?quantity:-1;
        context.new_image.elements.push_back(element.get());element.release();return true;
    }
    bool addRelationship(int32_t verb,bool transitive,int32_t actor,int32_t target=-1) {
        const auto size=context.new_image.elements.size();
        if(actor<0 || size_t(actor)>=size || context.new_image.properties.size()>=256)return false;
        if(transitive?(target<0 || size_t(target)>=size || target==actor):target!=-1)return false;
        const auto rows=choices(14,{});
        if(!rows || std::find(rows->begin(),rows->end(),std::make_pair(verb,transitive?1:0))==rows->end())return false;
        std::unique_ptr<df::art_image_property> property;
        if(transitive) {
            auto* row=construct<df::art_image_property_transitive_verbst>(0x1441b0);property.reset(row);
            row->subject=actor;row->object=target;row->verb=df::art_image_property_verb(verb);
        } else {
            auto* row=construct<df::art_image_property_intransitive_verbst>(0x1443a0);property.reset(row);
            row->subject=actor;row->verb=df::art_image_property_verb(verb);
        }
        context.new_image.properties.push_back(property.get());property.release();return true;
    }
    // Native20d316..20d475: element rows precede property rows. Removing an
    // element removes dependent relationships and shifts surviving indices.
    bool erase(int32_t index) {
        auto& elements=context.new_image.elements;auto& properties=context.new_image.properties;
        if(index<0 || size_t(index)>=elements.size()+properties.size())return false;
        if(size_t(index)>=elements.size()) {
            const auto position=size_t(index)-elements.size();delete properties[position];properties.erase(properties.begin()+position);return true;
        }
        delete elements[size_t(index)];elements.erase(elements.begin()+index);
        for(size_t i=properties.size();i-- >0;) {
            auto* property=properties[i];bool remove=false;
            if(int(property->getType())==0) {
                auto* row=static_cast<df::art_image_property_transitive_verbst*>(property);
                remove=row->subject==index || row->object==index;
                if(!remove){if(row->subject>index)--row->subject;if(row->object>index)--row->object;}
            } else if(int(property->getType())==1) {
                auto* row=static_cast<df::art_image_property_intransitive_verbst*>(property);
                remove=row->subject==index;if(!remove && row->subject>index)--row->subject;
            }
            if(remove){delete property;properties.erase(properties.begin()+i);}
        }
        return true;
    }
};

// Local draft edits are reconstructed from semantic values for this safe point.
// This page builder never installs a world image. Name generation consumes RNG
// and is dispatched only as a write intent.
inline std::optional<WorkOrderArtPage> nativeArtDraftPage(WorkOrderArtPage root,uint64_t sourceRevision,int16_t page,
    WorkOrderArtDraftValue value,uint8_t action,const std::optional<WorkOrderArtDraftElementValue>& element,
    const std::optional<WorkOrderArtDraftRelationshipValue>& relationship,int32_t deleteIndex,
    const std::string& query,uint32_t cursor,uint64_t listRevision,uint16_t columns,
    const WorkOrderArtNameQuery* nameQuery=nullptr,const WorkOrderArtNameEdit* nameEdit=nullptr,
    df::image_creator_context_type contextType=df::image_creator_context_type::JOB_DETAILS_MAIN) {
    if((page<6 && page!=-1) || page>18 || (action>4 && action!=6) || query.size()>128 || !columns || columns>256 ||
       value.elements.size()>256 || value.relationships.size()>256)return std::nullopt;
    auto draft=WorkOrderArtDraft::create(contextType);if(!draft)return std::nullopt;
    if(value.name && !draft->setName(*value.name))return std::nullopt;
    for(const auto& e:value.elements)if(!draft->addElement(e.kind,e.id,e.secondary,e.quantity))return std::nullopt;
    for(const auto& r:value.relationships)if(!draft->addRelationship(r.verb,r.transitive,r.actor,r.target))return std::nullopt;
    if(action==6) {
        if(!nameEdit || !draft->editName(nameEdit->mode,nameEdit->target,nameEdit->displayed,nameEdit->word,nameEdit->part,nameEdit->query))return std::nullopt;
        value.name=draft->image().name;
    }
    if(action==4){if(!draft->generateName())return std::nullopt;value.name=draft->image().name;page=6;}
    if(action==1) {
        if(!element || !draft->addElement(element->kind,element->id,element->secondary,element->quantity))return std::nullopt;
        value.elements.push_back(*element);page=6;
    } else if(action==2) {
        if(!relationship || !draft->addRelationship(relationship->verb,relationship->transitive,relationship->actor,relationship->target))return std::nullopt;
        value.relationships.push_back(*relationship);page=6;
    } else if(action==3) {
        if(!draft->erase(deleteIndex))return std::nullopt;
        if(size_t(deleteIndex)<value.elements.size())value.elements.erase(value.elements.begin()+deleteIndex);
        value.relationships.clear();
        for(const auto* p:draft->image().properties) {
            if(int(const_cast<df::art_image_property*>(p)->getType())==0) {
                const auto* r=static_cast<const df::art_image_property_transitive_verbst*>(p);
                value.relationships.push_back({int(r->verb),true,r->subject,r->object});
            } else {
                const auto* r=static_cast<const df::art_image_property_intransitive_verbst*>(p);
                value.relationships.push_back({int(r->verb),false,r->subject,-1});
            }
        }
        page=value.elements.empty()?6:17;
    }
    std::optional<WorkOrderArtPage> result=std::move(root);
    if(page==-1){result->draft=value;result->draftDescription=std::vector<std::string>{};return result;}
    result->page=page;result->rows.clear();result->draft=value;
    result->draftDescription=draft->preview(columns);if(!result->draftDescription)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    std::vector<std::pair<int32_t,int32_t>> candidates;
    if(page==18) {
        if(!nameQuery || !value.name)return std::nullopt;
        result->name=draft->namePage(nameQuery->component,nameQuery->query,nameQuery->cursor);
        if(!result->name)return std::nullopt;
    } else if(page==6) {
        constexpr std::pair<int32_t,size_t> options[]={{7,0x15f7220},{8,0x16156e8},{9,0x16156e0},{10,0x1615704},{11,0x16156fc},{12,0x1615728},{13,0x15edd20},{14,0x1615710},{17,0x1615738}};
        for(const auto& [id,rva]:options){candidates.emplace_back(id,-1);result->rows.push_back({id,reinterpret_cast<const char*>(base+rva),std::nullopt});}
    } else if(page<=14) {
        const auto rows=draft->choices(page,query);if(!rows)return std::nullopt;candidates=*rows;
    } else {
        if(page==16 && (!relationship || !relationship->transitive || relationship->actor<0 || size_t(relationship->actor)>=value.elements.size()))return std::nullopt;
        const auto count=value.elements.size()+(page==17?value.relationships.size():0);
        for(size_t i=0;i<count;++i)if(page!=16 || int32_t(i)!=relationship->actor)candidates.emplace_back(int32_t(i),-1);
    }
    uint64_t hash=sourceRevision;
    const auto number=[&](uint64_t v){for(unsigned i=0;i<8;++i){hash^=v&255;hash*=UINT64_C(1099511628211);v>>=8;}};
    number(page);for(unsigned char c:query)number(c);
    for(const auto& e:value.elements){number(e.kind);number(e.id);number(e.secondary);number(e.quantity);}
    for(const auto& r:value.relationships){number(r.verb);number(r.transitive);number(r.actor);number(r.target);}
    if(value.name){for(unsigned char c:value.name->first_name)number(c);for(unsigned char c:value.name->nickname)number(c);for(auto word:value.name->words)number(word);for(auto part:value.name->parts_of_speech)number(int(part));number(value.name->language);number(int(value.name->type));number(value.name->has_name);}
    for(const auto& [id,secondary]:candidates){number(id);number(secondary);}
    result->listRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    if(cursor>candidates.size() || (action==0 && listRevision && listRevision!=result->listRevision))return std::nullopt;
    result->total=uint32_t(candidates.size());
    if(page!=6 && page!=18) {
        const auto end=std::min(size_t(cursor)+128,candidates.size());
        for(size_t i=cursor;i<end;++i) {
            const auto [id,secondary]=candidates[i];
            auto caption=page<=14?draft->choiceCaption(page,id,secondary):draft->draftRowCaption(size_t(id));
            if(!caption)return std::nullopt;
            result->rows.push_back({id,std::move(*caption),std::nullopt,secondary});
        }
        result->nextCursor=end<candidates.size()?uint32_t(end):0;
    }
    return result;
}
inline std::optional<WorkOrderArtPage> nativeWorkOrderArtDraftPage(df::manager_order& order,int16_t page,
    WorkOrderArtDraftValue value,uint8_t action,const std::optional<WorkOrderArtDraftElementValue>& element,
    const std::optional<WorkOrderArtDraftRelationshipValue>& relationship,int32_t deleteIndex,
    const std::string& query,uint32_t cursor,uint64_t listRevision,uint16_t columns,
    const WorkOrderArtNameQuery* nameQuery=nullptr,const WorkOrderArtNameEdit* nameEdit=nullptr) {
    auto root=nativeWorkOrderArtPage(order,-1,{},0,0);if(!root)return std::nullopt;
    const auto details=nativeWorkOrderDetails(order);if(!details)return std::nullopt;
    return nativeArtDraftPage(std::move(*root),details->revision,page,std::move(value),action,element,
        relationship,deleteIndex,query,cursor,listRevision,columns,nameQuery,nameEdit);
}
inline WorkOrderDetailEditResult commitWorkOrderArtDraft(df::manager_order& order,uint64_t revision,const WorkOrderArtDraftValue& value) {
    WorkOrderDetailEditResult result;
    const auto before=nativeWorkOrderDetails(order);
    if(!before || !value.name || value.elements.empty() || value.elements.size()>256 || value.relationships.size()>256)return result;
    if(!revision || before->revision!=revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    auto draft=WorkOrderArtDraft::create();if(!draft || !draft->setName(*value.name))return result;
    for(const auto& e:value.elements)if(!draft->addElement(e.kind,e.id,e.secondary,e.quantity))return result;
    for(const auto& r:value.relationships)if(!draft->addRelationship(r.verb,r.transitive,r.actor,r.target))return result;
    if(!draft->canInstall())return result;
    result.outcome=WorkshopOrdersOutcome::Unknown;
    auto* image=draft->install();if(!image)return result;
    order.art_spec.type=df::job_art_specifier_type(3);order.art_spec.id=image->id;order.art_spec.subid=image->subid;
    if(order.items)rebuildWorkOrderDetailRequirements(order);
    result.observation=nativeWorkOrderDetails(order);
    if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
    return result;
}
}
