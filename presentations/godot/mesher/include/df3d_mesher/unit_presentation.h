#pragma once
#include "wm/evaluate.h"
namespace df3d::mesher {
// Arrival bootstrapping is immediate, but departure follows the presentation
// clock so a confirmed outcome and its disappearing live sprite share a tick.
struct PresentedUnit {
    wm::EvalResult state;
    float sliceZ = 0;
};
inline PresentedUnit presentUnit(const wm::EvalResult& current, const wm::EvalResult& delayed) {
    auto shown = delayed;
    if (shown.presence != wm::Presence::Present && current.presence == wm::Presence::Present)
        shown = current;
    return {shown, current.presence == wm::Presence::Present ? current.pos.z : shown.pos.z};
}
}
