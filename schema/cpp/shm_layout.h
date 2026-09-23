// Shared-memory mirror transport (mirror layer).
//
// One named mapping carries: a fixed header, two snapshot slots (double
// buffer with seqlocks; bridge writes, clients read), and a command ring
// (serialized client producers, bridge consumer) of size-prefixed FlatBuffers
// Command messages. A second named mapping (the terrain grid)
// carries the terrain base state as a POD block grid the bridge updates in
// place; clients synthesize a Full terrain snapshot from it at attach and
// then follow ring Deltas. Everything is index/offset-based and
// relocatable — no pointers cross the process boundary.
//
// Compiled by BOTH the MSVC-built DFHack plugin and GCC-built clients:
// keep this header C++17-compatible, POD layout only, no std::atomic
// members (ABI paranoia) — cross-process atomicity goes through the
// explicit shims below, with layout pinned by static_asserts.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

#if defined(_MSC_VER)
#include <intrin.h>
#if !defined(_M_X64)
#error "shm atomic shims assume x86-64 (plain aligned loads/stores + compiler fences); port before targeting other architectures"
#endif
#endif

namespace df3d::shm {

// ---- atomic shims (64-bit aligned fields only) ----

inline uint64_t atomicLoadAcquire(const volatile uint64_t* p) {
#if defined(_MSC_VER)
  uint64_t v = *p;
  _ReadWriteBarrier();
  return v;  // aligned 64-bit loads are atomic on x86-64; barrier orders the compiler
#else
  return __atomic_load_n(p, __ATOMIC_ACQUIRE);
#endif
}

inline void atomicStoreRelease(volatile uint64_t* p, uint64_t v) {
#if defined(_MSC_VER)
  _ReadWriteBarrier();
  *p = v;
#else
  __atomic_store_n(p, v, __ATOMIC_RELEASE);
#endif
}

// Seqlock protocol (every seqlock in this file follows it):
//   writer: store seq odd; seqlockFence(); write payload; store seq even (release).
//   reader: load seq (acquire); copy payload; seqlockFence(); reload seq; equal and even => valid.
// The fence keeps the payload accesses between the two sequence accesses. A release
// store alone does not stop the compiler hoisting the payload writes above the odd
// store, and an acquire load alone does not stop it sinking the payload reads below
// the validating reload. x86-64 hardware never reorders store/store or load/load, so
// a compiler barrier is enough there; the GCC form spells the intent portably.
inline void seqlockFence() {
#if defined(_MSC_VER)
  _ReadWriteBarrier();
#else
  __atomic_thread_fence(__ATOMIC_ACQ_REL);
#endif
}

// ---- region layout ----

inline constexpr char kShmMagic[8] = {'D', 'F', '3', 'D', 'S', 'H', 'M', '1'};
// v2: RegionHeader::terrainEpoch carved from the reserved pad.
// v3: RegionHeader::entityFullRequest carved from the pad.
// v4: external producer mutex and client-owned reply mailboxes.
// v5: explicit publication indices, protected by each snapshot seqlock.
// v6: bounded optional publication journal and per-publication timestamps.
inline constexpr uint32_t kLayoutVersion = 6;
// Windows kernel object name (Local\ = current session namespace).
inline constexpr const char* kDefaultRegionName = "Local\\df3d_mirror_v1";

inline constexpr uint32_t kDefaultSnapshotCapacity = 16u * 1024 * 1024;  // per slot
inline constexpr uint32_t kDefaultCommandCapacity = 1u * 1024 * 1024;
// Sanity ceilings for header-declared capacities. A client trusts the header
// only after checkRegionSize() proves the declared layout fits the mapping.
inline constexpr uint32_t kMaxSnapshotCapacity = 512u * 1024 * 1024;
inline constexpr uint32_t kMaxCommandCapacity = 64u * 1024 * 1024;
inline constexpr uint64_t kMaxJournalCapacity = 1024ull * 1024 * 1024;
// Largest single command a client may push (commands are small FlatBuffers;
// the default ring holds 1 MiB). Callers reject larger payloads before pushCommand.
inline constexpr size_t kMaxCommandBytes = 64u * 1024;

// Fixed-size header at offset 0. 64-bit fields are 8-aligned for the shims.
struct RegionHeader {
  char magic[8];             // kShmMagic
  uint32_t layoutVersion;    // kLayoutVersion
  uint32_t schemaVersion;    // df3d.mirror SchemaVersion.Current of the writer
  uint32_t snapshotCapacity; // bytes per snapshot slot
  uint32_t commandCapacity;  // bytes in the command ring
  volatile uint64_t activeSlot;     // 0 or 1: last fully-published slot
  volatile uint64_t slotSeq[2];     // seqlock per slot: odd while writing
  volatile uint64_t slotBytes[2];   // valid FlatBuffers bytes in each slot
  volatile uint64_t cmdHead;        // producer position (monotonic byte count)
  volatile uint64_t cmdTail;        // consumer position (monotonic byte count)
  volatile uint64_t bridgeTick;     // last sim tick published (heartbeat)
  // Identifies the terrain grid mapping that belongs to this session:
  // its name is terrainRegionName(epoch). 0 = no grid published (yet).
  // A new value means the bridge created a new grid (map load); clients
  // re-attach and re-synthesize their Full.
  volatile uint64_t terrainEpoch;
  // Client -> bridge: a client that needs the buildings / items
  // base state (attach, map reload, a tick gap it cannot bridge) bumps
  // this counter; the bridge answers every new value with a snapshot whose
  // building_scope and item_scope are Full. Increment atomically with
  // requestEntityFull(), never write it directly.
  volatile uint64_t entityFullRequest;
  volatile uint64_t commandSequence; // unique IDs across basic-command clients
  volatile uint64_t publicationIndex; // successful publications, independent of DF tick
  volatile uint64_t slotPublicationIndex[2]; // belongs to the bytes in this slot
  volatile uint64_t slotTimestampMicros[2];
  volatile uint64_t slotTick[2];
  uint64_t journalCapacity;         // byte arena size; zero disables journal
  volatile uint64_t journalOldestIndex;
  volatile uint64_t journalNewestIndex;
  volatile uint64_t journalByteHead; // monotonically increasing byte position
  uint8_t reserved[56];             // pad header to 256 bytes for layout stability
};

static_assert(sizeof(RegionHeader) == 256, "header layout is part of the ABI");
static_assert(offsetof(RegionHeader, activeSlot) % 8 == 0);
static_assert(offsetof(RegionHeader, slotSeq) % 8 == 0);
static_assert(offsetof(RegionHeader, cmdHead) % 8 == 0);
static_assert(offsetof(RegionHeader, terrainEpoch) % 8 == 0);
static_assert(offsetof(RegionHeader, entityFullRequest) % 8 == 0);

inline uint64_t nextCommandSequence(RegionHeader* h) {
#if defined(_MSC_VER)
  return uint64_t(_InterlockedIncrement64(reinterpret_cast<volatile long long*>(&h->commandSequence)));
#else
  return __atomic_add_fetch(&h->commandSequence,uint64_t(1),__ATOMIC_RELAXED);
#endif
}

// Client: asks the bridge for a Full of both entity tables (see the field).
inline void requestEntityFull(RegionHeader* h) {
  #if defined(_MSC_VER)
  _InterlockedIncrement64(reinterpret_cast<volatile long long*>(&h->entityFullRequest));
#else
  __atomic_add_fetch(&h->entityFullRequest, uint64_t(1), __ATOMIC_RELEASE);
#endif
}

inline constexpr uint32_t kJournalEntries = 128;
struct JournalDescriptor {
  volatile uint64_t sequence; // guards this entry and every arena byte it owns
  volatile uint64_t index, byteBegin, bytes, tick, timestampMicros;
};
static_assert(sizeof(JournalDescriptor) == 48, "journal descriptor ABI");
inline constexpr size_t journalOffset(uint32_t snapCap, uint32_t cmdCap) {
  return (sizeof(RegionHeader) + 2 * static_cast<size_t>(snapCap) + cmdCap + 7u) & ~size_t(7u);
}
inline constexpr size_t regionSize(uint32_t snapCap, uint32_t cmdCap, uint32_t journalBytes = 0) {
  return journalBytes ? journalOffset(snapCap,cmdCap) + sizeof(JournalDescriptor)*kJournalEntries + journalBytes
      : sizeof(RegionHeader) + 2 * static_cast<size_t>(snapCap) + cmdCap;
}
inline JournalDescriptor* journalDescriptors(RegionHeader* h) {
  return reinterpret_cast<JournalDescriptor*>(reinterpret_cast<uint8_t*>(h) + journalOffset(h->snapshotCapacity,h->commandCapacity));
}
inline const JournalDescriptor* journalDescriptors(const RegionHeader* h) {
  return journalDescriptors(const_cast<RegionHeader*>(h));
}
inline uint8_t* journalData(RegionHeader* h) {
  return reinterpret_cast<uint8_t*>(journalDescriptors(h) + kJournalEntries);
}
inline const uint8_t* journalData(const RegionHeader* h) {
  return journalData(const_cast<RegionHeader*>(h));
}

inline uint8_t* slotData(RegionHeader* h, unsigned slot) {
  return reinterpret_cast<uint8_t*>(h) + sizeof(RegionHeader) +
         static_cast<size_t>(slot) * h->snapshotCapacity;
}
inline const uint8_t* slotData(const RegionHeader* h, unsigned slot) {
  return slotData(const_cast<RegionHeader*>(h), slot);
}
inline uint8_t* ringData(RegionHeader* h) {
  return reinterpret_cast<uint8_t*>(h) + sizeof(RegionHeader) +
         2 * static_cast<size_t>(h->snapshotCapacity);
}
inline const uint8_t* ringData(const RegionHeader* h) {
  return ringData(const_cast<RegionHeader*>(h));
}

// Initializes a freshly-created region (bridge side).
inline void initRegion(RegionHeader* h, uint32_t schemaVersion,
                       uint32_t snapCap = kDefaultSnapshotCapacity,
                       uint32_t cmdCap = kDefaultCommandCapacity,
                       uint32_t journalBytes = 0) {
  std::memset(h, 0, sizeof(RegionHeader));
  std::memcpy(h->magic, kShmMagic, sizeof(kShmMagic));
  h->layoutVersion = kLayoutVersion;
  h->schemaVersion = schemaVersion;
  h->snapshotCapacity = snapCap;
  h->commandCapacity = cmdCap;
  h->journalCapacity = journalBytes;
  if (journalBytes) {
    h->journalOldestIndex = 1;
    std::memset(journalDescriptors(h),0,sizeof(JournalDescriptor)*kJournalEntries);
  }
}

// Validates magic/version/capacities of a mapped region (client side).
// Returns nullptr on success or a static error string.
inline const char* checkRegion(const RegionHeader* h, uint32_t expectSchemaVersion) {
  if (std::memcmp(h->magic, kShmMagic, sizeof(kShmMagic)) != 0) return "bad shm magic";
  if (h->layoutVersion != kLayoutVersion) return "shm layout version mismatch";
  if (h->schemaVersion != expectSchemaVersion) return "shm schema version mismatch";
  if (h->snapshotCapacity == 0 || h->commandCapacity == 0) return "zero shm capacity";
  return nullptr;
}

// Validates that the layout the header declares fits inside `mappedBytes`
// (the mapped view's actual size) and that the capacities are sane. Pure over
// the header so it is unit-testable; run it after checkRegion and before
// trusting any slot / ring / journal offset. nullptr on success.
inline const char* checkRegionSize(const RegionHeader* h, size_t mappedBytes) {
  if (mappedBytes < sizeof(RegionHeader)) return "shm mapping smaller than the header";
  if (h->snapshotCapacity > kMaxSnapshotCapacity) return "shm snapshot capacity exceeds the sane maximum";
  if (h->commandCapacity > kMaxCommandCapacity) return "shm command capacity exceeds the sane maximum";
  if (h->journalCapacity > kMaxJournalCapacity) return "shm journal capacity exceeds the sane maximum";
  const size_t need = regionSize(h->snapshotCapacity, h->commandCapacity,
                                 static_cast<uint32_t>(h->journalCapacity));
  if (need > mappedBytes) return "shm header declares a layout larger than the mapping";
  return nullptr;
}

// ---- snapshot double buffer ----

// Single producer, no acknowledgments: overwrite old publications when either
// the descriptor count or byte arena fills. Eviction invalidates every affected
// descriptor BEFORE overwriting any arena bytes. Unrelated appends therefore
// never interrupt a reader copying a retained publication.
inline void invalidateJournalEntry(JournalDescriptor& entry) {
  const uint64_t seq=atomicLoadAcquire(&entry.sequence);
  atomicStoreRelease(&entry.sequence,seq+1);
  seqlockFence();
  atomicStoreRelease(&entry.index,0);
  atomicStoreRelease(&entry.sequence,seq+2);
}
inline void appendJournal(RegionHeader* h, const uint8_t* bytes, size_t len,
                          uint64_t index, uint64_t tick, uint64_t timestampMicros) {
  if (!h->journalCapacity) return;
  uint64_t oldest = atomicLoadAcquire(&h->journalOldestIndex);
  const uint64_t newest = atomicLoadAcquire(&h->journalNewestIndex);
  const uint64_t head = atomicLoadAcquire(&h->journalByteHead);
  auto* entries = journalDescriptors(h);
  while (oldest <= newest && (index-oldest >= kJournalEntries ||
      head+len-atomicLoadAcquire(&entries[oldest%kJournalEntries].byteBegin) > h->journalCapacity)) {
    invalidateJournalEntry(entries[oldest%kJournalEntries]);
    ++oldest;
  }
  atomicStoreRelease(&h->journalOldestIndex,oldest);
  auto& entry = entries[index%kJournalEntries];
  const uint64_t seq=atomicLoadAcquire(&entry.sequence);
  atomicStoreRelease(&entry.sequence,seq+1);
  seqlockFence();
  const size_t offset = size_t(head%h->journalCapacity);
  const size_t first = len < h->journalCapacity-offset ? len : size_t(h->journalCapacity-offset);
  std::memcpy(journalData(h)+offset,bytes,first);
  if (len>first) std::memcpy(journalData(h),bytes+first,len-first);
  atomicStoreRelease(&entry.index,index);
  atomicStoreRelease(&entry.byteBegin,head);
  atomicStoreRelease(&entry.bytes,len);
  atomicStoreRelease(&entry.tick,tick);
  atomicStoreRelease(&entry.timestampMicros,timestampMicros);
  atomicStoreRelease(&entry.sequence,seq+2);
  atomicStoreRelease(&h->journalNewestIndex,index);
  atomicStoreRelease(&h->journalByteHead,head+len);
}

// Bridge: publish a serialized snapshot. Returns false if it exceeds the
// slot/journal capacity or is empty (caller should treat as a hard bug,
// not truncate). Failure leaves both transports and the publication index intact.
inline bool publishSnapshot(RegionHeader* h, const uint8_t* bytes, size_t len,
                            uint64_t simTick, uint64_t timestampMicros = 0) {
  if (!len || len > h->snapshotCapacity || (h->journalCapacity && len > h->journalCapacity)) return false;
  const unsigned slot = 1u - static_cast<unsigned>(atomicLoadAcquire(&h->activeSlot) & 1u);
  atomicStoreRelease(&h->slotSeq[slot], atomicLoadAcquire(&h->slotSeq[slot]) + 1);  // odd
  seqlockFence();
  const uint64_t index = atomicLoadAcquire(&h->publicationIndex) + 1;
  std::memcpy(slotData(h, slot), bytes, len);
  atomicStoreRelease(&h->slotPublicationIndex[slot], index);
  atomicStoreRelease(&h->slotTimestampMicros[slot], timestampMicros);
  atomicStoreRelease(&h->slotTick[slot], simTick);
  atomicStoreRelease(&h->slotBytes[slot], len);
  atomicStoreRelease(&h->slotSeq[slot], atomicLoadAcquire(&h->slotSeq[slot]) + 1);  // even
  appendJournal(h,bytes,len,index,simTick,timestampMicros);
  atomicStoreRelease(&h->publicationIndex, index);
  atomicStoreRelease(&h->activeSlot, slot);
  atomicStoreRelease(&h->bridgeTick, simTick);
  return true;
}

// Bridge: discard a prior map's snapshots before publishing a new map epoch.
// Tick zero is a valid paused frame, so absence is represented by empty slots.
inline void invalidateSnapshots(RegionHeader* h) {
  if (h->journalCapacity) {
    const uint64_t oldest=atomicLoadAcquire(&h->journalOldestIndex);
    const uint64_t newest=atomicLoadAcquire(&h->journalNewestIndex);
    const uint64_t index = atomicLoadAcquire(&h->publicationIndex);
    atomicStoreRelease(&h->journalOldestIndex,index+1);
    for (uint64_t retained=oldest;retained<=newest;++retained)
      invalidateJournalEntry(journalDescriptors(h)[retained%kJournalEntries]);
    atomicStoreRelease(&h->journalNewestIndex,index);
  }
  for (unsigned slot = 0; slot < 2; ++slot) {
    atomicStoreRelease(&h->slotSeq[slot], atomicLoadAcquire(&h->slotSeq[slot]) + 1);
    seqlockFence();
    atomicStoreRelease(&h->slotBytes[slot], 0);
    atomicStoreRelease(&h->slotSeq[slot], atomicLoadAcquire(&h->slotSeq[slot]) + 1);
  }
  atomicStoreRelease(&h->bridgeTick, 0);
}

// Client: copy out the latest stable snapshot. Returns bytes copied, or 0
// if nothing published yet / torn read persisted past maxRetries.
// Identifies the exact stable publication copied, independently of sim time.
struct SnapshotPublication {
  unsigned slot = 2; // 2 identifies journal reads, which have no double slot
  uint64_t sequence = 0, index = 0;
  uint64_t timestampMicros = 0, tick = 0;
  uint64_t oldestRetainedIndex = 0, latestIndex = 0;
};
inline size_t readLatestSnapshot(const RegionHeader* h, uint8_t* out, size_t outCap,
                                 int maxRetries = 16, SnapshotPublication* publication = nullptr) {
  for (int i = 0; i < maxRetries; ++i) {
    const unsigned slot = static_cast<unsigned>(atomicLoadAcquire(&h->activeSlot) & 1u);
    const uint64_t seqBefore = atomicLoadAcquire(&h->slotSeq[slot]);
    if (seqBefore == 0 || (seqBefore & 1u)) continue;  // never written / mid-write
    const uint64_t len = atomicLoadAcquire(&h->slotBytes[slot]);
    if (len == 0 || len > outCap || len > h->snapshotCapacity) return 0;
    const uint64_t index = atomicLoadAcquire(&h->slotPublicationIndex[slot]);
    const uint64_t timestamp = atomicLoadAcquire(&h->slotTimestampMicros[slot]);
    const uint64_t tick = atomicLoadAcquire(&h->slotTick[slot]);
    std::memcpy(out, slotData(h, slot), static_cast<size_t>(len));
    seqlockFence();
    if (atomicLoadAcquire(&h->slotSeq[slot]) == seqBefore) {
      if (publication) *publication = {slot, seqBefore, index, timestamp, tick, index, index};
      return static_cast<size_t>(len);
    }
  }
  return 0;
}

// Copy the next retained publication after `afterIndex`. Zero attaches at the
// latest publication, ignoring history before attachment. A returned index
// greater than afterIndex+1 is the exact retention gap. No producer waits for
// readers. Return zero when caught up, empty, too-small output, or a persistent
// torn read. Bounds are optimistic observations; the copied publication's
// descriptor index and seqlock protect its metadata and bytes independently.
// An empty retained range has oldestRetainedIndex > latestIndex. On success
// timestampMicros/tick belong to the copied bytes, not the live header.
inline size_t readNextSnapshot(const RegionHeader* h, uint64_t afterIndex,
    uint8_t* out, size_t outCap, int maxRetries = 16, SnapshotPublication* publication = nullptr) {
  if (publication) *publication = {};
  if (!h->journalCapacity) {
    SnapshotPublication copied;
    const size_t len = readLatestSnapshot(h,out,outCap,maxRetries,&copied);
    if (publication) *publication = copied;
    return copied.index > afterIndex ? len : 0;
  }
  for (int attempt=0;attempt<maxRetries;++attempt) {
    const uint64_t oldest = atomicLoadAcquire(&h->journalOldestIndex);
    const uint64_t newest = atomicLoadAcquire(&h->journalNewestIndex);
    SnapshotPublication copied{2,0,0,0,0,oldest,newest};
    if (oldest>newest || newest==0 || afterIndex>=newest) {
      if (publication) *publication=copied;
      return 0;
    }
    const uint64_t wanted = afterIndex==0 ? newest : (afterIndex+1<oldest ? oldest : afterIndex+1);
    const auto& entry = journalDescriptors(h)[wanted%kJournalEntries];
    const uint64_t before=atomicLoadAcquire(&entry.sequence);
    if (!before || (before&1u)) continue;
    copied.sequence=before;
    const uint64_t index = atomicLoadAcquire(&entry.index);
    const uint64_t begin = atomicLoadAcquire(&entry.byteBegin);
    const uint64_t len = atomicLoadAcquire(&entry.bytes);
    copied.index=index;
    copied.timestampMicros=atomicLoadAcquire(&entry.timestampMicros);
    copied.tick=atomicLoadAcquire(&entry.tick);
    if (index!=wanted || len>h->journalCapacity || len>h->snapshotCapacity) continue;
    if (len>outCap) {
      seqlockFence();
      if (atomicLoadAcquire(&entry.sequence)!=before || atomicLoadAcquire(&entry.index)!=wanted) continue;
      if (publication) *publication=copied;
      return 0;
    }
    const size_t offset=size_t(begin%h->journalCapacity);
    const size_t first=len<h->journalCapacity-offset ? size_t(len) : size_t(h->journalCapacity-offset);
    std::memcpy(out,journalData(h)+offset,first);
    if (len>first) std::memcpy(out+first,journalData(h),size_t(len)-first);
    seqlockFence();
    if (atomicLoadAcquire(&entry.sequence)!=before || atomicLoadAcquire(&entry.index)!=wanted) continue;
    if (publication) *publication=copied;
    return size_t(len);
  }
  return 0;
}

// ---- command ring (serialized producers / single consumer) ----
//
// Entries are [uint32 len][len bytes], 4-byte aligned. A len of 0xFFFFFFFF
// is a wrap marker: skip to the next ring lap. Positions are monotonic
// byte counters; position % capacity is the ring offset.

inline constexpr uint32_t kRingWrapMarker = 0xFFFFFFFFu;

namespace detail {
// Widened so a length near UINT32_MAX cannot wrap to a small value.
inline uint64_t alignUp4(uint32_t v) { return (static_cast<uint64_t>(v) + 3u) & ~uint64_t(3u); }
}

// Client: enqueue one serialized Command. False if the ring lacks space
// (caller may retry after the bridge drains). All runtime clients must call
// CommandWriter::push to hold the cross-process producer mutex around this copy.
inline bool pushCommand(RegionHeader* h, const uint8_t* bytes, uint32_t len) {
  const uint32_t cap = h->commandCapacity;
  if (len > cap) return false;  // never fits; also keeps the arithmetic below from wrapping
  const uint64_t need64 = 4u + detail::alignUp4(len);
  if (need64 + 4u > cap) return false;  // never fits
  const uint32_t need = static_cast<uint32_t>(need64);
  uint64_t head = atomicLoadAcquire(&h->cmdHead);
  const uint64_t tail = atomicLoadAcquire(&h->cmdTail);
  uint32_t off = static_cast<uint32_t>(head % cap);
  uint32_t contiguous = cap - off;
  uint64_t advance = 0;
  if (contiguous < need + 4u) {
    // Not enough room for this entry plus a subsequent length word before
    // the end: emit a wrap marker (if the marker itself fits) and lap.
    advance = contiguous;
  }
  if ((head + advance + need) - tail > cap) return false;  // full
  uint8_t* ring = ringData(h);
  if (advance != 0) {
    if (contiguous >= 4u) std::memcpy(ring + off, &kRingWrapMarker, 4);
    head += advance;
    off = 0;
  }
  std::memcpy(ring + off, &len, 4);
  std::memcpy(ring + off + 4, bytes, len);
  atomicStoreRelease(&h->cmdHead, head + need);
  return true;
}

// Bridge: dequeue one command into `out` (capacity outCap). Returns the
// command length, 0 if the ring is empty, or SIZE_MAX if the entry is
// corrupt/oversized (consumer should log and reset tail to head).
inline size_t popCommand(RegionHeader* h, uint8_t* out, size_t outCap) {
  const uint32_t cap = h->commandCapacity;
  uint64_t tail = atomicLoadAcquire(&h->cmdTail);
  const uint64_t head = atomicLoadAcquire(&h->cmdHead);
  while (true) {
    if (tail >= head) return 0;
    uint32_t off = static_cast<uint32_t>(tail % cap);
    const uint32_t contiguous = cap - off;
    if (contiguous < 4u) {  // implicit wrap: too small even for a length word
      tail += contiguous;
      continue;
    }
    uint32_t len = 0;
    std::memcpy(&len, ringData(h) + off, 4);
    if (len == kRingWrapMarker) {
      tail += contiguous;
      continue;
    }
    if (len > cap) return SIZE_MAX;
    const uint64_t need = 4u + detail::alignUp4(len);
    if (need > contiguous || tail + need > head) return SIZE_MAX;
    if (len > outCap) return SIZE_MAX;
    std::memcpy(out, ringData(h) + off + 4, len);
    atomicStoreRelease(&h->cmdTail, tail + need);
    return len;
  }
}

// ---- terrain grid ----

inline constexpr char kTerrainMagic[8] = {'D', 'F', '3', 'D', 'T', 'E', 'R', '1'};
inline constexpr uint32_t kTerrainLayoutVersion = 3;
inline constexpr uint32_t kDefaultTerrainMaterialsCapacity = 1u * 1024 * 1024;
inline constexpr uint32_t kTerrainTilesPerBlock = 256;
inline constexpr uint16_t kTerrainNoMaterial = 0xFFFF;

struct TerrainTile {
  uint8_t shape;          // df3d.mirror.TileShape
  uint8_t material_kind;  // df3d.mirror.MaterialKind
  uint16_t material;      // index into the grid materials table; 0xFFFF = none
  uint8_t liquid_level;   // 0..7
  uint8_t liquid_kind;    // df3d.mirror.LiquidKind
  uint8_t flags;          // df3d.mirror.TileFlags bits
  uint8_t designation;    // terrain v2: packed operation[0:3], priority[4:6], marker[7]
  uint8_t track;
  uint8_t traffic;
  uint8_t warnings;
  uint8_t track_blockers; // bits0/1 blocked clearance/horizontal; bit2 ramp support; bit3 open ramp clearance
};
static_assert(sizeof(TerrainTile) == 12, "Terrain v3 indicators");

// Packing is private to the resident grid. FlatBuffers and world-model fields
// remain explicit semantics, and terrain layout v3 rejects older readers.
inline uint8_t terrainOperation(uint8_t value) { return value & 15; }
inline uint8_t terrainPriority(uint8_t value) { return (value >> 4) & 7; }
inline bool terrainMarker(uint8_t value) { return (value & 128) != 0; }
inline uint8_t terrainDesignation(uint8_t operation, uint8_t priority, bool marker) {
  return (operation & 15) | ((priority & 7) << 4) | (marker ? 128 : 0);
}

struct TerrainHeader {
  char magic[8];              // kTerrainMagic
  uint32_t layoutVersion;     // kTerrainLayoutVersion
  uint32_t schemaVersion;     // df3d.mirror SchemaVersion.Current of the writer
  int32_t sizeX, sizeY, sizeZ;  // map size in tiles
  int32_t blocksX, blocksY;     // ceil(size / 16); z is per level
  uint32_t blockCount;          // blocksX * blocksY * sizeZ
  uint32_t materialsCapacity;   // bytes reserved for the materials table
  volatile uint64_t epoch;          // == RegionHeader::terrainEpoch of the owner
  volatile uint64_t seq;            // grid seqlock: odd while writing
  volatile uint64_t gridTick;       // sim tick the grid state is current to
  volatile uint64_t terrainVersion; // number of grid write batches so far
  volatile uint64_t materialCount;  // published entries in the table
  volatile uint64_t materialBytes;  // bytes used by those entries
  uint8_t reserved[160];
};
static_assert(sizeof(TerrainHeader) == 256, "terrain header layout is part of the ABI");
static_assert(offsetof(TerrainHeader, epoch) % 8 == 0);
static_assert(offsetof(TerrainHeader, seq) % 8 == 0);
static_assert(offsetof(TerrainHeader, materialBytes) % 8 == 0);

// Formats the kernel object name for a grid epoch into `out` (>= 48 chars).
inline void terrainRegionName(uint64_t epoch, char* out, size_t outCap) {
  static const char prefix[] = "Local\\df3d_terrain_v1_";
  static const char hex[] = "0123456789abcdef";
  size_t n = 0;
  for (; prefix[n] != '\0' && n + 1 < outCap; ++n) out[n] = prefix[n];
  for (int shift = 60; shift >= 0 && n + 1 < outCap; shift -= 4) {
    out[n++] = hex[(epoch >> shift) & 0xF];
  }
  out[n] = '\0';
}

inline constexpr int32_t terrainBlocksAlong(int32_t tiles) { return (tiles + 15) / 16; }

inline constexpr uint64_t terrainBlockCount(int32_t sizeX, int32_t sizeY, int32_t sizeZ) {
  return static_cast<uint64_t>(terrainBlocksAlong(sizeX)) * terrainBlocksAlong(sizeY) *
         static_cast<uint64_t>(sizeZ);
}

inline constexpr size_t terrainRegionSize(uint64_t blockCount, uint32_t materialsCapacity) {
  return sizeof(TerrainHeader) + static_cast<size_t>(blockCount) * sizeof(uint64_t) +
         static_cast<size_t>(blockCount) * kTerrainTilesPerBlock * sizeof(TerrainTile) +
         materialsCapacity;
}

inline uint64_t* terrainVersions(TerrainHeader* h) {
  return reinterpret_cast<uint64_t*>(reinterpret_cast<uint8_t*>(h) + sizeof(TerrainHeader));
}
inline const uint64_t* terrainVersions(const TerrainHeader* h) {
  return terrainVersions(const_cast<TerrainHeader*>(h));
}
inline TerrainTile* terrainTiles(TerrainHeader* h) {
  return reinterpret_cast<TerrainTile*>(reinterpret_cast<uint8_t*>(h) + sizeof(TerrainHeader) +
                                        static_cast<size_t>(h->blockCount) * sizeof(uint64_t));
}
inline const TerrainTile* terrainTiles(const TerrainHeader* h) {
  return terrainTiles(const_cast<TerrainHeader*>(h));
}
inline TerrainTile* terrainBlockTiles(TerrainHeader* h, uint32_t blockIndex) {
  return terrainTiles(h) + static_cast<size_t>(blockIndex) * kTerrainTilesPerBlock;
}
inline const TerrainTile* terrainBlockTiles(const TerrainHeader* h, uint32_t blockIndex) {
  return terrainBlockTiles(const_cast<TerrainHeader*>(h), blockIndex);
}
inline uint8_t* terrainMaterials(TerrainHeader* h) {
  return reinterpret_cast<uint8_t*>(terrainTiles(h)) +
         static_cast<size_t>(h->blockCount) * kTerrainTilesPerBlock * sizeof(TerrainTile);
}
inline const uint8_t* terrainMaterials(const TerrainHeader* h) {
  return terrainMaterials(const_cast<TerrainHeader*>(h));
}

inline uint32_t terrainBlockIndex(const TerrainHeader* h, int32_t bx, int32_t by, int32_t bz) {
  return (static_cast<uint32_t>(bz) * static_cast<uint32_t>(h->blocksY) +
          static_cast<uint32_t>(by)) *
             static_cast<uint32_t>(h->blocksX) +
         static_cast<uint32_t>(bx);
}

// Bridge: initializes a freshly-created grid. Tiles start all-zero (shape
// Empty, kind None) with material 0 — callers must run the initial scan
// before publishing the epoch, or clients would read an "empty" map.
inline void initTerrain(TerrainHeader* h, uint32_t schemaVersion, int32_t sizeX, int32_t sizeY,
                        int32_t sizeZ, uint64_t epoch,
                        uint32_t materialsCapacity = kDefaultTerrainMaterialsCapacity) {
  std::memset(h, 0, sizeof(TerrainHeader));
  std::memcpy(h->magic, kTerrainMagic, sizeof(kTerrainMagic));
  h->layoutVersion = kTerrainLayoutVersion;
  h->schemaVersion = schemaVersion;
  h->sizeX = sizeX;
  h->sizeY = sizeY;
  h->sizeZ = sizeZ;
  h->blocksX = terrainBlocksAlong(sizeX);
  h->blocksY = terrainBlocksAlong(sizeY);
  h->blockCount = static_cast<uint32_t>(terrainBlockCount(sizeX, sizeY, sizeZ));
  h->materialsCapacity = materialsCapacity;
  h->epoch = epoch;
  std::memset(terrainVersions(h), 0, static_cast<size_t>(h->blockCount) * sizeof(uint64_t));
  const size_t tileBytes =
      static_cast<size_t>(h->blockCount) * kTerrainTilesPerBlock * sizeof(TerrainTile);
  std::memset(terrainTiles(h), 0, tileBytes);
  // Material 0xFFFF (none) on every tile.
  TerrainTile* t = terrainTiles(h);
  for (size_t i = 0, n = static_cast<size_t>(h->blockCount) * kTerrainTilesPerBlock; i < n; ++i)
    t[i].material = kTerrainNoMaterial;
}

// Client: validates a mapped grid. nullptr on success or a static error.
inline const char* checkTerrain(const TerrainHeader* h, uint32_t expectSchemaVersion) {
  if (std::memcmp(h->magic, kTerrainMagic, sizeof(kTerrainMagic)) != 0) return "bad terrain magic";
  if (h->layoutVersion != kTerrainLayoutVersion) return "terrain layout version mismatch";
  if (h->schemaVersion != expectSchemaVersion) return "terrain schema version mismatch";
  if (h->sizeX <= 0 || h->sizeY <= 0 || h->sizeZ <= 0) return "terrain map size not positive";
  if (h->blocksX != terrainBlocksAlong(h->sizeX) || h->blocksY != terrainBlocksAlong(h->sizeY))
    return "terrain block extent inconsistent";
  if (terrainBlockCount(h->sizeX, h->sizeY, h->sizeZ) != h->blockCount)
    return "terrain block count inconsistent";
  if (h->materialsCapacity == 0) return "zero terrain materials capacity";
  return nullptr;
}

inline constexpr uint32_t kMaxTerrainMaterialsCapacity = 256u * 1024 * 1024;
inline constexpr uint64_t kMaxTerrainBlocks = 1ull << 24;  // 16M blocks: far beyond any DF map

// Validates that the grid layout the header declares fits inside `mappedBytes`.
// Run after checkTerrain (which proves blockCount consistent with the map size).
inline const char* checkTerrainSize(const TerrainHeader* h, size_t mappedBytes) {
  if (mappedBytes < sizeof(TerrainHeader)) return "terrain mapping smaller than the header";
  if (h->materialsCapacity > kMaxTerrainMaterialsCapacity) return "terrain materials capacity exceeds the sane maximum";
  if (h->blockCount > kMaxTerrainBlocks) return "terrain block count exceeds the sane maximum";
  if (terrainRegionSize(h->blockCount, h->materialsCapacity) > mappedBytes)
    return "terrain header declares a layout larger than the mapping";
  return nullptr;
}

// Bridge: appends a material string, returning its index, or
// kTerrainNoMaterial if the table is full (caller should log once and
// publish the tile with no material). Not idempotent — the bridge keeps
// its own string -> index map. Safe against concurrent readers without
// the seqlock: bytes land before the count is released.
inline uint16_t terrainAppendMaterial(TerrainHeader* h, const char* str, size_t len) {
  const uint64_t count = atomicLoadAcquire(&h->materialCount);
  const uint64_t used = atomicLoadAcquire(&h->materialBytes);
  if (count >= kTerrainNoMaterial || len > 0xFFFF) return kTerrainNoMaterial;
  if (used + 2 + len > h->materialsCapacity) return kTerrainNoMaterial;
  uint8_t* table = terrainMaterials(h) + used;
  const uint16_t len16 = static_cast<uint16_t>(len);
  std::memcpy(table, &len16, 2);
  std::memcpy(table + 2, str, len);
  atomicStoreRelease(&h->materialBytes, used + 2 + len);
  atomicStoreRelease(&h->materialCount, count + 1);
  return static_cast<uint16_t>(count);
}

// Bridge: brackets one batch of tile/version writes.
inline void terrainBeginWrite(TerrainHeader* h) {
  atomicStoreRelease(&h->seq, atomicLoadAcquire(&h->seq) + 1);  // odd
  seqlockFence();
}
inline void terrainEndWrite(TerrainHeader* h, uint64_t simTick) {
  atomicStoreRelease(&h->gridTick, simTick);
  atomicStoreRelease(&h->terrainVersion, atomicLoadAcquire(&h->terrainVersion) + 1);
  atomicStoreRelease(&h->seq, atomicLoadAcquire(&h->seq) + 1);  // even
}

// Bridge: writes one block's tiles inside a begin/end batch and bumps its
// version. Returns the new version.
inline uint64_t terrainWriteBlock(TerrainHeader* h, uint32_t blockIndex, const TerrainTile* tiles) {
  std::memcpy(terrainBlockTiles(h, blockIndex), tiles, kTerrainTilesPerBlock * sizeof(TerrainTile));
  uint64_t* v = terrainVersions(h) + blockIndex;
  const uint64_t nv = atomicLoadAcquire(v) + 1;
  atomicStoreRelease(v, nv);
  return nv;
}

struct TerrainReadResult {
  uint64_t gridTick = 0;
  uint64_t terrainVersion = 0;
  uint64_t materialCount = 0;
  uint64_t materialBytes = 0;
};

// Client: copies the whole grid (versions + tiles + used material bytes)
// into caller buffers under the seqlock. `tiles` must hold blockCount*256
// entries, `versions` blockCount entries, `materials` materialsCapacity
// bytes. Returns false if the read stayed torn for maxRetries attempts
// (the bridge is writing continuously; try again next poll).
inline bool readTerrainGrid(const TerrainHeader* h, TerrainTile* tiles, uint64_t* versions,
                            uint8_t* materials, TerrainReadResult& out, int maxRetries = 8) {
  const size_t nBlocks = h->blockCount;
  for (int i = 0; i < maxRetries; ++i) {
    const uint64_t s1 = atomicLoadAcquire(&h->seq);
    if (s1 & 1u) continue;  // mid-write
    out.gridTick = atomicLoadAcquire(&h->gridTick);
    out.terrainVersion = atomicLoadAcquire(&h->terrainVersion);
    out.materialCount = atomicLoadAcquire(&h->materialCount);
    out.materialBytes = atomicLoadAcquire(&h->materialBytes);
    if (out.materialBytes > h->materialsCapacity) return false;  // corrupt
    std::memcpy(versions, terrainVersions(h), nBlocks * sizeof(uint64_t));
    std::memcpy(tiles, terrainTiles(h), nBlocks * kTerrainTilesPerBlock * sizeof(TerrainTile));
    std::memcpy(materials, terrainMaterials(h), static_cast<size_t>(out.materialBytes));
    seqlockFence();
    if (atomicLoadAcquire(&h->seq) == s1) return true;
  }
  return false;
}

// Walks a copied materials table: sets (*str, *len) to entry `index`'s
// bytes. O(index); callers iterate with terrainMaterialNext instead.
// Returns false when `offset` runs past `bytes`.
inline bool terrainMaterialNext(const uint8_t* table, size_t bytes, size_t& offset,
                                const char** str, uint16_t* len) {
  if (offset + 2 > bytes) return false;
  uint16_t l = 0;
  std::memcpy(&l, table + offset, 2);
  if (offset + 2 + l > bytes) return false;
  *str = reinterpret_cast<const char*>(table + offset + 2);
  *len = l;
  offset += 2 + l;
  return true;
}

}  // namespace df3d::shm
