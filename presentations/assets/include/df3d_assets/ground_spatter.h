#pragma once
#include <string>
#include <string_view>
#include <algorithm>
#include <cstdint>
#include <limits>
#include <map>

namespace df3d::assets {
struct SpatterPile {
  std::string family;
  uint64_t amount{};
  uint8_t density() const { return static_cast<uint8_t>(std::min<uint64_t>(amount,255)); }
};
// A tile has one terrain stain, not competing coplanar decals. Combine sources
// using the same art before selecting the largest pile. Lexical ties are stable
// across packet order. This is DF3D policy, not a recovered native mixing rule.
class SpatterPiles {
public:
  void add(std::string_view family,uint8_t amount) {
    if(family.empty() || !amount) return;
    auto& total=amounts_[std::string(family)];
    total+=std::min<uint64_t>(amount,std::numeric_limits<uint64_t>::max()-total);
  }
  SpatterPile dominant() const {
    SpatterPile result;
    for(const auto& [family,amount]:amounts_)
      if(amount>result.amount) result={family,amount};
    return result;
  }
private:
  std::map<std::string,uint64_t,std::less<>> amounts_;
};
// Presentation policy only. Material identity remains unmodified in the model.
// Unrecognized materials are kept semantically but not painted as false blood.
inline std::string_view spatterFamily(std::string_view material) {
  const auto suffix=material.substr(material.rfind(':')==std::string_view::npos ? 0 : material.rfind(':')+1);
  if(suffix=="BLOOD") return "SPATTER_BLOOD_RED";
  if(suffix=="ICHOR") return "SPATTER_BLOOD_ICHOR";
  if(suffix=="GOO") return "SPATTER_BLOOD_GOO";
  if(suffix=="VOMIT") return "SPATTER_VOMIT";
  if(suffix=="MUD") return "SPATTER_MUD";
  if(suffix=="WATER") return "SPATTER_WATER";
  if(suffix=="MAGMA") return "SPATTER_MAGMA";
  if(suffix=="SLIME") return "SPATTER_SLIME";
  return {};
}
inline bool spatterFull(uint8_t amount) { return amount>=100; }
// Stable tile variation; these density bands are presentation approximations
// until native density/selection rules have been captured as a reference.
inline std::string spatterVariant(uint8_t amount,uint8_t neighbors,int32_t x,int32_t y) {
  const uint32_t variation=(uint32_t(x)*73856093u)^(uint32_t(y)*19349663u);
  if(!spatterFull(amount)) return "PARTIAL_"+std::to_string(std::clamp((int(amount)+24)/25,1,4))+char('A'+variation%4);
  static constexpr std::string_view sides[]{"ISOLATED","N","S","NS","W","NW","SW","NSW","E","NE","SE","NSE","WE","NWE","SWE","NSWE"};
  std::string result="FULL_"+std::string(sides[neighbors&15]);
  if((neighbors&15)==15) result+="_"+std::string(1,char('A'+variation%5));
  return result;
}
}
