#pragma once
#include <cstddef>
#include <cstdint>
#include <tuple>

namespace wm::detail {
using MaterialTileKey = std::tuple<int32_t,int32_t,int32_t>;
struct MaterialTileKeyHash {
  size_t operator()(const MaterialTileKey& p) const noexcept {
    uint64_t h=0;
    const auto mix=[&](int32_t v) {
      uint64_t x=uint32_t(v)+UINT64_C(0x9e3779b97f4a7c15)+h;
      x=(x^(x>>30))*UINT64_C(0xbf58476d1ce4e5b9);
      x=(x^(x>>27))*UINT64_C(0x94d049bb133111eb);
      h=x^(x>>31);
    };
    mix(std::get<0>(p));mix(std::get<1>(p));mix(std::get<2>(p));
    return size_t(h);
  }
};
} // namespace wm::detail
