// Shared host monotonic time for publication stamps across MSVC/GCC processes.
#pragma once
#include <cstdint>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
namespace df3d::shm {
inline uint64_t publicationClockMicros() {
  static const uint64_t frequency = [] {
    LARGE_INTEGER value{}; QueryPerformanceFrequency(&value);
    return static_cast<uint64_t>(value.QuadPart);
  }();
  LARGE_INTEGER value{}; QueryPerformanceCounter(&value);
  const auto ticks = static_cast<uint64_t>(value.QuadPart);
  return (ticks / frequency) * 1000000 + (ticks % frequency) * 1000000 / frequency;
}
}
#endif
