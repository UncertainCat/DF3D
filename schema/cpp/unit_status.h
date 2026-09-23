#pragma once
#include <cstdint>

// Semantic snapshot state. Bit positions are append-only (UnitState.status_flags).
namespace df3d::unit_status {
constexpr uint64_t Sleeping=1ULL<<0, Webbed=1ULL<<1, Stunned=1ULL<<2,
    Unconscious=1ULL<<3, Fey=1ULL<<4, Secretive=1ULL<<5, Possessed=1ULL<<6,
    Macabre=1ULL<<7, Fell=1ULL<<8, Melancholy=1ULL<<9, Raving=1ULL<<10,
    Berserk=1ULL<<11, Traumatized=1ULL<<12, TellingStory=1ULL<<13,
    RecitingPoetry=1ULL<<14, PerformingMusic=1ULL<<15, Dancing=1ULL<<16,
    Migrant=1ULL<<17, NoJob=1ULL<<18, NoDestination=1ULL<<19,
    Hungry=1ULL<<20, Thirsty=1ULL<<21, Drowsy=1ULL<<22,
    Stressed=1ULL<<23, Distracted=1ULL<<24, Tantrum=1ULL<<25,
    Oblivious=1ULL<<26, Depression=1ULL<<27, Enraged=1ULL<<28,
    MartialTrance=1ULL<<29, Terrified=1ULL<<30, Wrestling=1ULL<<31,
    MinorInjury=1ULL<<32, MajorInjury=1ULL<<33, Paralyzed=1ULL<<34,
    Nausea=1ULL<<35, Winded=1ULL<<36, Fevered=1ULL<<37,
    Yielding=1ULL<<38, PlayingMakeBelieve=1ULL<<39,
    Projectile=1ULL<<40, Grounded=1ULL<<41, Climbing=1ULL<<42, Baby=1ULL<<43;
}
