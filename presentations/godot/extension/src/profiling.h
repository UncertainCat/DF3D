#pragma once
// Engine-independent, opt-in process profiling. Names must remain valid for
// the lifetime of their Scope (string literals are the usual call site).
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace df3d::profiling {
enum class Mode { Off, Basic, Deep };
inline const char* modeName(Mode mode) noexcept {
    switch (mode) {
        case Mode::Basic: return "basic";
        case Mode::Deep: return "deep";
        default: return "off";
    }
}

inline Mode modeFromValues(const char* primary, const char* legacy) noexcept {
    // An explicitly supplied empty/invalid primary value also disables the
    // profiler; legacy compatibility applies only when the primary is unset.
    if (primary) {
        if (std::strcmp(primary, "basic") == 0) return Mode::Basic;
        if (std::strcmp(primary, "deep") == 0) return Mode::Deep;
        return Mode::Off;
    }
    return legacy && std::strcmp(legacy, "1") == 0 ? Mode::Basic : Mode::Off;
}
inline Mode modeFromEnvironment() noexcept {
    return modeFromValues(std::getenv("DF3D_PROFILE"), std::getenv("DF3D_STAGE_PROFILE"));
}

struct Event {
    std::string name;
    double startUs = 0;
    double durationUs = 0;
    uint64_t thread = 0;
};
struct Snapshot {
    std::vector<Event> events;
    uint64_t dropped = 0;
    double evictedThroughUs = 0;
};

class Profiler {
public:
    using Clock = double (*)();
    static constexpr size_t MaxEvents = 32768;
    static double defaultClock() noexcept {
        return std::chrono::duration<double, std::micro>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
    }
    explicit Profiler(Mode mode, size_t capacity = MaxEvents, Clock clock = defaultClock)
        : mode_(mode), capacity_(std::min(capacity, MaxEvents)), clock_(clock ? clock : defaultClock) {}
    Mode mode() const noexcept { return mode_; }
    static uint64_t currentThreadId() noexcept { return threadId(); }
    double now() const { return clock_(); }
    // Explicit clock anchor for synchronizing external script traces.
    double nowUs() const { return clock_(); }
    Snapshot snapshot() const {
        Snapshot result;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            result.dropped = dropped_;
            result.evictedThroughUs = evictedThroughUs_;
            result.events.reserve(events_.size());
            for (size_t i = 0; i < events_.size(); ++i)
                result.events.push_back(events_[(oldest_ + i) % events_.size()]);
        }
        // Scopes finish out of start-time order (nesting and multiple threads).
        // Retain latest completed events, but export in timestamp order. Stable
        // ties preserve recording order. Sorting does not block producers.
        std::stable_sort(result.events.begin(), result.events.end(),
            [](const Event& a, const Event& b) { return a.startUs < b.startUs; });
        return result;
    }
    // Call at a deliberate capture boundary. Existing scopes that finish later
    // are included in the new capture, with their original start timestamps.
    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        events_.clear();
        oldest_ = 0;
        dropped_ = 0;
        evictedThroughUs_ = 0;
    }
    void record(const char* name, double startUs, double durationUs) noexcept {
        if (mode_ != Mode::Deep) return;
        std::lock_guard<std::mutex> lock(mutex_);
        if (capacity_ == 0) {
            ++dropped_;
            evictedThroughUs_ = std::max(evictedThroughUs_, startUs + durationUs);
            return;
        }
        try {
            // Reserve the exact configured event bound once, avoiding vector
            // growth beyond a non-power-of-two capacity. Off/Basic never enter.
            if (events_.capacity() < capacity_) events_.reserve(capacity_);
            // Construct before overwriting: failed name allocation drops this
            // new event while preserving every previously retained event.
            Event event{name ? name : "", startUs, durationUs, threadId()};
            if (events_.size() < capacity_) events_.push_back(std::move(event));
            else {
                const auto& evicted = events_[oldest_];
                evictedThroughUs_ = std::max(evictedThroughUs_, evicted.startUs + evicted.durationUs);
                events_[oldest_] = std::move(event);
                oldest_ = (oldest_ + 1) % capacity_;
                ++dropped_;
            }
        } catch (...) {
            // Profiling must not turn allocation pressure into an application
            // failure. Snapshot/export itself remains an explicit allocating API.
            ++dropped_;
            evictedThroughUs_ = std::max(evictedThroughUs_, startUs + durationUs);
        }
    }
private:
    static uint64_t threadId() noexcept {
        static std::atomic<uint64_t> next{1};
        static thread_local const uint64_t id = next.fetch_add(1, std::memory_order_relaxed);
        return id;
    }
    const Mode mode_;
    const size_t capacity_;
    const Clock clock_;
    mutable std::mutex mutex_;
    std::vector<Event> events_;
    size_t oldest_ = 0;
    uint64_t dropped_ = 0;
    // Conservative boundary: no dropped completed span starts after this time.
    double evictedThroughUs_ = 0;
};

inline Profiler& global() {
    // Configuration is read once per process. No clock reads or event storage
    // allocations occur during initialization, including in Off mode.
    static Profiler profiler(modeFromEnvironment());
    return profiler;
}

inline Profiler& detailed() {
    static Profiler disabled(Mode::Off);
    return global().mode() == Mode::Deep ? global() : disabled;
}

inline double timestampUs() { return global().mode() == Mode::Off ? 0.0 : global().nowUs(); }
inline double elapsedMs(double startUs) {
    return global().mode() == Mode::Off ? 0.0 : (global().nowUs() - startUs) / 1000.0;
}

class Scope {
public:
    explicit Scope(const char* name, double* cumulativeMs = nullptr, Profiler& profiler = global(),
                   double minimumTraceUs = 0)
        : profiler_(profiler), name_(name), cumulativeMs_(cumulativeMs), minimumTraceUs_(minimumTraceUs) {
        if (profiler_.mode() != Mode::Off) startUs_ = profiler_.now();
    }
    Scope(const char* name, double& cumulativeMs, Profiler& profiler = global())
        : Scope(name, &cumulativeMs, profiler) {}
    ~Scope() noexcept {
        if (profiler_.mode() == Mode::Off) return;
        const double durationUs = std::max(0.0, profiler_.now() - startUs_);
        // Accumulators retain their caller's ownership discipline: use separate
        // doubles per thread. Trace recording and snapshots are synchronized.
        if (cumulativeMs_) *cumulativeMs_ += durationUs / 1000.0;
        if (profiler_.mode() == Mode::Deep && durationUs >= minimumTraceUs_)
            profiler_.record(name_, startUs_, durationUs);
    }
    Scope(const Scope&) = delete;
    Scope& operator=(const Scope&) = delete;
    Scope(Scope&&) = delete;
    Scope& operator=(Scope&&) = delete;
private:
    Profiler& profiler_;
    const char* name_;
    double* cumulativeMs_;
    double startUs_ = 0;
    // Hot per-entity scopes can retain only outliers without flooding the ring.
    // Accumulation is unaffected; this is not a sampling CPU profiler.
    double minimumTraceUs_ = 0;
};
} // namespace df3d::profiling
