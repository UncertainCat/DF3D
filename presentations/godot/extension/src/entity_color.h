#pragma once
#include <godot_cpp/variant/color.hpp>
#include <cstdint>
namespace df3d_godot {
// Placeholder tint for a building / item kind the raws have no art for:
// a hue from the kind name (same hashing as the species placeholder).
inline godot::Color entityKindColor(const char* name) {
    uint32_t h = 2166136261u;
    for (const char* c = name; *c; ++c) {
        h ^= static_cast<unsigned char>(*c);
        h *= 16777619u;
    }
    const auto chan = [](uint32_t v) { return (96.0f + static_cast<float>(v & 0x7F)) / 255.0f; };
    return godot::Color(chan(h), chan(h >> 8), chan(h >> 16), 1.0f);
}



}
