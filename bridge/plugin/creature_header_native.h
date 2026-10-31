#pragma once
#include "creature_office_native.h"
#include "df/unit_soul.h"
#include "df/personality_moodst.h"
#include "df/identity.h"
#include "df/game_mode.h"
#include "df/job.h"
#include "location_staff_order_native.h"
#include "zone_native.h"
namespace df3d_creature {
// Native8bb4af..8bb650 implements these writes inline, after its SDL text
// helper changes a draft. There is no aggregate rename call on that path.
// Do not call the text helper or borrow its draft/focus/input globals. The
// nickname writes only unit and HF names, not soul or identity names.
// Caller owns epoch/visibility/stale validation. False means no write began;
// exceptions after entry have an unknown outcome and must not be replayed.
inline bool setHeaderCustomName(df::unit* unit,bool profession,const std::string& bytes) {
    if(!unit || bytes.size()>30 || bytes.find('\0')!=std::string::npos)return false;
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x8bb4af,0x1a2,UINT64_C(0x66e693ff90782333)},
            {0x13b3090,0x19,UINT64_C(0x901cd2f6d41c1657)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return false;
    auto& target=profession?unit->custom_profession:unit->name.nickname;
    if(target==bytes)return true;
    target=bytes;
    if(!profession) {
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        auto* figure=reinterpret_cast<df::historical_figure* (*)(df::unit*)>(base+0x13b3090)(unit);
        if(figure)figure->name.nickname=unit->name.nickname;
    }
    return true;
}
struct HeaderActivity {std::string text;int16_t foreground=0,background=0;bool bright=false;};
// Native header CAN_LEARN/control gates precede the semantic formatter.
// Native may refresh the unit HF index and retire stale squad activity/event
// IDs. These are semantic lazy repairs, not owned or restored menu scratch.
// No renderer1390cf0/GPS call is permitted here. Outputs are independently owned.
inline std::optional<HeaderActivity> headerActivity(df::unit* unit) {
    if(!unit)return std::nullopt;
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x138ffd0,0xd20,UINT64_C(0x904926737b452832)},
            {0xd03170,0x12b,UINT64_C(0x90da46373e49508e)},
            {0xd032b0,0x5024,UINT64_C(0xba755d2dfd15322d)},
            {0x13cc610,0x1ab,UINT64_C(0xb9e9ed9744ed0fe3)},
            {0x73230,0x47b,UINT64_C(0x8bb8f157af0b9c69)}, // body and all dispatch tables
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    HeaderActivity result;
    if(!reinterpret_cast<bool (*)(df::unit*,int32_t)>(base+0x73230)(unit,58) ||
       (!reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20)(unit) && !unit->flags3.bits.guest))return result;
    if(unit->job.current_job && !unit->job.current_job->flags.bits.on_break) {
        reinterpret_cast<void (*)(df::job*,std::string*)>(base+0xd03170)(unit->job.current_job,&result.text);
        result.foreground=3;result.bright=true;
    } else {
        reinterpret_cast<void (*)(df::unit*,bool,bool,std::string*,int16_t*,int16_t*,bool*)>(base+0x138ffd0)
            (unit,true,false,&result.text,&result.foreground,&result.background,&result.bright);
    }
    if(result.text.size()>512 || result.foreground<0 || result.foreground>7 || result.background<0 || result.background>7)return std::nullopt;
    return result;
}
struct HeaderName {
    std::string combined,name,profession,translated;
    df3d_area::ZoneOwnerNameColor color;
};
// Same formatter and color flags as native15b8ed/15b902. Reuse the existing
// staff formatter and owner color provider; header width fitting is separate.
// As in those providers, native semantic HF lookup may refresh its cache index.
inline std::optional<HeaderName> headerName(df::unit* unit) {
    if(!unit)return std::nullopt;
    const auto& functions=df3d_area::staffOrderingFunctions();
    if(!functions)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&] {
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x1330500,0x37d)==UINT64_C(0x963e5805735092ee) &&
               hash(0x1330880,0x3ac)==UINT64_C(0xbef834f2b924d785) &&
               hash(0x13e5a90,0x8c)==UINT64_C(0x18f14fd96d2fb5d7) &&
               hash(0xb530b0,0xac)==UINT64_C(0x7c6f66602bdab157) &&
               hash(0x72570,0x98)==UINT64_C(0xa69932c0f279084a) &&
               hash(0xc3a4f0,0x98)==UINT64_C(0x90965a9fe84783f6) &&
               hash(0xa946e0,0x7c2)==UINT64_C(0xdbc3db5f052419ee) &&
               hash(0xd2cb50,0xf0)==UINT64_C(0xf7ab8eceaadda09f);
    }();
    if(!supported)return std::nullopt;
    const auto color=df3d_area::nativeZoneOwnerNameColor(*unit);
    if(!color)return std::nullopt;
    HeaderName result;result.color=*color;
    functions.name(unit,&result.combined,false);
    using Name=void (*)(df::unit*,std::string*);
    reinterpret_cast<Name>(const_cast<uint8_t*>(base+0x1330500))(unit,&result.name);
    reinterpret_cast<df3d_area::StaffOrderingFunctions::Text>(const_cast<uint8_t*>(base+0x1330880))(unit,&result.profession,false);
    // Native15becf resolves historical/identity language_name, then15c18c
    // formats its English form. Returned name is borrowed read-only; output is owned.
    auto* language=reinterpret_cast<df::language_name* (*)(df::unit*)>(const_cast<uint8_t*>(base+0x13e5a90))(unit);
    if(language && language->has_name)
        reinterpret_cast<void (*)(df::language_name*,std::string*,bool,bool)>(const_cast<uint8_t*>(base+0xa946e0))(language,&result.translated,true,false);
    if(result.combined.size()>512 || result.name.size()>512 || result.profession.size()>512 || result.translated.size()>512)return std::nullopt;
    return result;
}
struct HeaderStatus {std::string text;int32_t color=15;};
// Native15c23a..15d588 selects the status inline among drawing calls. Keep
// that priority here; reusable semantic name/relationship/position helpers
// receive owned outputs. Never invoke the containing renderer or gps writers.
inline std::optional<HeaderStatus> headerStatus(df::unit* unit) {
    if(!unit || !df::global::gamemode || *df::global::gamemode!=df::game_mode::DWARF)return std::nullopt;
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x15c23a,0x134e,UINT64_C(0xc8ec4ec556530230)}, // reference only
            {0x19ea80,0x100,UINT64_C(0xefcbaa58578e8c42)}, // mood/emotion tables
            {0x73760,0x4c,UINT64_C(0xd6e159fb1367c80e)},
            {0x72850,0x8b,UINT64_C(0xf9b1c2f8d7f55288)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0x134f250,0x87,UINT64_C(0x9c327e1e67bb8fcc)},
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
            {0x52d3c0,0x288,UINT64_C(0x6e1fbc2416fba9fc)},
            {0xc0f630,0x2c,UINT64_C(0x2f03e40b0a07e0bf)},
            {0x72570,0x98,UINT64_C(0xa69932c0f279084a)},
        };
        for(const auto& pin:pins) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){value^=base[pin.rva+i];value*=UINT64_C(1099511628211);}
            if(value!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    static_assert(offsetof(df::unit,mood)==0x360);
    static_assert(offsetof(df::unit,counters)+offsetof(decltype(df::unit::counters),soldier_mood)==0x814);
    static_assert(offsetof(df::personality_moodst,flags)==0x18);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const int soldier=int(unit->counters.soldier_mood),mood=int(unit->mood);
    if(soldier!=-1) {
        constexpr const char* text[]={"In a martial trance!","Enraged at all enemies!","Throwing a tantrum!","Sunk into depression...","Stumbling obliviously!"};
        constexpr int colors[]={10,4,14,6,3};
        if(soldier>=0 && soldier<5)return HeaderStatus{text[soldier],colors[soldier]};
        return HeaderStatus{"Corrupt Soldier Mood: "+std::to_string(soldier),12};
    }
    if(mood!=-1 && mood!=8) {
        constexpr const char* text[]={"Has the aspect of one fey!","Peculiarly secretive...","Possessed by unknown forces!","Brooding darkly...","Has a horrible fell look!","Stricken by melancholy...","","In a berserk rage!","","Staring off into space..."};
        constexpr int colors[]={15,7,13,8,5,9,11,12,15,2};
        if(mood==6) {
            const bool speech=reinterpret_cast<bool (*)(df::unit*)>(base+0x73760)(unit) ||
                reinterpret_cast<bool (*)(void*,int16_t,int16_t,int32_t)>(base+0x72850)(base+0x24eca48,unit->race,unit->caste,59);
            return HeaderStatus{std::string(unit->flags1.bits.on_ground?"Crawling around ":"Running around ")+(speech?"babbling!":"crazed!"),11};
        }
        if(mood>=0 && mood<10)return HeaderStatus{text[mood],colors[mood]};
        return HeaderStatus{"Corrupt Strange Mood: "+std::to_string(mood),12};
    }
    if(unit->flags3.bits.emotionally_overloaded) {
        if(unit->status.current_soul) {
            const auto& emotions=unit->status.current_soul->personality.emotions;
            if(emotions.size()>65536)return std::nullopt;
            for(const auto* emotion:emotions) {
                if(!emotion)return std::nullopt;
                if(!emotion->flags.bits.failed_to_overcome)continue;
                const char* text=nullptr;
                switch(int(emotion->type)) {
                    case 5:text="Writhing in agony!";break;
                    case 12:text="In existential crisis!";break;
                    case 13:text="Anguished!";break;
                    case 39:text="Lost in despair!";break;
                    case 44:text="Completely dismayed!";break;
                    case 46:text="Distressed!";break;
                    case 64:text="Experiencing mortal fear!";break;
                    case 68:text="Taken by a fright!";break;
                    case 78:return HeaderStatus{std::string("Beside ")+(unit->sex==0?"herself":unit->sex==1?"himself":"itself")+" with grief!",9};
                    case 88:text="Overwhelmed by horror!";break;
                    case 111:text="Wallowing in misery!";break;
                    case 112:text="Truly mortified!";break;
                    case 135:text="Drowning in sadness!";break;
                    case 141:text="Shaken to the core!";break;
                    case 143:text="In emotional shock!";break;
                    case 152:text="Overcome by terror!";break;
                }
                if(text)return HeaderStatus{text,9};
            }
        }
        return HeaderStatus{"Emotionally overloaded!",9};
    }
    HeaderStatus result;
    using Name=void (*)(df::language_name*,std::string*);
    if(unit->relationship_ids[0]!=-1 && reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20)(unit)) {
        auto* owner=reinterpret_cast<df::unit* (*)(df::unit*,int32_t)>(base+0x134f250)(unit,0);
        if(owner)reinterpret_cast<Name>(base+0xa94030)(&owner->name,&result.text);
        else result.text="Somebody";
        result.text.insert(0,"Pet of ");return result;
    }
    if(unit->flags4.bits.mood_succeeded) {
        reinterpret_cast<Name>(base+0xa94030)(&unit->status.artifact_name,&result.text);
        result.text.insert(0,"Creator of ");return result;
    }
    if(auto* hf=df::historical_figure::find(unit->hist_figure_id)) {
        const auto* identity=reinterpret_cast<df::identity* (*)(df::historical_figure*)>(base+0xc0f630)(hf);
        if(identity && int(identity->profession)!=-1)return result;
    }
    const auto position=headerPositionTitle(unit);
    if(!position)return std::nullopt;
    result.text=position->text;return result;
}
}
