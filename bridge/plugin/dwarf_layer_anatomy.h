#pragma once
// DF3D's explicit missing-limb enhancement for the named vanilla dwarf map
// layers. Appearance references are permitted here. This is not a native rule:
// vanilla 53.16 map layers lack BP_PRESENT. See BODY_PART_GRAPHICS_INVESTIGATION.
#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <utility>

namespace df3d_appearance::anatomy {
enum class Region : uint8_t { None, RightArm, LeftArm, RightHand, LeftHand,
                             RightLeg, LeftLeg, RightFoot, LeftFoot, Head };
constexpr uint16_t bit(Region r) { return r==Region::None ? 0 : uint16_t(1u << (unsigned(r)-1)); }

inline Region region(std::string_view page, std::string_view name) {
    if (page=="DWARF_BODY") {
        constexpr std::array<std::pair<std::string_view,Region>,8> names{{
            {"_RIGHT_SHOULDER",Region::RightArm},{"_LEFT_SHOULDER",Region::LeftArm},
            {"_RIGHT_HAND",Region::RightHand},{"_LEFT_HAND",Region::LeftHand},
            {"_RIGHT_LEG",Region::RightLeg},{"_LEFT_LEG",Region::LeftLeg},
            {"_RIGHT_FOOT",Region::RightFoot},{"_LEFT_FOOT",Region::LeftFoot}}};
        for (auto [label,r]:names) {
            const auto pos=name.find(label);
            if(pos!=name.npos && (pos+label.size()==name.size() || name[pos+label.size()]=='_')) return r;
        }
        if(name.find("_FACE_")!=name.npos) return Region::Head;
    }
    if(page=="DWARF_HAIR") {
        for(std::string_view label:{"BEARD_","LONG_","MID_","SHORT_","STUBBLE_"})
            if(name.starts_with(label)) return Region::Head;
    }
    if(page!="DWARF_WEARABLES" && page!="WIELDABLES") return Region::None;
    constexpr std::array<std::pair<std::string_view,Region>,8> clothes{{
        {"CLOTHING_RA_",Region::RightArm},{"CLOTHING_LA_",Region::LeftArm},
        {"CLOTHING_RH_",Region::RightHand},{"CLOTHING_LH_",Region::LeftHand},
        {"CLOTHING_RL_",Region::RightLeg},{"CLOTHING_LL_",Region::LeftLeg},
        {"CLOTHING_RF_",Region::RightFoot},{"CLOTHING_LF_",Region::LeftFoot}}};
    for(auto [label,r]:clothes) if(name.starts_with(label)) return r;
    if(page=="DWARF_WEARABLES") {
        for(std::string_view label:{"CLOTHING_CAP","CLOTHING_CROWN","CLOTHING_HELM","CLOTHING_HOOD",
                                  "CLOTHING_MASK","CLOTHING_TURBAN","CLOTHING_EARRING",
                                  "CLOTHING_SCARF_HEAD","CLOTHING_VEIL_HEAD"})
            if(name==label || (name.starts_with(label) && name[label.size()]=='_')) return Region::Head;
    }
    return Region::None;
}

inline bool hideNamedLayer(uint16_t missing, std::string_view page, std::string_view name, bool explicitCondition) {
    // A mod's explicit BP_MISSING stump (or other anatomical rule) wins over
    // our fallback association. Never reinterpret its chosen layer as intact.
    return !explicitCondition && (missing & bit(region(page,name)))!=0;
}

struct Part { std::string_view token; int parent=-1; bool missing=false; };
// Unknown parts remain visible. Walk actual connections, including a missing
// ancestor even if the game's descendant flags have not arrived yet. Bounded
// traversal also tolerates malformed/cyclic plans without hanging the bridge.
template<class ReadPart>
uint16_t missingRegions(size_t count, ReadPart read) {
    uint16_t mask=0;
    for(size_t i=0;i<count;++i) {
        auto part=read(i);
        Region r=Region::None;
        if(part.token=="RUA") r=Region::RightArm;
        else if(part.token=="LUA") r=Region::LeftArm;
        else if(part.token=="RH") r=Region::RightHand;
        else if(part.token=="LH") r=Region::LeftHand;
        else if(part.token=="RUL" || part.token=="RLL") r=Region::RightLeg;
        else if(part.token=="LUL" || part.token=="LLL") r=Region::LeftLeg;
        else if(part.token=="RF") r=Region::RightFoot;
        else if(part.token=="LF") r=Region::LeftFoot;
        else if(part.token=="HD") r=Region::Head;
        if(r==Region::None) continue;
        int p=int(i);
        for(size_t depth=0; depth<count && p>=0 && size_t(p)<count; ++depth) {
            auto ancestor=read(size_t(p));
            if(ancestor.missing) {mask|=bit(r);break;}
            p=ancestor.parent;
        }
    }
    return mask;
}

template<class StatusRange, class Mix>
void fingerprintMissing(const StatusRange& status, Mix mix) {
    mix(static_cast<uint32_t>(status.size()));
    for(const auto& s:status) mix(s.bits.missing ? 1u:0u);
}
} // namespace df3d_appearance::anatomy
