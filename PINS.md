# Version pins

Supported build baseline. Exact dependency revisions are the committed Git submodule pointers.

## Game

| What | Value |
|---|---|
| Dwarf Fortress version | 53.16 |
| Steam app ID | 975370 |
| Steam build ID | 24557528 (PE timestamp 0x6A70A6D9) |
| Install discovery | `libraryfolders.vdf` → app 975370 (explicit path override supported) |

## Bridge stack

| What | Value |
|---|---|
| DFHack | 53.16-r1 + df3d patches (branch `df3d/53.16`, head `39b289bb0891b3d96f56a34defe6a6f5552f89aa`), fork: github.com/UncertainCat/dfhack |
| df-structures | 53.16-r1 + codegen teardown fix (`27097fdca2f4ab81492d0543b45518039d0a7fef`, branch `df3d/53.16`), fork: github.com/UncertainCat/df-structures |
| dfhooks | upstream + C4455 fix (`2a43bca84ccfbe3ad6605eb47a5afcdd348cd673`, branch `df3d/fixes`), fork: github.com/UncertainCat/dfhooks |
| Working tree | `external/dfhack` (pinned submodule; its own repository) |

## Wire compatibility

Management88 adds an explicit ProductionInspect contents read and optional
BuildingContentsPage. Pages retain native order, complete-vector revision and
continuation cursor; continuation requests require the same revision. Missing
historical contents remain unknown, never an invented empty list. Captions are
native UTF-8; item flags and eligibility are semantic fields. Each page holds
at most64 rows and128KiB of caption bytes within the management payload budget.
Rebuild/install bridge and viewer together on `Local\\df3d_management_v88`;
management87 is incompatible. Other wire versions are unchanged. Item writes
remain diagnostic until their typed request/receipt migration.

Management87 adds explicit FarmOperation.Remove and CancelRemoval. Both require
the exact displayed farm revision and return a freshly observed farm receipt.
They carry no crop, fertilizer or name fields. Rebuild/install bridge and viewer
together on `Local\\df3d_management_v87`; management86 is incompatible.
Snapshot/grid/session versions are unchanged.

Management86 adds FarmOperation.Rename and its required farm_name string.
The name is UTF-8 (at most90 bytes), losslessly converted to at most30 native
CP437 bytes at the safe point. Empty names clear the custom name; missing names
are invalid. Other operations cannot carry farm_name. Rebuild/install bridge
and viewer together using the management87 region above; management85 is incompatible.
Snapshot/grid/session versions are unchanged.

Management85 adds required custom/header names and removal/suspended/worker
facts to native farm snapshots. All participate in the exact content revision.
Names are UTF-8 from native CP437, bounded to1536 bytes for the reader's512-byte
source limit. Missing fields in old receipts cannot synthesize these facts or
new revisions. This snapshot contract remains required in management87;
snapshot/grid/session versions are unchanged.

Management84 introduced the stable plant raw ID carried by each native farm choice
(`raw_id`, nonempty and at most128 bytes). The owned ID participates in the farm
revision and selects installed artwork independently of translated names and
native menu state. Older receipts cannot synthesize raw IDs or new revisions;
use the management87 region above for the current bridge and viewer.
Snapshot/grid/session versions are unchanged.

Management83 renamed action19 to FarmEdit and added FarmOperation:
Crop (default), FertilizationToggle, and SeasonalFertilization. All require
the exact displayed expected_revision and selected season. Crop owns crop_id;
seasonal intent owns seasonal_fertilization (0/1). Other fields are rejected.
The farm snapshot adds current/max fertilizer, pending fertilizer jobs and
the seasonal flag; all four participate in its revision. Older recordings
cannot synthesize these facts or the new revision. Completed alone carries
an authoritative fresh snapshot; Unknown must never be replayed automatically.
Native fertilizer helpers are
verified separately; the complete farm presentation remains unfinished.
The existing tracker popup contract from management80 remains unchanged.


Snapshot schema **11** and resident terrain grid **6** preserve root tissue
separately from trunk wood, in addition to the schema10/grid5 semantic tile
subterranean status, brook-surface identity and native building occupancy.
The fixed snapshot TileState remains eight bytes; environment facts use a
sparse per-block vector. Resident tiles are fourteen bytes. Rebuild/reinstall
bridge and viewer together; older schema/grid readers reject the new layouts.
Management is **78**. Session **12** adds authoritative moon phase (0..27,-1 unavailable) to
the original fortress name, rank and capital status from session11. Rebuild/reinstall bridge and viewer together; the v12 session
region rejects older peers. Missing old identity facts must remain unavailable,
not be inferred from the translated name. Snapshot/grid versions are unchanged.

Management protocol **71** adds structured Location naming reads, native choice
pages and revision-bound edits. Bridge and viewer must move together to
`Local\\df3d_management_v71`; v70 peers remain isolated. CP437 names/filter bytes
and native word/grammar identity are explicit; old recordings cannot infer these
from translated display names. Snapshot/grid/session versions remain unchanged.
The v71 integration is in progress and is not a release acceptance claim.

Management protocol **70** adds revision-bound Location quantity intents:
Set, Increase and Decrease for supplies and library copies. Rebuild/install
bridge and viewer together for `Local\\df3d_management_v70`; older peers cannot
submit these edits. Existing quantities remain signed raw native values; no
migration rounds partial units or invents absent facts. Snapshot/grid/session
versions are unchanged.

Management protocol **69** adds optional saved squad symbol identity and RGB
colors to squad candidate rows. Rebuild/install bridge and viewer together;
the v69 management region isolates older peers. Missing old-recording symbols
remain unavailable; never fabricate colors or infer them from native texture
handles. Snapshot/grid/session versions are unchanged.

Management protocol **57** adds the revision-bound stockpile `LinkTarget` read.
It returns zero or one eligible native target for a tile and direction. Rebuild
and install bridge and viewer together; the v57 region isolates older peers.
Older recordings cannot supply target eligibility from generic building hits.

Management protocol **56** adds coordinate-based native ordered world-hover entries, including text, colors, kinds and object IDs.
Rebuild/install bridge and viewer together; the v56 region isolates older peers.
Old recordings lack hover prose and must not synthesize it from tile identifiers.

Management protocol **54** adds owned native construction warning text, separate
from placement validity and refusal messages. Rebuild/install bridge and viewer
together; v54 isolates peers without this field. Missing warning text in older
recordings remains unavailable and must not be inferred from refusal messages.

Management protocol **53** adds explicit `cancel_removal` intent for building
removal. Rebuild/install bridge and viewer together: v53 isolates older peers
so an old bridge cannot interpret cancellation as a new deconstruction request.

Management protocol **52** adds an explicit native Last-material name to each
construction material row. Standalone decorated/artifact display names and
singular generic names cannot establish that copy. Missing old-recording data
leaves history unavailable; do not infer it by stripping decoration or pluralizing.
Rebuild/install bridge and viewer together; v52 isolates older peers.

Management protocol **51** distinguishes standalone construction item rows from
same-material generic groups using individual_id (-1 for a group). Standalone
rows and selections require exactly that item and cannot substitute another.
Rebuild/install bridge and viewer together; v51 isolates older peers. Old
aggregate recordings cannot establish standalone identity and must not infer it
from a decorated name. Snapshot/grid/session versions are unchanged.

Management protocol **50** carries the last selected construction corner as a
semantic material anchor and permits the complete stair volume in Materials
queries. Cache identity and Place validation preserve both. Rebuild/install
bridge and viewer together; v50 isolates older peers. Older normalized requests
do not establish the missing gesture endpoint or multi-level admission.

Management protocol **49** adds semantic PrepareAlertDismissal and DismissAlert
commands (68/69) with client/fortress-bound source receipts. The v49 shared-memory
region isolates older peers. Report payload fields retain their representation;
for these actions, expected_list_revision/list_revision carry the dismissal
receipt and total carries the captured/cleared reference count. No migration
fabricates receipts. Native UI Alert and interruption acknowledgment stay retired.

Protocol **48** adds complete retained alert Group reads and group-owned
Text, selected by notification category or the distinct red ALERT source. Rebuild
bridge and viewer together; v47 lacks these selectors. Tab, unit-log, group and
independent Text owners remain separate. Do not invent missing references or text
when migrating older summaries. Session is now **12**; dependency/game pins are
unchanged.

## Viewer host

| What | Value |
|---|---|
| Godot | 4.7.2 stable, Steam install (`godot.windows.opt.tools.64.exe`, `4.7.2.stable.steam.ed1daf0bf`) |
| godot-cpp | commit `7e18e40d7591429f915035a7de7cf79457d555cc` at `external/godot-cpp` (bundled extension API: 4.7-stable) |

godot-cpp is pinned to a master commit whose bundled extension API matches Godot 4.7, not to a release tag.

## Tooling (vendored under `third_party/`)

| What | Value |
|---|---|
| FlatBuffers | v25.12.19 (release tag `v25.12.19-2026-02-06-03fffb2`) |
| flatc | Windows release binary from that tag, `third_party/flatbuffers/bin/flatc.exe` |
| doctest | pinned single header, see `third_party/doctest/VERSION` |

## Toolchain (machine-provided, recorded for reproducibility)

| What | Value |
|---|---|
| Compiler | MinGW-w64 g++ 15.1.0 (MSYS2), C++20 |
| CMake | 3.30.5 |
| Generator | MinGW Makefiles (`mingw32-make`) |
