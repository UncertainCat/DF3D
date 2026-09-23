#pragma once
#include <godot_cpp/variant/variant.hpp>
#include <initializer_list>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include "wm/management_enums.h"

namespace df3d_godot {
// Validate before Variant conversion: IDs are integers, never rounded floats or
// numeric strings. Optional fields retain the domain-specific sentinel defaults.
inline bool managementDictionaryTypes(const godot::Dictionary& data,
    std::initializer_list<const char*> integers, godot::String& error) {
    using godot::Variant;
    auto typed=[&](const char* key,Variant::Type type,bool required=false) {
        if(!data.has(key)) {
            if(required) { error=godot::String("Missing management field: ")+key;return false; }
            return true;
        }
        if(data[key].get_type()!=type) { error=godot::String("Wrong management field type: ")+key;return false; }
        return true;
    };
    if(!typed("action",Variant::INT,true))return false;
    for(auto key:integers)if(!typed(key,Variant::INT))return false;
    for(auto key:{"definition","query","recipe"})if(!typed(key,Variant::STRING))return false;
    for(auto key:{"give","unlink","cancel","remove_condition","pending_only","announcements_only"})
        if(!typed(key,Variant::BOOL))return false;
    if(!typed("origin",Variant::VECTOR3I)||!typed("items",Variant::ARRAY))return false;
    if(data.has("items")) {
        godot::Array ids=data["items"];
        for(int i=0;i<ids.size();++i)if(ids[i].get_type()!=Variant::INT) {
            error="Construction item identities must be integers";return false;
        }
    }
    return true;
}
inline bool managementRequiredFields(const godot::Dictionary& data, godot::String& error) {
    using A=wm::ManagementAction;
    const int64_t raw=data["action"];
    if(raw<0 || raw>static_cast<int64_t>(A::CreatureInspect))return true; // domain range guard follows
    const auto action=static_cast<A>(raw);
    auto require=[&](const char* key) {
        if(data.has(key))return true;
        error=godot::String("Missing management field: ")+key;return false;
    };
    switch(action) {
    case A::Preview: case A::Place:
        return require("definition") && require("origin");
    case A::InspectAtTile: case A::RemoveConstruction: case A::AreaInspectAtTile: case A::AreaCreate:
        return require("origin");
    case A::Inspect: case A::Remove: return require("building_id");
    case A::AreaInspect: case A::AreaUpdate: case A::AreaDelete: case A::AreaLink: return require("id");
    default: return true; // other domain identities retain their typed model/schema validation
    }
}
} // namespace df3d_godot
