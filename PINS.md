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

Current management protocol234 adds revision-bound depot checkbox drafts and
retained sorting choices to goods reads. Protocol233 introduced whole-batch
commits and explicit outcomes;232 introduced owned goods reads.
Both peers use `Local\df3d_management_v234`; rebuild bridge and viewer together.
Older recordings must not synthesize goods snapshots or commit receipts.
Migration guidance is in ENGINEERING.md's depot goods transport sections.

Management231 added depot body facts and the explicit DepotMode
building-header intent. Older recordings contain no depot body and must not
synthesize availability, broker or access facts. Migration guidance is in
ENGINEERING.md's depot transport section.

Management230 introduced native well status in building headers.

Management229 adds paired optional grate orientation/open
facts. Both peers use `Local\df3d_management_v229`; rebuild bridge and viewer
together. Older appearances retain unknown facts. Migration and protected
compatibility evidence are in ENGINEERING.md's grate transport section.

Management225 adds explicit missing-building identity to header reads. A confirmed
missing target is an Ok read with no snapshot; failed reads and edit outcomes
remain distinct. Rebuild bridge and client together; the defaults and mailbox
are225 (`Local\df3d_management_v225`). Earlier recordings imply no deletion fact.

Management224 adds optional native funerary body facts to building headers:
coffin owner/Tomb captions, notices, memorial subject and owner artwork. Rebuild
bridge and client together; `Local\df3d_management_v224` isolates223. Earlier
recordings contain no funerary body and must not synthesize one. Specialized
panel exposure still requires separate runtime and rendered acceptance.

Management212 adds owned unit-selector appearance to selection identities.
Unit captions use the existing native name field. Only Unit identities may
carry unit appearance. Rebuild bridge and client together; the defaults/mailbox
are212 (`Local\\df3d_management_v212`). Older recordings imply no unit-group
artwork; do not fabricate it from the new field.

Management211 adds item type and owned ItemInspectionAppearance to selection
identities. ItemList members require those facts; other target kinds cannot carry
item appearance. Rebuild both peers: `Local\df3d_management_v211` isolates210.
Earlier recordings do not imply group artwork and must not synthesize it.

Management210 connects the owned tile-selection provider. SelectionState.members
contains typed unit/item group members, and SelectMember chooses a row using a
client/world-bound receipt. Native group and engraving IDs use-1 with tile
identity. Rebuild both peers: `Local\df3d_management_v210` isolates209. Earlier
recordings have no group-member projection; do not invent it from item contents.

Management209 adds retained byte continuations for Production Inspect, Queue and
JobEdit replies larger than the512KiB mailbox. Continuations use Inspect with
only `production_reply`, never the original action payload. The client assembles
the entire reply before publishing its original identity and result. Stocks and
Production share a64MiB retained budget with distinct capture families. Expired
captures fail without replay; world changes retire them. Rebuild both peers:
`Local\df3d_management_v209` isolates208. Legacy recordings imply no continuation
or additional recipe facts. Production menus now allow16384 recipes within the
retained reply budget; Work orders retain their independent128 recipe limit.
ProductionDyeStatus color_id=-1 with zero RGB represents native information
without a color swatch; older absent status fields remain absent.

Management208 adds ProductionRequest.expected_previous_job_id for an exclusive
Move up intent and ProductionJob.can_move_up (-1 unknown,0 unavailable,1 available).
The predecessor must be a distinct nonnegative job ID; legacy observations omit
the capability in Godot. Rebuild both peers: Local\df3d_management_v208 isolates207.
Move up dispatch validates the observed predecessor at a safe point before the
native-equivalent adjacent swap; flags and worker assignments are preserved.

ProductionJob.active is an additive optional tri-state observation under208.
Absent legacy values remain unknown (-1); known0/1 comes from native d02850.
It adds no request semantics and does not change the mailbox or required version.

Management207 adds optional `ProductionState.task_parent`. Present empty means
native Back to root; present nonempty means Back to that opaque category; absent
retains Cancel/legacy behavior. A parent requires a known nonempty current
category, is bounded at256 bytes and cannot equal that category. Rebuild both
peers: `Local\df3d_management_v207` isolates206. The contract is wired through
codecs. Forge dispatch produces owned parent targets, and the staged viewer
uses them for Back navigation; public workshop exposure remains gated.

Management206 adds an opaque workshop `task_category` request and optional
category context/list observations. Rebuild both peers:
`Local\df3d_management_v206` isolates Management205. Empty requests select root;
absent response context means category support is unknown, not a known empty
menu. Category keys are bounded at256 bytes, captions512, and lists128 entries.
Native reaction-category dispatch and navigation now consume this contract for
Carpenter, Kitchen, Still and WoodFurnace. Invalid or unreachable keys reject;
other workshop families and builtin category paths remain unfinished.

Management205 introduced workshop job Priority intent and observation fields.
ProductionJobEdit carries desired `priority` and displayed `expected_priority`
as0/1; the two must differ, and Priority cannot be mixed with another edit.
Job observations use-1 for unknown/legacy, so old recordings do not invent an
inactive value. The Godot dictionary omits unknown observations. Native effect dispatch and UI wiring now consume these fields; the workshop
surface remains staged while its other workflows are incomplete. Older peers
cannot issue or observe Priority edits. Existing production actions are unchanged.

Management151 adds owned KitchenRead98/KitchenApply99 in `kitchen_menu`.
Rebuild both peers: `Local\df3d_management_v151` isolates Management150.
Queries carry filters and ordered sort priorities; reads return native rows and
the full ordered exclusion receipt. Edits require that receipt plus the target's
identity/count/capabilities. Successful edits return no stale list; refresh it.
Rejected/Stale/Unknown replies carry no authoritative rows or exclusions, and
Unknown is write-only. The former menu-coupled Kitchen actions remain retired.
No old recording can supply these missing native facts. Runtime dispatch and
screen exposure are staged separately from this breaking migration.

Management147 extends Standing orders to Forbidding(category3, ten settings),
Petitions(category4, six) and Other(category6, seven scalar settings). Categories3/4
accept values0..2; Other announcements accept0..3 and its other controls0..1.
Category5 remains outside the scalar contract because Chores is a separate
roster/labor workflow. Rebuild both peers: `Local\df3d_management_v147` isolates
Management146. All returned rows in3/4/6 are visible/editable. Native adapters
supply effects and receipts; UI exposure remains staged.

Management146 adds Hauling(category1) and Refuse(category2) Standing orders
contracts and replaces `available` with independent `visible`/`editable` fields.
Workshops(category0) retains eleven settings; Hauling has six and Refuse ten.
Reads reject write fields; edits carry bounded ID, expected value and desired
value. Hidden controls cannot be editable. Rejected/Stale/Unknown replies have
no settings, and unknown mutations must not replay. Rebuild both peers:
`Local\df3d_management_v146` isolates Management145. Native category dispatch
uses the verified Hauling/Refuse adapter and returns updated dependency flags.
Existing Workshops remains supported; category UI exposure remains staged.

Management144 adds `CitizenState.outcome_unknown`. It is valid only for a rejected
citizen mutation with no returned rows, selected targets, page cursor or list
receipt. Godot exposes it as the service's `outcome="unknown"`; it must not be
replayed. Read replies and confirmed/pre-write outcomes leave the flag false.
Rebuild both peers: `Local\df3d_management_v144` rejects Management143 peers.
Runtime write-boundary wiring classifies native write failures; protected112740
verifies a post-rename
receipt fault, with other mutation/fallback fault paths still untested live.
Ordinary native creation compatibility passes in protected111719; see ENGINEERING.md.


Management143 adds revision-bound `WorkDetailSettingsRead` and
`WorkDetailSettingsToggle` in `work_detail_settings`. Read returns the complete
native catalog and current allowed labors; Toggle is a one-shot definition edit,
not a bulk replacement or forced worker recalculation. Both require the selected
detail's exact revision. Rebuild both peers; `Local\df3d_management_v143` rejects
Management142 peers. Older snapshots do not imply an empty catalog or disabled
labors. Native handler acceptance is recorded in ENGINEERING.md; full editor exposure
still requires rendered workflow and lifecycle acceptance.

Management142 adds `WorkDetailRowsRead` using bounded worker IDs and an exact
selected-detail revision. Shared row observations gain ordered native skills
and membership; Work Details rows do not observe activity or happiness. Older
Residents requests retain their meaning and cannot carry detail authority or
skill results. Rebuild both peers; `Local\df3d_management_v142` rejects older
Management141 peers. Missing older fields do not imply an empty skill list or
nonmembership.

Management141 adds `WorkDetailWorkersQuery`: a selected detail index and exact
inspection revision, native sort/direction and bounded raw textbox bytes. It
returns the complete ordered-ID `ResidentsState` payload. Rebuild both peers;
`Local\df3d_management_v141` rejects older Management140 peers. There is no
migration of an old query into a guessed work-detail target.

Management140 adds exclusive nested artwork draft intents to job settings reads
and edits, with exact source revisions and shared bounded draft/name payloads.
Job draft writes can return their updated draft plus an Applied receipt, or an
explicit Unknown outcome after uncertain registration/RNG work. Unknown writes
must never be replayed. Both peers require rebuilding and use
`Local\df3d_management_v140`; older Management139 peers are incompatible.

Management139 extends `JobSettingsApply` with optional artwork page and query.
Ordinary edits retain their existing shape. Artwork entry, artist choice and
related-subject/image assignments have distinct choice/revision bounds and use
the existing Applied/Stale/Rejected result. Rebuild both peers for
`Local\df3d_management_v139`; Management138 peers are incompatible. Unknown
outcomes are never replayed. No migration invents artwork selection authority.

Management138 adds read-only artwork pages to `JobSettingsRead`. Optional page,
list revision, hovered subject and preview width inputs produce a separate artwork
payload with bounded rows and previews. Material reads keep their existing fields;
artwork drafts/edits are not part of this addition. Rebuild both peers for
`Local\df3d_management_v138`; Management137 peers are incompatible. No migration
fabricates job or list authority from older recordings.

Management137 adds `JobSettingsApply` (action86) to `job_settings`, with a
separate edit request containing exact job/holder/resident IDs, selected option,
job and choice revisions and original choice ID. Its result distinguishes
Applied, Stale and Rejected and contains no retained read catalog. Rebuild both
peers for `Local\df3d_management_v137`; Management136 peers are incompatible.
No migration fabricates edit authority from older reads.

ResidentRow gains optional additive `job_target` (job and holder IDs) on
Management136. Older producers omit it; older readers ignore it. It is mutually
exclusive with `activity_target`; no migration fabricates a job identity.

Management136 adds read-only JobSettingsRead (action85), domain `job_settings`.
Rebuild both peers for `Local\df3d_management_v136`; do not mix Management135
peers. Requests identify the job, holder building and optional current resident,
with a selected option, bounded query and cursor. Results carry separate job and
choice revisions, native options/captions, and up to64 choices per page. Rejected
or unrelated results carry no job settings. This staged contract does not expose
unfinished Residents or workshop Tasks controls, or authorize job edits.

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

Standing orders Workshops adapter pins input4331ca..4334fa (FNV64
`d165a25c665d4e6d`) and verifies the eleven simulation-global addresses.
Native menu input/render functions are never called at runtime. Protected114842
compares eight available controls and their full cycles; the remaining three
automation controls require enabled-reaction acceptance. See ENGINEERING.md.
