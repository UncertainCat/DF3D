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

Management135 adds read-only ResidentsActivityRead (action84) on the
`residents_activity` domain. Rebuild both peers for
`Local\df3d_management_v135`; Management134 peers must not be mixed.
Requests carry unit/activity/event IDs and1..1024 text columns. Successful
results retain native markup words, semantic link IDs and native word positions;
rejected results carry no page. ResidentRow gains optional `activity_target`
with the observed activity/event identity. Absence remains unobserved/unavailable.
The new contract is staged; it does not expose the Residents screen or establish
native acceptance for every activity family.

Management134 adds read-only CreatureSheetLocate (action83), using CreatureRequest
and CreaturePosition on the `creature_sheet_location` domain. Rebuild both peers
for `Local\df3d_management_v134`; Management133 peers must not be mixed. It resolves
the native unit-sheet destination at request time without follow-mode filters.
Successful coordinates are signed16 with x different from the native -30000
sentinel; unavailable/missing targets reject without a position. Existing
CreatureLocate retains its follow eligibility and nonnegative-coordinate contract.
No native sheet or camera is opened by this semantic read.

Residents row `position` is an optional additive Management133 observation of
raw signed16 unit coordinates captured with the row. Absence means unobserved;
do not replace it with a current follow position or manufacture coordinates.
Older133 readers ignore it. Existing requests and required fields are unchanged.

Residents row `assignments` is an optional additive Management133 observation
using existing LocationStaffAssignment semantics. Absent means unobserved; an
empty vector means observed no assignments. Older133 readers ignore this field.
The limit is256 entries per row; names, custom codes and32 bytes per entry share
the128KiB row-content budget. No action, required field or existing meaning changes.

Management133 adds ResidentsSpecialize, a dedicated native Residents action,
and optional per-row specialization receipts. Rebuild both bridge and viewer for
`Local\\df3d_management_v133`; Management132 peers are incompatible with this
channel and must not be mixed. Existing action ordinals are unchanged; the new
action is82. An edit carries the stable unit ID, positive observed revision and
desired only-assigned value. Applied, Rejected, Stale, Unavailable and Unknown
are explicit outcomes; Unknown must never be automatically replayed. Successful
edits require a fresh read before another edit. An absent row receipt conveys no
editing authority; do not invent it when reading older observations.

Management132 adds ResidentsRowsRead for native row content in explicit batches
of1–64 unique unit IDs, with a3–30-column name width and gender-display flag.
Rebuild both peers for `Local\\df3d_management_v132`. A successful reply contains
the complete requested batch in request order; stale or unavailable inputs must
reject the batch rather than silently omit rows. Text is UTF-8, unlike the raw
textbox query bytes in ResidentsQuery. Older observations leave row content
absent. Captions, color effects and Activity text are separate from the complete
ordered ID query. Bridge/adapter acceptance is recorded in ENGINEERING.md;
the complete Residents screen remains staged.

Residents row `happiness` is an additive Management132 observation with default-1
(unobserved). Values0..6 are native displayed tiers, happiest through most
distressed; older readers ignore the field and older buffers retain absence.
It does not change existing required fields, actions or defaults.

Residents row `sheet_icon` is an optional additive Management132 observation.
Older132 buffers omit it and older readers ignore it; no required field, action,
default or existing meaning changes. Absence means no artwork observation, never
a request to substitute a map sprite. Appearance recipes have a separate128KiB
batch budget in addition to the existing128KiB text budget.

Management131 adds the dedicated ResidentsQuery request and complete ordered
unit-ID result. Rebuild both peers for `Local\\df3d_management_v131`; older
observations leave this result absent. Query bytes retain native textbox input,
including partial UTF-8; do not convert them to CP437. The contract is separate
from CitizenList and its Work Details pagination. Native query transport and
public Residents UI acceptance are tracked in ENGINEERING.md.

Management130 adds dye-stage navigation and native dye headings, color swatches
and submenu choices to Work order Details. Rebuild/install both peers on
`Local\\df3d_management_v130`. Older recordings leave these observations absent;
do not infer dye colors, available ingredients or selection effects from captions.

Management129 adds optional native current-setting text to Work order Details.
Rebuild/install both peers on `Local\\df3d_management_v129`. Earlier recordings
leave the current setting unobserved; do not infer it from labels or choices.

Management128 adds artwork name queries, component edits and native word pages,
and permits the owned initial draft on the artwork root. Rebuild/install both
peers on `Local\\df3d_management_v128`. Older observations have no name-editor
state; do not synthesize word choices or editable name components.

Management127 carries viewer-owned artwork drafts, compound candidate IDs, and
separate draft editing, name generation and image commit intents. Draft previews
retain native text without installing an image. Rebuild/install both peers on
`Local\\df3d_management_v127`. Earlier recordings have no draft observations;
do not synthesize names, elements, relationships or commit authority.

Management126 adds optional native artwork row labels and revision-checked hover
previews, including the requested text width. Preview reads cannot carry a
selection. Rebuild/install both peers on `Local\\df3d_management_v126`. Missing
labels and previews in earlier recordings remain unobserved. Other channels are
unchanged.

Management125 adds a distinct artwork intent and observation under Work order
Details. Subject IDs retain their full simulation range; pages carry native
captions, bounded rows and separate list revisions. Entering Image is an explicit
update, distinct from browsing and selecting a subject. Rebuild/install both peers
on `Local\\df3d_management_v125`. Older recordings have no artwork observation or
selection authority; do not synthesize it. Other channels are unchanged.

Management124 adds optional native Work order Details reads and exclusive selections,
with separate order and choice revisions, native option captions and paged choices.
Rebuild/install both peers on `Local\\df3d_management_v124`. Older recordings have
no Details observation or selection authority; absent choice/count observations
remain absent. Other channels are unchanged.

Management123 adds optional native global work-order availability and validation
observations, assigned-workshop names, and custom building raw codes for categories.
Rebuild/install both peers on `Local\\df3d_management_v123`. Missing observations
in older recordings remain unknown and grant no Create authority. Other channels
are unchanged.

Management122 adds an exclusive native condition-filter choice, identified by
catalog kind/index and both order/catalog revisions. It carries no copied filter
values. Rebuild/install both peers on `Local\\df3d_management_v122`; old recordings
omit this intent and do not acquire filter-edit authority.

Management121 adds an exclusive native suggested-condition intent, carrying the
suggestion index, target order/workshop and observed order revision. It carries
no copied filter fields. Rebuild/install both peers on `Local\\df3d_management_v121`.
Older recordings omit this intent; other channels are unchanged.

Management120 adds optional native condition item captions and suggested-condition
observations. Rebuild/install both peers on `Local\\df3d_management_v120`.
Absence in older recordings remains unknown, distinct from an observed empty list.
Other channels are unchanged.

Management119 adds optional native work-order phase, validation requirement and
Details availability observations. Rebuild/install both peers on
`Local\\df3d_management_v119`. Legacy rows lack this observation; do not infer it
from old order flags or a viewer clock. Other channels are unchanged.

Management118 adds absolute general-order limit updates for native numeric entry.
Rebuild/install both peers on `Local\\df3d_management_v118`; management117 cannot
execute this intent. Older recordings do not supply numeric-edit receipts.

Management117 adds native workshop order-profile reads and general-order limit steps.
Rebuild/install both peers on `Local\\df3d_management_v117`. Older recordings
cannot supply manager availability or limit authority; do not synthesize them.
Other channels are unchanged.

Management116 adds native assignment membership to each workshop candidate row.
Rebuild/install both peers on `Local\\df3d_management_v116`. Older rows cannot
synthesize occupation/workshop/furnace/work-detail indicators; no recording is
migrated by inventing these facts. Other channels are unchanged.

Management115 adds independent assigned-worker display facts and the native
remove/work-mode actions. Rebuild/install both peers on
`Local\\df3d_management_v115`. The assigned caption and work-mode authority cannot
be inferred from a candidate row or an older recording. Other channels are unchanged.

Management114 adds bounded workshop worker pages and revision-bound worker
selection via the production channel. Rebuild/install bridge and viewer together
on `Local\\df3d_management_v114`. Profile and candidate-list receipts are distinct;
legacy recordings cannot synthesize candidates or assignment authority. Map,
grid and session versions are unchanged.

Management105 adds independent CreatureExpelRead and CreatureExpelApply commands.
Preview carries native eligibility, refusal code, ordered group, names, colors,
full-body appearance recipes and destinations. Apply requires the exact ordered
departing group and revalidates it before mutation; Unknown must never be replayed.
Rebuild both endpoints on `Local\\df3d_management_v105`; management104 is
incompatible. Older captures have no Expel authority. The unit UI remains staged.

Management104 adds CreatureLocate, an independent native follow-position read
with a stable unit ID and confirmed tile. Rebuild both endpoints on
`Local\\df3d_management_v104`; management103 is incompatible. Older captures
have no follow authority. This does not expose the staged unit UI.

Management103 adds independent creature header reads and revision-checked
nickname/profession edits with confirmed receipts. Rebuild both endpoints on
`Local\\df3d_management_v103`; management102 is incompatible. Older captures do
not acquire synthetic header authority. The unit editor remains staged until
its rendered workflow and lifecycle checks are complete.

Management102 also permits confirmed eligible Melt contents receipts during
Box removal. The native eligibility and mark/cancel routines remain authoritative.
Rebuild both endpoints on `Local\\df3d_management_v102`; management101 is
incompatible. No historical receipt or missing authority is synthesized.

Management101 permits confirmed contents Forbid/Dump/Visibility receipts during
Box removal. Melt during removal remains unverified and refused. Rebuild both
endpoints on `Local\\df3d_management_v101`; management100 is incompatible.
No historical receipt or missing authority is synthesized.

Management100 adds independent building header reads and revision-checked actions.
The request flag excludes farm/item/contents fields; header results carry their
own snapshot, typed outcome and confirmed operation. Current production supports
Box targets only. Both endpoints must rebuild on `Local\\df3d_management_v100`;
management99 is incompatible. Missing historical header facts remain unknown.

Management99 adds ItemInspectionAppearance to building contents rows, including
the legacy building-item wrapper. BOX and INSTRUMENT rows require coherent
appearance; other rows may omit it. Appearance participates in the complete
contents revision and survives paging, receipts and both codecs. Rebuild both
endpoints on `Local\\df3d_management_v99`; management98 is incompatible. Missing
facts in historical recordings remain unknown, never inferred from captions.

Management98 extends ItemInspectionAppearance with instrument family and placement
facts. INSTRUMENT snapshots require appearance and family0..3/placed0..1; other
item types require both fields absent (-1). The fields participate in item edit
revisions and are validated across both endpoints. Rebuild bridge and viewer on
`Local\\df3d_management_v98`; management97 is incompatible. Historical missing
instrument facts remain unknown rather than inferred from item names.

Management97 adds independent item appearance, required for BOX inspection and
optional for other verified item families. The shared ItemInspectionAppearance
also carries container appearance. Own material/subtype must match the item's
identity facts; all appearance fields participate in its revision. Rebuild both
endpoints on `Local\\df3d_management_v97`; management96 is incompatible. Missing
appearance in historical recordings remains unknown, never inferred from names.

Management96 adds required semantic appearance to container carriers: native
material/subtype/color tokens, stack size and artifact/spider flags. Unit carriers
must omit it. Appearance participates in the independent item revision and is
validated across the bridge/model/viewer path. Rebuild both endpoints on
`Local\\df3d_management_v96`; management95 is incompatible. Historical recordings
without these facts remain unknown; do not infer appearance from a carrier name.

Management95 adds an optional native item carrier (container or unit) to independent
item observations and their revision. A building holder and carrier are mutually
exclusive; stockpile location remains independent. Carrier kind, ID, native name
and container item type are validated throughout the bridge/model/viewer path.
Rebuild both endpoints on `Local\\df3d_management_v95`; management94 is incompatible.
Missing carrier observations in historical recordings cannot be invented.

Management94 adds `stockpile_categories` to independent item snapshots. It is
DF's 17-bit stockpile_group_set and participates in the item observation revision.
A stockpile link requires categories0..131071; absent links require -1. Rebuild
bridge and viewer together on `Local\\df3d_management_v94`; management93 is
incompatible. Never infer categories missing from historical observations.

Management93 adds explicit `independent_item` inspection and flag-edit intents
and a separate IndependentItemState snapshot/receipt. These requests exclude
building identity and use an item observation revision, preserving the existing
building-contents contract. Optional holder and spatial stockpile links remain
distinct; absent historical observations cannot be synthesized. Rebuild/install
bridge and viewer together on `Local\\df3d_management_v93`; management92 is
incompatible. Other wire versions are unchanged.

Management92 adds ProductionInspect locate_item requests and optional ItemPosition
responses. Position-only requests require item_id and exclude building identity,
contents paging, revisions and edit fields. Replies carry only the requested item
ID and a valid effective map position from DF; missing/invalid targets reject.
Historical absence remains absent. Camera/follow state stays viewer-owned.
Rebuild/install bridge and viewer together on `Local\\df3d_management_v92`;
management91 is incompatible. Other wire versions are unchanged.

Management91 adds optional BuildingItemSnapshot and ItemBuildingHolder. A
ProductionInspect request with item_id selects one contained item; it cannot mix
contents paging, seasonal controls or edit fields. Inspection starts without a
revision precondition because native formatting can initialize weight caches;
the response carries the post-format contents revision for later edits. Text is
owned and bounded (128KiB name, 32KiB description, 128-byte weight, 512-byte
holder name). Absent historical snapshots or holders remain absent; never
synthesize them from contents or map records. Rebuild/install bridge and viewer
together for the current management version; management90 is incompatible. Other
wire versions are unchanged. This contract alone does not expose the item sheet.

Management90 adds item_type, material_token and subtype_raw to every contents
row. These owned semantic identities participate in the full-vector revision;
no texture handles, native cache or resident map item is required. Missing
material/subtype information is an empty token, never an invented default.
Item types are0..92 and UTF-8 tokens are bounded to256/128 bytes. Rebuild/install
bridge and viewer together on `Local\\df3d_management_v90`; management89 is
incompatible. Historical rows without these facts cannot supply artwork.
Other wire versions are unchanged.

Management89 adds FarmOperation.ItemForbid/ItemDump/ItemMelt/ItemHidden with
required item_id, explicit item_value and the displayed contents revision.
These intents carry no season/crop/fertilizer/name fields. Only Completed grants
a fresh contents page and typed receipt identifying the item, operation and
observed desired value. Rejected/Stale/Unknown grant no contents authority.
Rebuild/install bridge and viewer together on `Local\\df3d_management_v89`;
management88 is incompatible. Other wire versions are unchanged.

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
