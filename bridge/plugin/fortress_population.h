#pragma once
#include <array>
#include <cstdint>
#include <cstddef>
#include <limits>
#include <optional>

namespace df3d_session {
struct FortressPopulation {
    int32_t population = 0;
    // DFHack stress categories: most stressed first, as in the session contract.
    std::array<uint32_t, 7> stress{};
};

// The adapter supplies the authoritative membership range and category reader.
// Each person contributes once to population and stress. Invalid categories
// invalidate the whole census instead of publishing inconsistent partial totals.
template<class Range, class CategoryOf>
std::optional<FortressPopulation> fortressPopulation(Range&& people, CategoryOf categoryOf) {
    FortressPopulation result;
    for (auto person : people) {
        const auto category = categoryOf(person);
        if (category < 0 || category >= int(result.stress.size()) ||
            result.population == std::numeric_limits<int32_t>::max()) return {};
        ++result.population;
        ++result.stress[std::size_t(category)];
    }
    return result;
}
}
