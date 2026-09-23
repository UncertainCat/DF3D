#include "wm/buffered_world_client.h"

#include <atomic>
#include <deque>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <exception>
#include <mutex>
#include <thread>
#include "buffered_frame_queue.h"

namespace wm {
struct BufferedWorldClient::Impl {
  BufferedWorldConfig config;
  std::unique_ptr<MirrorClient> collector, reader, sender;
  mutable std::mutex mutex, commandMutex;
  std::condition_variable wake;
  std::atomic<bool> stopping{false};
  std::atomic<uint64_t> capturedEpoch{0};
  std::thread worker, captureWorker, retirementWorker;
  std::condition_variable retireWake;
  bool workerFinished = false;
  // Capture never takes the presentation lock. That lock transfers ownership;
  // model/event processing runs only on privately owned queues outside it.
  std::mutex inboxMutex;
  std::condition_variable inboxWake;
  std::deque<MirrorClient::CapturedSnapshot> inbox;
  size_t inboxBytes = 0, peakInboxBytes = 0, peakInboxCount = 0;
  uint64_t queueDrops = 0;
  bool recoveryNeeded = false;
  PublicationStats capturedStats;
  MirrorClient::CaptureDiagnostics captureInfo;
  double captureMs = 0, capturePollMaxMs = 0, captureMissPollMaxMs = 0;
  std::string captureError;
  BufferedWorldStats status;
  std::unique_ptr<detail::BufferedFrameQueue> frames;

  void retireLoop() {
    for (;;) {
      std::vector<std::unique_ptr<WorldModel>> garbage;
      {
        std::unique_lock lock(mutex);
        retireWake.wait(lock, [this] { return workerFinished || frames->retiredCount() != 0; });
        garbage = frames->takeRetired();
        if (workerFinished && garbage.empty()) break;
      }
      const auto start = config.collectTimings ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
      garbage.clear();
      if (config.collectTimings) {
        const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now()-start).count();
        std::lock_guard lock(mutex); status.retirementMilliseconds += ms;
      }
    }
  }

  void captureLoop() {
    bool epochObserved = false, havePreviousPoll = false;
    double previousPoll = 0;
    unsigned contentionRetries = 0;
    try {
      while (!stopping) {
        MirrorClient::CapturedSnapshot captured;
        const auto start = config.collectTimings ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        const double pollTime = config.clock();
        const double intervalMs = havePreviousPoll ? std::max(0.0, (pollTime - previousPoll) * 1000) : 0;
        previousPoll = pollTime; havePreviousPoll = true;
        const bool fresh = collector->capture(captured, pollTime);
        const auto end = config.collectTimings ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        {
          std::lock_guard lock(inboxMutex);
          const auto receipts = collector->captureStats();
          capturePollMaxMs = std::max(capturePollMaxMs, intervalMs);
          if (receipts.missed > capturedStats.missed) captureMissPollMaxMs = std::max(captureMissPollMaxMs, intervalMs);
          capturedStats = receipts;
          captureInfo = collector->captureDiagnostics();
          captureError = collector->lastError();
          if (config.collectTimings) captureMs += std::chrono::duration<double, std::milli>(end-start).count();
          if (fresh) {
            if (!epochObserved || captured.epoch != capturedEpoch.load()) {
              epochObserved = true;
              capturedEpoch = captured.epoch;
              // Old-session envelopes are obsolete, not queue-overload losses.
              inbox.clear(); inboxBytes = 0; recoveryNeeded = false;
            }
            const auto bytes = captured.bytes.size();
            if (bytes > config.maxPendingBytes) {
              // Retrying an older Full cannot recover a publication that cannot fit.
              // Default budget exceeds the transport slot capacity; custom budgets
              // that cannot hold one publication fail explicitly rather than loop.
              ++queueDrops;
              captureError = "snapshot exceeds maxPendingBytes; increase the input queue byte budget";
              stopping = true;
            } else {
              while (!inbox.empty() && (inbox.size() >= config.maxPendingSnapshots ||
                     inboxBytes + bytes > config.maxPendingBytes)) {
                if (!inbox.front().bytes.empty()) ++queueDrops;
                inboxBytes -= inbox.front().bytes.size();
                inbox.pop_front(); recoveryNeeded = true;
              }
              inboxBytes += bytes;
              inbox.push_back(std::move(captured));
              peakInboxCount = std::max(peakInboxCount, inbox.size());
              peakInboxBytes = std::max(peakInboxBytes, inboxBytes);
            }
          }
        }
        if (fresh) {
          contentionRetries = 0;
          inboxWake.notify_one();
          // Drain retained publications at memory speed; polling delay only
          // applies when caught up. Never impose one sleep per publication.
          continue;
        }
        if (collector->captureDiagnostics().pendingPublications && contentionRetries++ < 8) {
          std::this_thread::yield();
          continue;
        }
        contentionRetries = 0;
        std::unique_lock lock(inboxMutex);
        wake.wait_for(lock, std::chrono::duration<double>(config.pollIntervalSeconds), [this] { return stopping.load(); });
      }
    } catch (const std::exception& ex) {
      std::lock_guard lock(inboxMutex); captureError = std::string("snapshot collector: ") + ex.what(); stopping = true;
    } catch (...) {
      std::lock_guard lock(inboxMutex); captureError = "snapshot collector: unknown exception"; stopping = true;
    }
    inboxWake.notify_all();
  }

  void run() {
    try {
      WorldModel model(config.model, config.initialGeneration);
      uint64_t sequence = 0;
      double lastPublishedAt = -1e30;
      bool pending = false, pendingReset = false;
      double modelCapturedAt = 0, modelSourceAt = 0;
      uint64_t modelEpoch = 0;
      MirrorClient::CapturedSnapshot latest;
      while (true) {
        { std::lock_guard lock(mutex); if (stopping) break; }
        bool recover = false;
        {
          std::unique_lock lock(inboxMutex);
          inboxWake.wait_for(lock, std::chrono::duration<double>(config.pollIntervalSeconds),
              [this] { return stopping.load() || !inbox.empty(); });
          if (stopping) break;
          if (!inbox.empty()) {
            inboxBytes -= inbox.front().bytes.size();
            latest = std::move(inbox.front()); inbox.pop_front();
          }
          recover = recoveryNeeded; recoveryNeeded = false;
        }
        if (recover) reader->requestRecovery();
        const auto started = config.collectTimings ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        const auto previousGeneration = model.sessionGeneration();
        const bool changed = reader->ingestCaptured(model, latest);
        const auto ingested = config.collectTimings ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        const bool reset = previousGeneration != model.sessionGeneration();
        if (reset) {
          std::lock_guard lock(mutex);
          frames->clear();
          status.generation = model.sessionGeneration();
          status.terrainEpoch = reader->terrainEpoch();
          status.queuedFrames = 0;
        }
        if (changed) {
          modelCapturedAt = latest.wallSeconds;
          modelSourceAt = latest.timestamped ? latest.sourceWallSeconds : latest.wallSeconds;
          modelEpoch = latest.epoch;
        }
        pending = pending || changed;
        pendingReset = pendingReset || reset;
        std::unique_ptr<BufferedWorldFrame> frame;
        bool canPublish = true;
        {
          std::lock_guard lock(mutex);
          canPublish = frames->retiredCount() < std::max(size_t(2), config.maxFrames);
          if (pending && !canPublish) ++status.publicationBackpressure;
        }
        if (pending && canPublish && (pendingReset || config.clock() - lastPublishedAt >= config.publishIntervalSeconds)) {
          frame = std::make_unique<BufferedWorldFrame>();
          frame->sequence = ++sequence;
          frame->sourceEpoch = modelEpoch;
          frame->generation = model.sessionGeneration();
          frame->capturedAt = modelCapturedAt;
          frame->sourceAt = modelSourceAt;
          frame->releaseAt = pendingReset
              ? modelCapturedAt : modelSourceAt + config.delaySeconds;
          frame->model = std::make_unique<WorldModel>(model);
          model.drainAllEvents();
          lastPublishedAt = config.clock();
          pending = false;
          pendingReset = false;
        }
        const auto copied = config.collectTimings ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        if (config.collectTimings && config.timingObserver) {
          const auto emit = [&](const char* name, auto begin, auto end) {
            try {
              config.timingObserver(name,
                  std::chrono::duration<double, std::micro>(begin.time_since_epoch()).count(),
                  std::chrono::duration<double, std::micro>(end - begin).count());
            } catch (...) { /* Optional diagnostics must not stop ingestion. */ }
          };
          emit("worker.ingest", started, ingested);
          emit("worker.snapshot_copy", ingested, copied);
        }
        uint64_t coalesced = 0;
        if (frame) {
          auto prepared = [&] {
            std::lock_guard lock(mutex);
            status.queuedFrames = 0;
            return frames->detachFrames();
          }();
          // append() can be substantial or reject its explicit retention budget.
          // The worker owns all detached state until publication succeeds.
          coalesced = prepared.push(std::move(frame));
          std::lock_guard lock(mutex);
          if (stopping) prepared.clear();
          else ++status.published;
          frames->restoreFrames(std::move(prepared));
          // Publication identity must become visible atomically with its frames.
          // Otherwise a fast consumer can discard a new worker's first frame.
          status.generation = model.sessionGeneration();
          status.queuedFrames = frames->size();
        }
        std::unique_lock lock(mutex);
        status.generation = model.sessionGeneration();
        status.sourcePublications = reader->publicationStats();
        status.bridgeTick = reader->bridgeTick();
        status.terrainEpoch = reader->terrainEpoch();
        status.terrainSynced = reader->terrainSynced();
        status.terrainGridTick = reader->terrainGridTick();
        status.buildingsSynced = reader->buildingsSynced();
        status.itemsSynced = reader->itemsSynced();
        status.entityFullRequests = reader->entityFullRequests();
        // A consumer-side fold failure may have stopped us during publication.
        // Keep that actionable error instead of replacing it with an empty read.
        if (!stopping) status.error = reader->lastError();
        if (config.collectTimings) {
          status.pollMilliseconds += std::chrono::duration<double, std::milli>(ingested-started).count();
          status.publicationMilliseconds += std::chrono::duration<double, std::milli>(copied-ingested).count();
        }
        status.coalesced += coalesced;
        status.queuedFrames = frames->size();
        retireWake.notify_one();
        if (stopping) break;
      }
    } catch (const std::exception& ex) {
      std::lock_guard lock(mutex); status.error = std::string("buffered worker: ") + ex.what(); stopping = true;
    } catch (...) {
      std::lock_guard lock(mutex); status.error = "buffered worker: unknown exception"; stopping = true;
    }
    wake.notify_all();
    {
      std::lock_guard lock(mutex);
      frames->clear(); workerFinished = true;
    }
    retireWake.notify_all();
  }
};
BufferedWorldClient::BufferedWorldClient() : impl_(std::make_unique<Impl>()) {}
std::unique_ptr<BufferedWorldClient> BufferedWorldClient::open(BufferedWorldConfig config,
    std::string& error, const std::string& regionName) {
  if (!config.clock || !std::isfinite(config.delaySeconds) || config.delaySeconds < 0 ||
      !std::isfinite(config.pollIntervalSeconds) || config.pollIntervalSeconds <= 0 ||
      !std::isfinite(config.publishIntervalSeconds) || config.publishIntervalSeconds <= 0 ||
      !config.maxPendingSnapshots || !config.maxPendingBytes) {
    error = "buffered client requires a clock, nonnegative delay, positive intervals and nonzero input queue budgets"; return {};
  }
  auto result = std::unique_ptr<BufferedWorldClient>(new BufferedWorldClient);
  auto& im = *result->impl_;
  im.config = std::move(config);
  im.collector = MirrorClient::open(error, regionName, MirrorClient::OpenMode::Capture);
  if (!im.collector) return {};
  im.reader = MirrorClient::open(error, regionName);
  if (!im.reader) return {};
  im.sender = MirrorClient::open(error, regionName, MirrorClient::OpenMode::Commands);
  if (!im.sender) return {};
  im.frames = std::make_unique<detail::BufferedFrameQueue>(im.config.maxFrames);
  im.worker = std::thread([ptr = &im] { ptr->run(); });
  im.captureWorker = std::thread([ptr = &im] { ptr->captureLoop(); });
  im.retirementWorker = std::thread([ptr = &im] { ptr->retireLoop(); });
  error.clear();
  return result;
}
BufferedWorldClient::~BufferedWorldClient() { stop(); }
void BufferedWorldClient::stop() {
  { std::lock_guard lock(impl_->mutex); impl_->stopping = true; }
  impl_->wake.notify_all();
  impl_->inboxWake.notify_all();
  if (impl_->captureWorker.joinable()) impl_->captureWorker.join();
  if (impl_->worker.joinable()) impl_->worker.join();
  if (impl_->retirementWorker.joinable()) impl_->retirementWorker.join();
}
std::unique_ptr<BufferedWorldFrame> BufferedWorldClient::takeReady(double wallSeconds) {
  auto ready = [&] {
    std::lock_guard lock(impl_->mutex);
    auto result = impl_->frames->extractReady(wallSeconds);
    impl_->status.queuedFrames = impl_->frames->size();
    return result;
  }();
  uint64_t coalesced = 0;
  std::unique_ptr<BufferedWorldFrame> result;
  std::string failure;
  try {
    result = ready.take(wallSeconds, &coalesced);
  } catch (const std::exception& ex) {
    failure = std::string("buffered presentation: ") + ex.what();
  } catch (...) {
    failure = "buffered presentation: unknown exception";
  }
  {
    std::lock_guard lock(impl_->mutex);
    if (!failure.empty()) {
      impl_->status.error = std::move(failure);
      impl_->stopping = true;
      ready.clear();
    }
    // A reset or failure can happen while folding. Never adopt that old state
    // or arm its command epoch after the worker has invalidated it.
    if (result && (impl_->stopping ||
        result->generation != impl_->status.generation ||
        result->sourceEpoch != impl_->capturedEpoch.load())) {
      ready.retire(std::move(result->model));
      result.reset();
    }
    impl_->frames->collectRetired(ready);
    impl_->status.coalesced += coalesced;
    if (result) {
      std::lock_guard commandLock(impl_->commandMutex);
      impl_->sender->setCommandEpoch(result->sourceEpoch);
    }
  }
  impl_->retireWake.notify_one();
  if (impl_->stopping) {
    impl_->wake.notify_all();
    impl_->inboxWake.notify_all();
  }
  return result;
}
void BufferedWorldClient::retire(std::unique_ptr<WorldModel> model) {
  std::lock_guard lock(impl_->mutex);
  impl_->frames->retire(std::move(model));
  impl_->retireWake.notify_one();
}
BufferedWorldStats BufferedWorldClient::stats() const {
  BufferedWorldStats result;
  { std::lock_guard lock(impl_->mutex); result = impl_->status; }
  {
    std::lock_guard lock(impl_->inboxMutex);
    result.capturedPublications = impl_->capturedStats;
    result.captureDiagnostics = impl_->captureInfo;
    result.pendingSnapshots = impl_->inbox.size(); result.pendingBytes = impl_->inboxBytes;
    result.peakPendingSnapshots = impl_->peakInboxCount; result.peakPendingBytes = impl_->peakInboxBytes;
    result.captureQueueDrops = impl_->queueDrops; result.captureMilliseconds = impl_->captureMs;
    result.capturePollIntervalMaxMs = impl_->capturePollMaxMs;
    result.captureMissPollIntervalMaxMs = impl_->captureMissPollMaxMs;
    if (!impl_->captureError.empty() && (!impl_->stopping || result.error.empty()))
      result.error = impl_->captureError;
  }
  return result;
}
uint64_t BufferedWorldClient::lastCommandSeq() const {
  std::lock_guard lock(impl_->commandMutex); return impl_->sender->lastCommandSeq();
}
std::string BufferedWorldClient::commandError() const {
  if (impl_->stopping) {
    const auto state = stats();
    return state.error.empty() ? "buffered client stopped; command was not sent" : state.error;
  }
  std::lock_guard lock(impl_->commandMutex); return impl_->sender->lastError();
}
uint64_t BufferedWorldClient::sendSetPause(bool paused) {
  std::lock_guard lock(impl_->commandMutex);
  if (impl_->stopping) return 0;
  return impl_->sender->sendSetPause(paused);
}
uint64_t BufferedWorldClient::sendDesignateDig(const TileRect& r, DigKind k, uint8_t p, bool marker, uint8_t mining_mode, int32_t max_z) {
  std::lock_guard lock(impl_->commandMutex);
  if (impl_->stopping) return 0;
  return impl_->sender->sendDesignateDig(r,k,p,marker,mining_mode,max_z);
}
uint64_t BufferedWorldClient::sendDesignateSmooth(const TileRect& r, SmoothKind k, uint8_t p, bool marker, bool from_east, bool from_south, int32_t max_z, int32_t track_end_z) {
  std::lock_guard lock(impl_->commandMutex);
  if (impl_->stopping) return 0;
  return impl_->sender->sendDesignateSmooth(r,k,p,marker,from_east,from_south,max_z,track_end_z);
}
uint64_t BufferedWorldClient::sendDesignateChop(const TileRect& r, bool e, uint8_t p, bool marker, int32_t max_z) {
  std::lock_guard lock(impl_->commandMutex);
  if (impl_->stopping) return 0;
  return impl_->sender->sendDesignateChop(r,e,p,marker,max_z);
}
uint64_t BufferedWorldClient::sendDesignateGather(const TileRect& r, bool e, uint8_t p, bool marker, int32_t max_z) {
  std::lock_guard lock(impl_->commandMutex);
  if (impl_->stopping) return 0;
  return impl_->sender->sendDesignateGather(r,e,p,marker,max_z);
}
uint64_t BufferedWorldClient::sendSetItemFlags(ItemId id, OptionalBool f, OptionalBool d, OptionalBool m) {
  std::lock_guard lock(impl_->commandMutex);
  if (impl_->stopping) return 0;
  return impl_->sender->sendSetItemFlags(id,f,d,m);
}
uint64_t BufferedWorldClient::sendSetBuildingFlags(BuildingId id, OptionalBool f) {
  std::lock_guard lock(impl_->commandMutex);
  if (impl_->stopping) return 0;
  return impl_->sender->sendSetBuildingFlags(id,f);
}
} // namespace wm
