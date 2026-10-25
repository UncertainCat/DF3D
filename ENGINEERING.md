## Native construction site support (DF 53.16)

The captures below document the native-service migration. For the current
verified construction scope, see [Construction coverage boundary](#construction-coverage-boundary).

Construction preview and placement now delegate Door wall support to DF's
coordinate-only routine at RVA `0xa827b0`. The plugin verifies the supported PE
and fingerprints the routine and its support-tile classifier before calling it
at a safe point. Unknown builds/inputs fail closed. It returns owned scalar
results and the sourced refusal `Needs adjacent wall`; Godot remains asynchronous.
No native build request, menu, cursor or redraw scratch is borrowed or changed.
The old Lua wall/fortification adjacency approximation is removed. Generic floor,
occupancy, liquid and DFHack construction checks remain; this is not full native
placement parity. Sourced Door refusal presentation is described below.

The same module, `bridge/plugin/construction_site_native.cpp`, delegates Well
support to RVA `0xa829a0` and Hatch/GrateFloor/BarsFloor adjacency to `0xa82890`,
with separate fingerprints. This removes the Lua Well approximation and supplies
the missing floor-opening support check. Preview and commit both recheck support.
Native refusals are `Needs open space` and `Surrounded by empty space`.
`df3d site-support-read <family> x y z` exposes this narrow predicate
(0 supported, 8/16/17 refusal, -1 unknown); `door-support-read` remains a Door alias.

`fixtures/construction/site_support.json` records 16 synthetic terrain cases from
protected oracle `build/construction-support-oracle-20261022-214726`. Matching
request, closed menu and Bed selected all agree without request/redraw changes.
This is support validation, not full placement parity or exhaustive terrain coverage.
Native captures `build/site-refusal-native-20261022-214839` and
`build/site-refusal-native-20261022-214912` establish the four families' copy.
Viewer `build/hatch-refusal-main-20261022-215003` passed visible refusal, recovery,
exact item48520 selection and natural hatch completion (+575 frames). The rejected
empty-space target in that initial run used a controller intent.
Screenshots were inspected. Source manifests stayed unchanged; no sessions saved.
Diagnostics were known engine issues only. Bridge build/install, 78 adapter cases,
construction headless suite, catalog validation and all 19 CTest checks passed.
Follow-up `build/hatch-hover-main-20261022-215558` verified actual viewport hover
and click on isolated empty space at the selected elevation. The picker already
supports this; no alternate picking algorithm was needed. Recovery exposed a
panel-height defect: hiding the refusal retained184px. The placement panel now
resets to its new minimum size and recovers168px. Headless regression and live
hover/recovery/exact selection/natural completion (+750 frames) passed, with known
engine diagnostics only. Source stayed unchanged; recovered screenshot inspected.
The obsolete Lua adjacency helper is removed. Existing frame/spacing differences
and broader terrain/camera coverage remain open.

Construction terrain remains under migration. `area_refusals.json.native_terrain_probe`
records 1,512 dry, single-tile cases from protected capture
`build/construction-terrain-oracle-20261023-020029`: nine explicit subtypes,
21 tile types, two perimeter terrains and four below terrains. All native tile
results match the existing FloorTerrain/OpenTerrain/SinglePerimeter predicates
composed with the native mode4 below-stair and subtype replacement branches.
Natural stairs may accept walls/floors with support; constructed stairs only
pass the replacement branch for subtype5 (UpDownStair). The current Lua shape
rules do not yet reproduce this. This probe changed tile types, not actual
construction records; replacement jobs, liquids, area placement and multi-z
behavior still require verification before migration. Source remained unchanged,
the owned session closed, and simulation stayed paused at frame0.

The read-only diagnostic `df3d construction-terrain-read x y z subtype` now
accepts an explicit construction subtype (0..37). It composes the verified native
terrain helpers and replacement table with the mode4 below-stair classification.
It calls native water depth (`0x247d80`) and magma depth (`0x2c3a90`) in native
refusal order; each 0xbf-byte leaf routine is fingerprinted and reads only map
state. Neither routine has callees. No build-menu state is accessed.
`area_refusals.json.native_terrain_service` references compressed captures in
`construction_terrain.json.gz`: 2,646 dry cases and 9,072 terrain/liquid cases,
each compared with Construction selected, Bed selected and menus closed.
Installed captures `build/construction-terrain-service-20261023-020419` and
`build/construction-terrain-liquid-20261023-020740` matched every native tile
result (accepted states0..3 normalized to0); sampled request, redraw and
pathfinding state stayed unchanged. Both sessions remained at frame0, preserved
the source and closed. Construction preview/commit now calls this query through the existing Lua binding,
with the selected subtype and full rectangle. Unknown results fail closed.
Stairs uses recipe subtype UpDownStair for eligibility; endpoint job subtype
selection remains separate. Connected Track keeps its dedicated route pipeline.
The local construction shape and existing-tile replacement lists are removed.

The query also accepts `[x1 y1 width height]` as explicit selection bounds.
Native construction checks the whole selection perimeter, so using each tile's
neighbors incorrectly counts other tiles inside the selection as support.
`build/construction-terrain-area-20261023-021242` records 1,944 area cases
(2x2,3x3,1x3): all9,216 non-track tile decisions match the rectangle-aware
query. The18 apparent track differences were a harness error: native footprint helper
`0x3c1e60` excludes TrackNSEW/TrackRampNSEW from selection rectangles at
`0x3c1edf`. `build/construction-track-footprint-20261023-022547` confirms216
TrackNSEW destination-tile comparisons match while a sentinel outside[0][0]
remains untouched. Other rectangle entries were stale; they do not establish
track route or placement behavior. `build/construction-record-oracle-20261023-021321`
checks 387 actual construction records (two occupied/hidden records excluded)
across nine subtypes: all3,483 comparisons match, including constructed stairs
and a top-of-wall floor. Both captures are retained in `construction_terrain.json.gz`,
preserved the source, remained at frame0 and closed the owned session.
These are eligibility queries, not replacement-job effects. Multi-z placement,
remaining eligibility stages and track route issues remain open for full
construction acceptance. Live viewer `build/construction-native-refusal-main-20261023-021900`
passed25 semantic previews against native expected results across Wall, Floor,
Ramp, Fortification and ReinforcedWall, including liquid/removal refusal and
valid-site recovery. The removal screenshot was inspected. Source was preserved,
owned DF closed, and diagnostics were known engine issues only. Adapter94,
catalog, headless construction and CTest19 checks passed; headless diagnostics
contained only the known startup notice.
Live `build/construction-native-stairs-main-20261023-022024` exercised pointer
menu/map anchors across three elevations and exact items48520/48521/48522.
Initial jobs retained those IDs; DF naturally completed Up/UpDown/Down stairs
at +3,675 frames with no remaining jobs. Screenshot inspected, known engine
diagnostics only, source preserved and owned DF closed. This proves new-stair
completion through the migrated query; existing-construction replacement
completion remains separate.
Follow-up `build/construction-native-replacement-20261023-022359` naturally
completed a staircase (+1,775 frames), then replaced those completed records
through the UI using exact items48523/48524/48525. New jobs1493/1494/1495 finished
naturally after another1,250 frames with Up/UpDown/Down tiles and zero jobs.
The source was preserved, owned DF closed, screenshot inspected and diagnostics
were known engine issues only. The authoritative IDs are in the native job
observations; the viewer harness logged an old placed_sites key for its receipt.
This establishes matching-stair replacement, not every replacement family.
`build/construction-floor-wall-20261023-022824` additionally built a floor
naturally using exact item48520 (+1,225 frames), then replaced its existing
record with wall job1491 using item48521 (+300 frames). Semantic recipe
selection and pointer map/material selection were used. The final wall screenshot
was inspected; source preserved, owned DF closed, known engine diagnostics only.

The native highest-level guard (`a82061..a8208a`, subtype mask0x200000006a)
is now included before terrain/liquid checks. It returns sourced refusal18,
`Cannot build at highest level`, for Wall, ReinforcedWall, Ramp and the Stairs
recipe. Captures `build/construction-top-oracle-20261023-023000` and
`build/construction-top-service-20261023-023246` verify378 cases across the top
two levels and21 terrains. Live `build/construction-top-ui-20261023-023615`
passed25 native comparisons, including unaffected Floor/Fortification controls;
Wall screenshot inspected. A prior run023313 timed out because the harness sent
preview before the elevation-change event settled; waiting15process frames
resolved it. The failed run is excluded from acceptance. All source manifests
were preserved and owned sessions closed. Adapter94/catalog/headless/CTest19
passed; headless had only the known startup notice. Two unused Lua shape tables
were removed with this change. The five-tile surface edge restriction is now included for Wall,
Fortification and ReinforcedWall. Native designation reader `0x07dc40`
(0x86bytes, fingerprint396b58fb95c29f02) supplies the underground exemption;
the selected subtype and edge ordering follow `a81fbf..a8205b`. Exact native
copy is `Too close to edge`. `build/construction-priority-oracle-20261023-023915`
records7,776 combinations of position, level, terrain, underground/hidden flags,
occupancy bits and liquids. For this matrix, native refusal priority is hidden,
edge, height, terrain, liquid, occupancy. The occupied cases use bits, not actual
construction jobs, so they do not establish the existing-job exception.
`build/construction-edge-service-20261023-024343` matches all1,944 visible,
unoccupied cases. Live `build/construction-edge-ui-20261023-024422` matches25
native previews across five recipes, with Wall refusal screenshot inspected.
Source preserved, owned sessions closed, known engine diagnostics only.
Adapter94/catalog/headless/CTest19 passed. Construction occupancy priority is now native: fingerprinted map reader
`0x068010` (0x86bytes, hash388d6b4f5c5f658e) runs after liquid and before the
replacement dispatch. DF's construction-job exception is reproduced by scanning
all buildings and calling their native type query, matching Construction at
`centerx/centery/z` as in `a82460..a82497`. Hidden rejection precedes edge/height.
Lua now calls this stage before its occupancy guard. Native terrain checks may
accept a queued construction. Floor, Wall, Ramp and Fortification now reuse
queued stage-zero construction jobs after the native terrain check, preserving
the job and original input. New tiles alone contribute to the material quantity;
a selection containing only reused jobs needs no material picker. Reinforced-wall
conversion retains its separately verified rectangle behavior. Queued stairs
also reuse existing jobs, preserving connections from both the terrain and the
queued subtype. The piece is recalculated before creation after incremental
work. `stairs_placement.json.queued_replacement` records32 native pointer cases
(eight original subtypes, two endpoint terrains, both click directions), with
unchanged building/job/material IDs. Protected viewer
`build/construction-queued-stairs-main-20261023-031319` uses menu/map pointers
and PageUp to convert three queued down stairs to up/down, up/down, down.
All original jobs/materials survive and complete naturally in3,850 frames.
Screenshot inspected, known engine diagnostics only, source preserved and owned
session closed. Adapter99/catalog/CTest19 pass; regression covers a queued
connection changing between incremental scan and creation.
Track terrain validation has a separate diagnostic query, `track-terrain-read`,
which composes fingerprinted coordinate-only native checks without native menu
inputs. Routing uses modes0/1/4 of `a81f40`; unlike rectangle placement, mode1
has no perimeter requirement. Hidden endpoint/intermediate policy belongs to the
route caller. `track-terrain-oracle-read` is protected reference capture only,
requires paused native Track selection, and must never serve runtime adapters.
`track_terrain_query.json.gz` retains 3,024 liquid/hidden/occupancy/support cases,
5,576 cases covering all697 tile types, and387 actual construction records.
All acceptance results match native checks; Track/Bed selection agrees in the
first two matrices and closed-menu results agree for existing records. Sampled
UI/pathfinding fields remain unchanged by the independent query in the matrices.
The routing reader now injects this service and supplies an owned optional
`native_eligible` fact. The world model no longer infers site approval from
shape, liquid depth or occupancy classes. Missing native verification remains
unknown; hidden/intermediate and twig endpoint policy, movement facts and job
identity checks remain separate. Callback replay covers36 native terrain and96
queued-construction cases; adapter99 and core19 pass. Protected viewer
`build/construction-track-merge-main-20261023-040642` exercised menu/map placement
over four completed tracks with queued wall replacements. Original jobs and
materials survive, all four finish naturally after425 additional frames, and
the source save remains unchanged. Screenshot inspected; only classified engine
startup/shutdown diagnostics occurred. This does not resolve cold-route ordering
or the separate negative material-distance discrepancy.
The refreshed offline gate `build/qa/construction-native-eligibility-offline-20261023`
passes171 selected checks/builds;40 unselected GPU/live/bridge checks are not
covered by that result. A separate protected viewer run,
`build/construction-queued-track-ramp-main-20261023-041523`, extends four queued
TrackRampNS jobs over natural floors. The final pieces are ramp NSE/NSEW/NSEW/NSW,
retaining their original building/job/material identities and completing naturally
in575 frames. `connected_track.json.queued_ramp_conversion_live` retains the
fixture and readback. Screenshot inspected; source unchanged, owned session
closed, only classified engine diagnostics. This closes the queued-ramp conversion
case without implying cold-route or material-distance parity.
Queued track conversion is now covered by
`connected_track.json.queued_construction_conversion`:48 native pointer cases
across12 original subtypes, floor/ramp terrain and both click directions. Tracks
merge existing track connections; a ramp track is retained over flat ground,
whereas a queued ordinary ramp over flat ground becomes a flat track. All cases
retain job/material IDs. The engine-independent PendingConstruction plan can
represent a queued job with no track connections. The bridge retains the exact
native subtype in its owned snapshot identity and checks it before mutation.
When every tile reuses a job, Preview omits material filters and Place builds a
fresh validated plan without reading stock or needing a material snapshot.
Non-construction buildings with occupancy are blocked sites under the verified
native occupancy branch, including passable workshops. Their presence near a
route no longer turns that route into an unverified result.
Protected viewer `build/construction-queued-track-main-20261023-033959` converts
four queued walls through menu/map pointers, without a material picker, retaining
building1490..1493 and items48520..48523. All four tracks complete naturally in575
frames. Screenshot inspected; source unchanged, owned session closed, known
engine diagnostics only. Callback replay covers36 existing terrain and48 queued
conversion cases; adapter99 and CTest19 pass. The earlier three viewer attempts
failed on an unverified workshop below the route; diagnostic033738 identifies
the actual rejection. They are retained as failures, not completion evidence.
`connected_track.json.queued_construction_terrain_merge` adds48 native pointer
cases with actual construction records and varied completed floor/ramp track
terrain. DF merges connections from route, queued job and completed track;
requiring the queued job to already contain the terrain's connections was wrong.
That rejection is removed; expected terrain and exact job subtype remain part of
the snapshot identity. Callback replay now covers96 queued-conversion cases and36
existing terrain cases. Core/CTest19 pass in
`build/qa/construction-track-terrain-merge-20261023`.
Protected viewer `build/construction-track-merge-main-20261023-034718` first lets
four NS tracks complete naturally at frame725, then converts queued walls over
them through menu/map pointers. The reused jobs preserve their inputs and finish
as NSE/NSEW/NSEW/NSW after475 more frames. Screenshot inspected; source unchanged,
owned session closed, known engine diagnostics only. The native matrix uses a
controlled completed-record fixture; the viewer proves this flat crossing's
natural completion. Cold-route/negative-
distance ordering remain outside this proof.
`build/construction-queued-commit-20261023-025649` verifies20 ordinary native
conversions across five initial subtypes; five reinforced single-point selections
do not exercise its perimeter. Viewer `build/construction-queued-paint-20261023-030421`
changes the same job through Floor/Ramp/Fortification/Wall via map pointer clicks,
retaining building1490, job382794 and item48520. The final wall completes naturally
in1,225 frames. Screenshot inspected, source unchanged, owned session closed,
known engine diagnostics only. Adapter97/catalog/CTest19 pass; adapter coverage
also includes mixed new/reused material counts and stale liquid rejection.
`build/construction-occupancy-service-20261023-025144` matches all7,776 overlap
cases, including hidden/occupied cases. `build/construction-queued-service-20261023-025219`
adds243 matches with actual planned floors, walls and chairs over dry, wet and
constructed-stair terrain. `build/construction-occupancy-ui-20261023-025316`
passed25 native UI comparisons, including water taking priority over synthetic
occupancy and clear-site recovery. Screenshot inspected; known engine diagnostics
only, source preserved and owned sessions closed. Adapter95/catalog/CTest19 passed.




Full construction remains open; the current offline gate result is recorded below.

The hidden dependency in `buildreq::evaluate_buildability` is its tile validator
at RVA `0xa81f40`: it reads building type/subtype from global buildreq at
`0x1418a0468`/`0x1418a046c`, even when the outer request is independently owned.
Its Door branch at `0xa8257a` invokes the coordinate-only support routine.
The outer wrapper remains unsuitable: it accepted a missing-wall site with menus
closed (`build/native-door-main-20261022-194749/setup.log`) despite passing the
native-menu oracle (`build/native-door-oracle-20261022-193903`). Do not use native
UI state to work around this limitation for other building families.

`fixtures/construction/door_support.json` records the native support oracle:
valid and missing-wall sites produce identical answers with menus closed, Bed
selected and Door selected (`build/door-support-oracle-20261022-212606`). Native
request type/subtype/position and redraw counter stayed unchanged. The read-only diagnostic
is `df3d door-support-read x y z` (0 supported, 8 needs wall, -1 unknown); it is not
a complete site validator. Two sites in one fortress do not establish exhaustive
terrain coverage. Protected sessions preserve source manifests and never save.

Verification: bridge build/install, 77 adapter tests (including refusal after an
accepted preview), catalog validation and all 19 CTest checks passed. Protected
main-screen run `build/door-support-main-20261022-212434` exercised rejection,
exact material selection, placement and natural completion (+575 frames, selected
item 48520 retained). Captures were inspected. It is `passed_with_known_issues`
for the documented rendering-thread notice and shutdown diagnostics; no new
unclassified errors. Source manifest stayed unchanged and the owned session closed.
Earlier `build/door-support-main-20261022-212227` reached placement but timed out
at 5100 frames with an unfinished job. The later run does not erase that failure
or establish deterministic worker timing. Packaged builds remain unchanged.

## Native farm and road terrain validation

FarmPlot/RoadDirt/RoadPaved Preview and Place now call `extentTile` through
the native Lua binding. The diagnostic is `extent-tile-read family x y z`.
It returns the owned final tile result and the separate raw terrain result
needed for area SKIP handling. `site-support-read` retains the narrow raw query:
FarmPlot calls RVA14b1460 (soil/mud predicate14d2130); roads call14b0b00 with
an explicit dirt flag. Raw refusals precede general tile errors in the native
outer validator. Qualifying tiles use the native mode0 floor predicates,
underground-aware farm edge restriction, water247d80, magma2c3a90 and
occupancy68010, in that order. Roads are exempt from the farm edge restriction.
The native family dispatch routes all three to success after those checks.

The query fingerprints the outer validator, general validator and family dispatch
in addition to its called leaves. It never calls the menu-dependent whole
validator or borrows global buildreq. The shared surface routine14adea0 uses
movement=false/flags=0, bypassing lazy walkability rebuilding. Lua retains owned
mask aggregation and fresh commit checking, but its farm/road shape, liquid and
occupancy approximations are removed. Unknown native answers fail the request;
raw-invalid cells may be skipped while later eligibility errors refuse placement.

`extent_tile_native.json.gz` retains864 soil/edge/hidden/subterranean/liquid/
occupancy cases from protected `build/construction-extent-tile-20261023-054059`,
each matching DF with the requested menu, Bed selected and menus closed. The
native tile sweep `build/construction-extent-types-20261023-054230` adds4,182
matches across all697 tile types with and without mud. Its sampled UI/path state
is unchanged;36 full comparisons preserve all ten RNG buffers, indices and
current stream. These are metadata terrain cases, not constructed-building
replacement records. Both runs stay at frame0, preserve the source and close.

Main-viewer `build/construction-extent-tile-ui-20261023-054847` matches21 native
previews, including surface/underground edge sites, water-over-occupancy priority,
shallow water, magma and boulders. It checks warning text and cancellation and
allocates no buildings. Farm edge screenshot inspected, source unchanged,
frame0, owned session closed; only known engine diagnostics. RoadPaved boulders
398/399/400/441 supply the newly exposed native Need soil at location refusal;
FarmPlot supplies Too close to edge. Adapter111 replays all5,046 captured tile
results through Preview and checks unknown/missing raw facts fail closed.
Paved-road run `build/native-road-paved-main-20261023-054940` verifies actual
reverse-corner viewport placement, semantic exact material selection, and natural
completion at frame2425: road1490 uses exactly blocks1714/1716/1717, excludes its
invalid center, reaches stage3/3 and has no jobs left. Source unchanged and owned
session closed; only known engine diagnostics. Completed screenshot inspected;
this is effect verification, not acceptance of every menu/material pointer path.

`fixtures/construction/farm_road_terrain.json` retains30 protected comparisons
from `build/farm-road-terrain-oracle-20261022-232337`: matching request, menus
closed and Bed selected agree on soil, grass, stone, wall, open space, ramp, mud,
water2/7 and magma1. Request fields, redraw counter, reindex flag and pathfinder
generations stayed unchanged around each diagnostic. Source stayed unchanged;
frame remained0. This is terrain evidence, not full liquid/placement acceptance:
water2 soil returns terrain0 while the complete validator returns water error10.

The dirt-road geological path14e100 can call RNGeb68b0 when geology is missing.
The bridge preserves the active stream's2496-byte buffer and index around this
call, including a full buffer refill. Native stream push eb6c80 establishes ten
streams; invalid stream/index and fingerprint mismatches fail closed. The active
stream selector is read only. No menu or cursor state is borrowed.

Protected `build/farm-road-rng-oracle-20261022-233303` forces missing geology and
verifies16 cases: Shrub/ShrubDead/Sapling/SaplingDead, streams0/9, indices0/2496.
The diagnostic reports a native RNG advance before restoration; all ten streams'
624 words and indices, plus the active selector, compare equal afterwards.
The region entry and original RNG state are restored by the harness; source
manifest unchanged, paused frame0. Earlier233142 did not actually trigger the
fallback and is not restoration evidence. The temporary plant-tile diagnostic
guard is removed. Plugin build/install and native diagnostic checks pass. Product adoption
verification is recorded below.
Follow-up `build/farm-road-terrain-oracle-20261022-233410` passes42 cases across
the same three menu states, adding all four plant variants for each family.
Source unchanged; this validates the installed restoration path on ordinary
terrain alongside the deliberately forced fallback probe.

Product adoption passes82 adapter tests,19CTest, catalog evidence checks and the
Godot construction suite. Adapter coverage injects native decisions, replays
recorded masks, rechecks at Place, and aborts on unknown/missing native service.
Protected main-viewer runs confirm natural effects with source saves unchanged:
`build/native-farm-main-20261022-234000` completed FarmPlot at frame1825;
`build/native-road-dirt-main-20261022-234124` retired the dirt-road building at
frame675 and left the expected furrowed-soil cells. Both used actual pointer
navigation, invalid first corners and valid reverse corners; refusal images were
inspected. `build/native-road-paved-main-20261022-234338` completed at2525 with
exact selected blocks1717/1716/1714 retained and footprint `[1,1,1,1,0,1,1,1,1]`.
Paved-road menu/invalid anchor/material selection used semantic controller calls;
valid corners used the viewport pointer. Its completion image was inspected.
All runs have only documented engine diagnostics. Earlier paved run234230 has a
harness SCRIPT ERROR (nonexistent row.index) and is excluded despite its partial
result claiming passed; the corrected harness also requires all observations.
These are construction effects, not crop/road operation or every terrain case.

FarmPlot also exposes the native Closest material mode even though it needs no
material items. Native pointer capture `build/farm-material-mode-native-20261023-055944`
verifies Closest/After/Closest toggling, retention across reopening, and creation
of a partial farm with no material inputs. Its owned job is deconstructed without
saving. The viewer uses its existing local strategy and empty-filter placement
flow; no native menu state is read at runtime. Main-viewer
`build/farm-closest-main-20261023-060118` clicks the launcher, category, leaf and
mode buttons, rejects an unsuitable anchor, then places via reverse viewport
corners. Farm1490 completes naturally at frame700, stage3/3, with no items/jobs
and the dry center excluded. Closest remains selected. Placement screenshot
inspected; source unchanged, owned sessions closed, only known engine diagnostics.
`farm_road_terrain.json.native_farm_material_mode` retains the evidence. Headless
coverage checks toggle/reselect retention and that no material-list request is
made for this zero-input recipe.

Farm/road water refusals now display `Water at this location` after the native
terrain predicate accepts a tile and the separate liquid stage rejects it.
`liquid_refusals.json` retains96 native/bridge area comparisons:32 per family,
water/magma depths0..7 at a first corner or center. Protected runs are
`build/liquid-area-farm-20261022-234914`,
`build/liquid-area-road-dirt-20261022-235236`, and
`build/liquid-area-road-paved-20261022-235330`. All compare actual installed
planned buildings and masks at paused frame0, using native simulated clicks
versus headless semantic bridge requests. Source saves stayed unchanged; known
startup notice only. Water2..6 rejects the rectangle; water7/positive magma can
leave a usable footprint around a skipped center. Wet first corners reject.
This is planned-building equivalence, not natural completion or main-screen
pointer proof. The farm run predates the message-only change. Earlier farm234703
handoff failure and dirt235122 stale case-count failure remain excluded.
83 adapter cases,19CTest, catalog scope and Godot construction checks pass.
Main viewer `build/extent-water-main-20261022-235443` verifies all three families
show the water refusal and clear it for mixed dry/depth7 terrain, retaining mask
`[0,1,1,1]`. Inputs were semantic rectangles, not pointer gestures. No building or
frame mutation; source unchanged; known engine diagnostics only. RoadPaved refusal
image inspected. Other families' liquid-message mapping remains open.

The full offline gate predates this integration; general liquid-message mapping
and other construction requirements remain open.

## Construction placement refusal display

The placement panel displays sourced refusals in orange beneath Keep building.
`panels/construction_refusals.json` defines exact message/key scope, backed by
`fixtures/construction/placement_refusals.json`: Door wall support, Well/opening
support, and `Building present` for all93 catalog keys. The occupied-stone
catalog sweep returns soil refusals for FarmPlot and RoadDirt; later native
occupied-soil captures prove Building present for both families.
Loaded hidden tiles return `Hidden, cannot build at this location` for90 keys;
FarmPlot/RoadDirt/RoadPaved retain their verified hidden-terrain behavior. Missing
flags/occupancy or out-of-map coordinates stay separate hidden diagnostics.
Natural solid-wall targets return `Blocked at this location` for all93 keys,
matching the catalog oracle. Existing-construction replacement stays separate.
Farm/road extents aggregate native refusals in x-major order, deduplicating
messages and placing Disconnected first. Raw terrain refusals become skipped
cells when any terrain qualifies; water and occupancy errors on qualifying
terrain refuse the entire placement. Raw terrain checks precede occupancy. Native FarmPlot
`Need soil or mud at location` is FarmPlot-only; `Need soil at location` is
verified for RoadDirt and the RoadPaved boulder cases described above.
Transport/draft diagnostics stay hidden. New targets, cancellation, session changes
and detached late replies cannot retain an obsolete refusal. Generic liquid and
terrain messages still need native mapping; water/magma copy varies by family.

Protected oracle `build/refusal-catalog-native-20261022-222336` evaluated93 keys
across5 synthetic cases. This establishes copy scope, not full footprint/error
precedence parity. Native request state is used only in the disposable oracle.
Viewer `build/occupancy-hover-main-20261022-222851` verified actual occupied-tile
hover/click, valid-site recovery, exact hatch item48520 and natural completion300.
Screenshots inspected; source unchanged; known engine diagnostics only. Headless
construction and catalog evidence checks passed. The additional native Bed
capture222807 is black under its overlay and excluded; existing Door occupied
capture remains the visual reference for the shared refusal line.

Hidden-target viewer run `build/hidden-refusal-main-20261022-223355` verified
semantic hidden-target rejection, pointer recovery, exact hatch48520 and completion575.
The hidden target was supplied by the harness, not a visible surface hit. DF
re-paused at frame1; the disposable session was resumed once before completion.
Cause remains unestablished, so this does not prove uninterrupted completion.
Refusal/completion screenshots inspected; source unchanged; known diagnostics only.
Bridge build/install,79 adapter cases, catalog evidence test, construction headless
and19 CTest checks passed. Adapter coverage distinguishes missing map data and
rechecks visibility after an accepted preview.

`fixtures/construction/placement_refusals.json` records four native Door states
and the visible scope. Native capture `build/construction-refusal-native-20261022-213312`
and viewer `build/construction-refusal-main-20261022-213519` were inspected. The
viewer passed visible rejection, recovery, exact selection and natural completion
(+575 frames), with documented engine diagnostics only; source manifests remained
unchanged. The headless construction suite covers cancellation, pending-site
clearing and hidden unsourced failures. Existing square frame and tighter vertical
spacing differ from the native rounded panel (refusal baseline 12 pixels higher);
this is retained presentation work, not pixel-parity acceptance.

`fixtures/construction/liquid_refusals.json` records1488 native evaluations
(93keys, water/magma depths0..7) from protected run
`build/liquid-depth-native-20261022-224635`. On the flat test patch, water2..6
reports `Water at this location` for non-soil recipes; full-depth water and magma
use family-dependent blocked/liquid errors. This is reference evidence only;
the generic liquid diagnostic has not yet been replaced. Default dimensions and
flat terrain do not prove full footprint/error precedence parity. Changing only
the tiletype to SoilFloor in follow-up224821 still returned soil errors when dry,
so that run does not establish valid farm/road terrain. Source manifests remained
unchanged and all sessions ended without saving.
The corrected soil follow-up `build/liquid-valid-soil-native-20261022-231620`
uses asserted SoilFloor1 for FarmPlot/RoadDirt and verifies a dry baseline of
native tile result0 before testing depths. Water2..6 yields the water refusal;
water7 and positive magma yield blocked. RoadPaved on smooth stone agrees.
These48 evaluations establish tile refusals, not material-stage or completion
acceptance. The earlier SoilFloor run remains invalid soil evidence.
A separate natural-wall sweep `build/liquid-wall-native-20261022-231711` returned
blocked for all1488 recipe/depth combinations. The bridge therefore checks
natural solid walls before liquid, while keeping hidden/occupancy checks and
existing-construction policy separate. Both sources remained unchanged.
Viewer `build/liquid-wall-refusal-main-20261022-231905` confirms water2/wall
refusal for seven families and mixed recovery for four terrain families, using
semantic targets. No building/frame mutation; source unchanged; FarmPlot refusal
image inspected. Known engine diagnostics only.81 adapter tests,19CTest and
catalog check pass. Plugin rebuilt/installed; no completion or pointer claim.

Terrain area validation preserves the first refused tile's reason across budgeted
scans. A rectangle with no usable cells now rejects Preview/Place instead of
reporting valid with zero materials. Mixed masks remain usable; reinforced-wall
upgrades can still reuse existing jobs with a zero new-material count.
`fixtures/construction/area_refusals.json` records native tile refusals and their
limits. Main run `build/area-refusal-main-20261022-225644` verified hidden-area
refusal/recovery for Wall/Floor/Ramp/Fortification with semantic rectangle inputs;
mixed masks retain `[0,1,1,1]`. This is not pointer-gesture or natural-completion
acceptance. Native building count/frame stayed unchanged, source manifests were
preserved, representative refusal/recovery images inspected, and only known
engine diagnostics occurred.80 adapter tests and19 CTest checks pass. The prior
full offline gate predates this area fix; it is not a full gate for the newer code.

Solid-wall viewer run `build/wall-refusal-main-20261022-231147` verified semantic
2x2 rejection for the four terrain families plus FarmPlot/RoadDirt/RoadPaved, and
mixed-area recovery for the four terrain families. Representative images were
inspected. Building count/frame and source save stayed unchanged. This is not
pointer-gesture or construction-completion acceptance.81 adapter tests, catalog
evidence checks, construction headless and19 CTest checks passed; only documented
engine diagnostics occurred. The full offline gate predates this change.

## Native surface predicate investigation

`df3d site-support-read Surface x y z` exposes the coordinate surface predicate
RVA0x14adea0 with movement=false/flags=0. PE/function fingerprints fail closed;
this mode bypasses lazy walkability reindexing. It returns0 for accepted surface,
6 for rejected surface, and-1 for unknown. These are diagnostic surface results,
not complete building eligibility. Product construction has not adopted this
mode: ordinary furniture applies additional tile exclusions after the predicate.

Protected `build/native-surface-oracle-20261023-001655` covers60 terrain/liquid
combinations and180 calls with Bed selected, Well selected and menus closed.
Answers agree; request fields, redraw, reindex and pathfinder generations remained
unchanged around each call. Water7 and positive magma reject at this stage;
water2 passes surface but later returns native water error10. Dry ramps/stairs
pass surface but furniture rejects them. The retained liquid-refusal fixture
records this boundary so future integration does not mistake surface acceptance
for placement acceptance. This is bounded diagnostic evidence, not exhaustive
callees or terrain validation. Source preserved, paused frame0, owned DF closed.
Bridge build/install and19 CTest checks passed. No product placement rule changed.

`site-support-read FloorTerrain` adds the ordinary validator's exclusions to
Surface. The complete validator cannot be called safely because it reads global
buildreq. This diagnostic composes native surface14adea0, ramp256170 and existing
construction14abf60 predicates, plus fingerprinted stair dispatch data and small
branch glue from a82112. Fingerprints include classifier lookup tables and the
construction lookup a46d90. It stops before water, occupancy and family support;
the64 ordinary-floor recipes below use it before liquid and support checks. Unknown
versions fail closed.

Protected `build/native-floor-oracle-20261023-002026` compared96 terrain/liquid
cases against native Bed validation, with288 calls across Bed/Well/closed-menu
contexts. All matched the terrain stage (native water10 means terrain accepted).
Request/redraw/reindex/generations stayed unchanged around calls. Constructed
stairs return19, `Must remove construction`;14abf60 is an existing-construction
predicate, correcting the earlier tree-predicate hypothesis. Natural tree tiles
were also included. This bounded comparison does not prove every tile or every
family's choice of validation branch. Source preserved, frame0, owned DF closed;
bridge build/install and19 CTest checks passed. Evidence is retained with the
liquid-refusal fixture for subsequent production integration.

## Native furniture terrain integration

The diagnostic `df3d furniture-tile-read <family> x y z` composes the full
mode0 tile refusal sequence for Bed, Chair, Door, Statue, Cage, Weaponrack,
Table, Box, Cabinet, Coffin, Slab, TractionBench, Bookcase, DisplayFurniture,
OfferingPlace, Instrument, GrateWall, BarsVertical, WindowGlass and WindowGem.
It uses verified native terrain, designation, liquid, occupancy and support
helpers plus the fingerprinted family dispatch with an owned family value.
It does not read buildreq. Hidden precedes the underground-aware five-tile edge,
terrain, water, magma, occupancy and family support/indoor restriction.
The supported dispatch applies `Must be inside` to Bed, Chair, Table, Coffin and
TractionBench. The runtime delegates these twenty families before local occupancy checks and removes
the obsolete Bed-only indoor rule and separate Door support call.

`fixtures/construction/furniture_tile_native.json.gz` retains4320 native
mixed-condition cases from `build/construction-furniture-tile-20261023-061110`,
with matching, Well and closed menus (12960 service comparisons), and4182 cases
covering all697 tile types from `build/construction-furniture-types-20261023-061151`.
All acceptance/refusal results match. Native FINE_BLOCKED for Statue is normalized
to success; the diagnostic does not represent footprint presentation. The type
sweep preserves tracked UI/path state, with36 sampled guards over all ten random
buffers, indices and active stream. Both runs stayed paused at frame0, preserved
the source manifest and closed owned DF; captured command diagnostics were empty.
The plugin build/install passed. Preview and Place now call this service through
nativeSiteSupport and require a verified result; commit rechecks it before allocation.
Native visual `build/furniture-inside-native-20261023-061612` verifies the indoor
copy and placement for Bed/Chair. Viewer `build/furniture-tile-main-20261023-061653`
passed32 semantic preview/refusal/recovery observations, including water before
occupancy, with no allocations at frame0. Chair-outside screenshots were inspected
in both native and viewer captures. `build/furniture-floor-main-20261023-061757`
passed actual pointer navigation, invalid Door support, recovery, exact item48520
selection and natural Door1490 completion at frame350 (stage1/1, no jobs).
The completion screenshot was inspected. Source manifests stayed unchanged and
owned sessions closed; viewer diagnostics were the three known engine signatures
with no unclassified entries. Extension build, construction headless and112 adapter
cases passed; catalog passed on targeted recheck after its mock was updated to
return the required verification flag. No full offline rerun is claimed.
The Keep-building checkbox label is present. A pixel comparison of its exact
rectangle in the original capture and subsequent captures confirms identical
rendering; an earlier visual interpretation claiming a missing label was incorrect.
No font workaround is needed or retained.
`build/construction-keep-main-20261023-062701` additionally verifies the actual
Keep-building checkbox click, native Door refusal/recovery, exact item48520
placement, retained placement mode and natural completion at frame575. Escape
key events then release construction input. The checked-label screenshot was
inspected; source stayed unchanged, owned DF closed, and both viewer logs contain
only the three known engine diagnostics. An earlier keep-mode harness incorrectly
expected placement to close; it is excluded from acceptance. These checks do not prove natural
completion for all furniture families; remaining ordinary recipes still need full tile migration.

The fourteen-family extension is retained in the same compressed fixture:
`build/construction-furniture-extra-20261023-062951` passed10080 mixed-condition
cases in three menu contexts (30240 comparisons), and
`build/construction-furniture-extra-types-20261023-063039` passed9758 cases over
all697 tile types, with84 sampled all-stream random guards. Tracked UI/path state
was unchanged; all ran paused at frame0 and preserved source saves. Native visual
`build/furniture-extra-native-20261023-063507` confirms indoor copy for Table,
Coffin and TractionBench. Viewer `build/furniture-extra-main-20261023-063316`
passed87 refusal/recovery observations across the fourteen families without
allocation. Native and viewer Table-outside screenshots were inspected.
`build/furniture-table-main-20261023-063418` passed actual pointer menu/map/material
selection, outdoor refusal and valid-site recovery, then natural Table1490
completion at frame375 with exact item48520, stage1/1 and no jobs. Its completion
screenshot was inspected. All owned sessions closed, sources stayed unchanged,
and viewer diagnostics contained only the three known engine signatures.
The focused furniture-extra-runtime gate passed extension build, construction
headless, catalog and112 adapter tests (including28340 recorded native tile rows).
Natural completion for every furniture family and the final full gate remain open.

## Native ordinary building tile validation

The44 remaining explicitly admitted ordinary floor recipe keys now delegate
Preview and Place tile decisions through `<key>OrdinaryTile`; commit rechecks the
verified native result. `df3d ordinary-tile-read <key> x y z` exposes the same
query. It shares the native mode0 sequence with furniture, using an owned type
and exact recipe whitelist that excludes magma, machinery and opening variants.
The fingerprinted family dispatch adds TradeDepot's ten-tile edge restriction,
including underground sites, after terrain/liquid/occupancy checks. Local floor,
liquid and occupancy decisions for these recipes are bypassed. Native global
buildreq remains prohibited as a runtime input. Support, machinery, magma and
opening recipes still need their remaining full-tile ordering work.

`fixtures/construction/ordinary_tile_native.json.gz` retains1100 mixed-condition
placements (7900 footprint cells) from
`build/ordinary-tile-service-20261023-064039`, plus30668 placements over all697
tile types (220252 footprint cells) from
`build/ordinary-tile-types-20261023-064331`. Every cell's acceptance/refusal matches
native DF; FINE_BLOCKED is normalized to accepted. The first cell was additionally
queried with the selected recipe, Well and closed menus; tracked UI/path state
was unchanged around those queries. The sweep is uniform terrain per footprint;
it does not establish every mixed-footprint combination or whole-placement rule.
Both runs stayed at paused frame0, preserved source saves, closed owned DF and
had no captured command diagnostics. An earlier sweep exceeded the initial RPC
limit; it is excluded. The successful harness yields before starting and between
batches so the normal protected completion monitor owns the long run.

`build/ordinary-tile-main-20261023-065336` passed88 semantic edge/refusal/recovery
observations across all44 recipe keys without allocation. The custom Screw Press
refusal screenshot was inspected. The earlier065139 run had screenshot filename
errors and is excluded from clean acceptance. `build/ordinary-floor-main-20261023-065235`
passed actual pointer menu/profile/map/exact mechanism selection and natural
PressurePlate1490 completion at frame650, stage1/1, no jobs and exact item48520.
Native readback verified water3 and one-use settings. The completion screenshot
was inspected. Sources stayed unchanged, owned sessions closed and both viewer
logs contain only the three known engine diagnostics. Extension build, construction
headless and catalog passed;113 adapter cases passed on targeted recheck after
test requests supplied their required footprints/profiles. No full offline gate
or natural completion of every recipe is claimed.

Pressure Plate preview and commit now reject profiles without a trigger using
DF's fingerprinted inline TEST mask at RVA `0x3c0eac`. The containing validator
and instruction block are checked before applying that mask to caller-owned
flags. This is an extracted native predicate, not a callable native function:
the original instruction reads global build-menu state and cannot be invoked
by the runtime. Citizens/reset flags alone do not qualify. Unknown fingerprints
fail closed. `df3d pressure-trigger-read <flags>` exposes the diagnostic.
`pressure_plate.json.native_trigger` records192 native combinations (all64 flag
sets on dry, water and hidden-water terrain),576 independent service comparisons
with matching/other/closed menus, and unchanged global flags. Preview preserves
native intent-before-tile message order and commit rechecks before job creation.
Protected viewer `build/pressure-trigger-main-20261023-070708` passed actual pointer
no-trigger refusal, water-trigger recovery and exact mechanism48520 selection.
DF readback verified water depth3 and one-use settings; building1490 completed
naturally at frame650, stage1/1 with no jobs. Keep-building remains open and resets
options, matching the recorded native lifecycle. Refusal/completion screenshots
were inspected. Source remained unchanged and owned DF closed; both viewer logs
contain only the three known engine diagnostics. Focused extension, construction
headless, catalog and114 adapter tests passed in `build/qa/pressure-trigger-runtime`.
Actual activation/link effects and broader construction acceptance remain open.

## Opening and support tile migration

`df3d opening-tile-read <family> x y z` exposes the query for Support, Well,
Hatch, GrateFloor, BarsFloor and AnimalTrap. It composes the fingerprinted native
terrain/liquid/occupancy leaves and family dispatch using owned coordinates and
family identity. Support uses mode0 terrain; the other five use mode1 terrain.
Hidden and underground-aware edge checks precede terrain, liquids and occupancy;
Well/Hatch-family support follows. No native menu state supplies runtime inputs.
`fixtures/construction/opening_tile_native.json.gz` retains150 baseline cases,
4,320 priority cases and4,182 cases covering all697 tile types for all six families.
Priority/type captures compare the independent query with matching, other and
closed native menus; every tile result matches (native accepted code1 normalizes
to0). Sampled UI/path state stays unchanged. All three protected sources remained
unchanged, sessions closed and simulation stayed at frame0. Preview and commit now use the same query through `<family>OpeningTile`, with
unknown results failing closed. Their former Lua terrain/liquid/occupancy/support
branches are removed. AnimalTrap's native perimeter query runs after accepted
tiles and again at commit; its refusal preserves the valid tile mask. The binding
already supplied `Needs walkable perimeter` before this migration; the earlier
claim that it displayed a blocked-tile refusal confused its numeric diagnostic
with its Lua result. Legacy Kennels retains its separate floor fallback.
Protected viewer `build/opening-runtime-main-20261023-071833` passed30 semantic
refusal/recovery checks across all six families, including edge, water/occupancy,
magma and valid-site recovery. No buildings were allocated and simulation stayed
at frame0. The Hatch edge screenshot was inspected. Source remained unchanged
and owned DF closed; both viewer logs contain only the three known engine
signatures. Focused extension, construction headless, catalog and115 adapter tests
passed in `build/qa/opening-tile-runtime-final`. A subsequent targeted test verifies
AnimalTrap's accepted tile mask survives perimeter refusal and commit rechecks
that perimeter before creating a job (116 adapter tests now).
`build/opening-hatch-main-20261023-071920` passed actual pointer menu, invalid
hover/click, valid hover recovery, exact item48520 selection and natural Hatch1490
completion at frame575, stage1/1 with no jobs. Completion screenshot inspected;
source preserved, owned session closed and only the same known diagnostics.
Natural completion of every family and broader construction acceptance remain open.

## Machinery and magma full-tile validation

`df3d special-tile-read <key> x y z <open_mode>` validates the tile for the eight
machine recipes (including Windmill and Millstone) and four magma recipes.
Mode0 uses native FloorTerrain and mode1 uses OpenTerrain; the caller supplies
an independently computed native machine-connection result or magma off-center
position. It then applies native edge, liquid, occupancy and family dispatch
rules through the shared fingerprinted helper. It does not borrow build-menu state.
Preview and commit use `<key>SpecialTile` with an explicitly typed boolean mode.
Unknown results fail closed. The former Lua terrain/liquid/occupancy checks for
these twelve recipes are removed; native hookup calculation and warning
aggregation remain separate.
Whole-placement hookup warnings, footprint behavior and job effects are separate.
`fixtures/construction/special_tile_native.json.gz` records5,184 ground cases,
2,592 planned-gear hookup cases (2,286 actually connected),648 magma cases and
300 edge/priority cases. Ground checks the first tile; connected/magma compare
whole native footprints against representative queries on uniform terrain;
the edge sweep independently queries every footprint cell. Both native terrain
modes are checked with matching/other/closed menus in the first three captures,
and the selected first-cell mode in the edge sweep. Sampled UI/path state stays
unchanged. All four protected sources remained unchanged, sessions closed and
simulation stayed at frame0. These comparisons establish tile-query behavior,
not exhaustive tile types, rendered parity or natural construction effects.

Protected viewer `build/special-runtime-main-20261023-072959` passed84 semantic
comparisons against freshly captured native errors across all twelve recipes,
including edge, combined liquid/occupancy, mixed support and valid-site recovery.
No buildings were allocated after setup and simulation stayed at frame0. The
Windmill edge/connection refusal screenshot was inspected. Source remained
unchanged and owned DF closed; both viewer logs contain only the three known
engine diagnostics. Extension, construction headless and catalog checks passed.
The new adapter replay initially used incorrect mock footprint sizes; after
supplying the captured sizes, its300 per-cell cases, unknown result and commit
recheck passed. The other116 adapter tests passed in the original focused run.
`build/special-hookup-main-20261023-073107` passed actual menu/map/material pointer
input over open space with a planned corner gear. Windmill1491 completed naturally
at frame825, stage1/1, no jobs, retaining exact logs48520..48523. The completion
screenshot was inspected; source preserved, owned DF closed, known diagnostics only.

`build/special-magma-main-20261023-073220` passed pointer menu/map/material input
and natural MagmaForge1490 completion at frame1450, stage3/3 with no jobs,
retaining selected block1714 and iron anvil48524. Completion screenshot inspected;
source preserved, owned DF closed and only the same known diagnostics. These
runs establish construction effects for these two recipes, not power generation,
reaction execution or natural completion of every machine/magma recipe.

## Bridge full-tile validation

`df3d bridge-tile-read x y z <anchor>` composes the verified native Bridge tile
check with caller-owned raising-edge membership. Bridge skips the general
five-tile edge restriction. Mode1 terrain, water, magma and occupancy are checked
before an anchor's mode0 result; anchor failure maps to native code5. Unknown
helper results fail closed. This diagnostic does not read native menu inputs.
`fixtures/construction/bridge_tile_native.json.gz` records960 priority placements
(5,520 individually queried cells) across all five orientations, four rectangle
sizes, eight uniform/mixed terrain patterns and six designation/liquid/occupancy
profiles. A further3,485 placements cover all697 tile types on3x3 bridges across
all orientations (31,365 cells). Every result matches; first-cell queries also
match with Bridge selected, Well selected and menus closed. Sampled UI/path state
stays unchanged. Both protected runs preserved their source, stayed at frame0
and closed the owned session. Preview and commit now call the same query through
`BridgeTile` with an explicitly typed, caller-owned anchor boolean. Unknown
results fail closed. The former Lua bridge terrain/liquid/occupancy and anchor
checks are removed.
The mixed cases expose a separate aggregation gap: DF may prepend
`Needs walkable perimeter` before earlier `Needs to be anchored on edge` tile
refusals when the final footprint tile is accepted. Ten priority cases show this;
preview now checks that condition and preserves the native message order.
Native `3c1618` gates the perimeter on the last coordinate in the accepted branch.
All118 adapter tests pass in `build/qa/bridge-tile-adapter-final`, including all
4,445 captured placements, native anchor membership, compound ordering, unknown
results and commit revalidation. Initial replay scaffolding wrongly excluded
boulders/pebbles from anchor floor mocks; that was corrected to existing native
evidence. Extension, construction headless and catalog checks passed separately.
Protected viewer `build/bridge-runtime-main-20261023-074032` matched30 freshly
captured native previews across all five orientations, including mixed terrain,
edge exemption and compound perimeter/anchor refusal. No new buildings after
setup, frame0, source preserved and owned DF closed. The compound screenshot
was inspected. Both viewer logs contain only the three known engine signatures.

`build/bridge-full-main-20261023-074136` passed actual pointer menu/orientation,
rectangle corners, group/individual material selection and natural Bridge1490
completion at frame8475, stage3/3 with no jobs. Exact materials48520..48522 were
retained. Completion screenshot inspected; source preserved, owned DF closed
and only the same known engine diagnostics. Lever linking and bridge activation
are separate from this construction proof.

## Bridge native perimeter

Bridge preview and placement use DF's coordinate-only rectangle predicate at
RVA `0xaa93e0`, replacing the Lua perimeter terrain/liquid/occupancy approximation.
`BridgePerimeter` accepts explicit width/height (1..31), checks map bounds and
fingerprints the routine and its surface dependency. It borrows no native menu
state. Unknown answers fail closed without presenting a fabricated refusal.
`df3d site-support-read BridgePerimeter x y z width height` exposes the same stage;
Animal Trap retains its single-tile use. Bridge anchor/footprint validation uses
the separate native terrain composition below.

`bridge_placement.json.native_perimeter_service` retains720 comparisons from
protected `build/bridge-perimeter-oracle-20261023-005936`: six dimensions, cardinal
edges/corner-only/empty perimeter, five terrains and four liquids. All match the
native Bridge validator with Bridge selected, Well selected and menus closed.
Sampled request/redraw/pathfinding state stayed unchanged, paused frame0; source
manifest was preserved. Adapter tests inject recorded native perimeter answers;
they no longer certify a duplicated Lua perimeter algorithm.

Installed bridge build,89 adapter tests, catalog, construction headless and19
CTest checks pass. Protected viewer `build/bridge-perimeter-main-20261023-010129`
passed pointer menu/orientation/corners, group and individual material selection,
and natural bridge completion at7975 frames with exact items48520/48521/48522.
Completion screenshot inspected; source unchanged and owned session closed.
Diagnostics contain only the documented engine startup/shutdown issues. Earlier
010027 stopped on an obsolete harness hidden-footer assertion, superseded by
existing native placement-hover evidence; it remains recorded as a failed run.

## Bridge footprint and anchor terrain

Bridge uses OpenTerrain before liquid validation and FloorTerrain on the hinged
edge after liquid validation. This follows evaluate_buildability's explicit
orientation branches at3c1586..3c15ea, using native coordinate predicates without
borrowing global buildreq. Retracting bridges have no hinged edge. Unknown
native results abort; known rejected anchor terrain maps to native `Needs to be
anchored on edge`. The Lua bridge shape/floor lists are removed. Verified bridge
water, magma, existing-construction, anchor and perimeter refusals are displayed.
Machinery still has its separate unfinished terrain checks.

`bridge_placement.json.native_terrain_service` retains540 uniform3x3 cases from
`build/bridge-terrain-oracle-20261023-010714`: five directions,18 terrain types,
six liquid variants, all nine tile results matching the composition. OpenTerrain
answers agree with Bridge selected, Well selected and menus closed; sampled UI
and pathfinding state stayed unchanged. Source preserved, paused frame0. This is
terrain/anchor evidence, not every occupancy or mixed-footprint case. Earlier
010521 passed the wrong orientation argument;010607 failed to invalidate native
last-position caching. Both failed harness runs are excluded from acceptance.

Product verification passes90 adapter tests, catalog, construction headless and19
CTest checks; plugin installed. Viewer `build/bridge-terrain-main-20261023-010940`
passes five semantic refusal previews and dry recovery. Anchor screenshot inspected.
`build/bridge-perimeter-main-20261023-011037` verifies pointer placement, exact
material selection and natural bridge completion with the terrain migration.
Both preserve source manifests and close owned sessions; diagnostics are limited
to the known engine startup/shutdown issues. Completion screenshot inspected.

## Native windmill machinery hookups

Windmill support calls the native `building_handler::get_machine_hookup_list`
(RVA5ab260) with explicit type, bounds, elevation and direction and an owned
`machine_tile_set`. It then follows evaluate_buildability's reverse scan of
`world.buildings.all`, calling native `canConnectToMachine` for each building.
The vector lifetime is bounded by `with_finalize`; no buildreq/menu state is used.
The hookup generator writes its output vectors and calls vector append helpers,
without reading gameplay UI globals. These are DF virtual methods exposed by
DFHack, rather than reimplementations in a DFHack helper.

The old five-entry Lua list and `findAtTile` candidate shortlist are removed.
Native DF returns nine windmill hookup entries, including corner masks that the
old list missed. `windmill.json.native_hookup_service` retains14 protected cases
from `build/machine-hookup-oracle-20261023-011516`: each lateral corner gear is
accepted, while a purely diagonal gear is rejected. Existing planned/completed,
above/below/side, axle and non-machine cases remain covered. Windmill selected,
Bed selected and closed menus agree; sampled request/redraw/pathfinding state
stays unchanged, paused frame0, source manifest preserved. The earlier011412 run
covers the initial nine cases. These support fixtures deliberately prepare terrain
and support buildings; they are not evidence of natural construction completion.
Windmill terrain/liquid validation follows the native composition below.

Installed bridge,90 adapter tests, catalog, construction headless and19 CTest
checks pass. Protected viewer `build/machine-hookup-main-20261023-011808` placed a
windmill over a prepared open center using a planned lateral corner gear. Pointer
menu/material controls and a semantic empty-center target led to natural completion
at825 frames, retaining exact logs48520..48523. No completion stage was forced.
Completion screenshot inspected; source preserved and owned session closed.
Diagnostics contain only the documented engine startup/shutdown issues. This
verifies construction admission/effect, not downstream machine operation.

## Native farm and road connectivity

`area-connectivity-read` calls native3c2640 with an allocated, owned buildreq and
explicit rectangle. Only FarmPlot/RoadDirt/RoadPaved are accepted; their3c1e60
footprint branches read owned corners. Both functions are fingerprinted. Native
farm/road terrain leaves supply eligibility; the helper uses a local31x31 visited
grid. Its shared two-frontier coordinate buffer and random state are restored.
The961-cell bound is below the120000-entry frontier capacity. No global buildreq,
cursor or viewscreen is read or changed by this query.

`farm_road_terrain.json.native_area_connectivity` retains protected043640:
24 farm/road cases agree across selected, Bed and closed menus. Sampled UI/path
fields remain unchanged; an explicit guard compares every frontier byte and all
ten RNG buffers/indices plus selected stream before/after. All match. The same
capture records56 native area error/warning sets. The raw helper returns true for
empty qualifying terrain as well as disconnected regions; native outer3c0d62
suppresses the Disconnected message unless some raw terrain qualifies. Liquid
and occupancy restrictions are later stages and must not replace that precondition.
The wrapper now includes native3c0d62's precondition: visit every tile through
Road then Farm predicates, select acceptance by the requested family, and call
connectivity only if some raw terrain qualifies. The entire sequence preserves
RNG state. Thus empty terrain reports its own refusal rather than Disconnected.
Normal farm/road Preview and Place use this query; Place repeats it immediately
before creation, so a changed connectivity result cannot create a stale building.
Unknown results refuse without fabricated copy.

Protected044617 verifies24 cases in three menu states, matching the exact native
Disconnected decision, with eight full frontier/RNG byte comparisons. Native
pointer run044111 verifies all three families reject separated regions, accept
connected partial footprints, and refuse all-wall areas. Farm/dirt-road partial
clicks create buildings; paved road reaches materials. Those oracle-created jobs
are cleaned up without saving; no natural-completion claim follows. Main-viewer
044652 matches six separated/partial previews and displays the native refusal.
Screenshot inspected, no construction allocated, paused frame0 and source unchanged;
only classified engine diagnostics. Adapter102 includes a connectivity change
between initial checking and creation. Mixed farm/road error
aggregation is covered below; construction-paint rectangles are described below. Earlier044042 stopped at an incorrect native menu
path and is not acceptance. All owned sessions closed.

The diagnostic `farm-warning-read FarmPlot x y z width height mask` accepts an
owned x-major/y-minor eligibility mask (ASCII0/1). It returns1 for the native
warning pair,0 when suppressed, and-1 when unknown. It calls the fingerprinted
soil/mud and designation readers and accumulates only accepted underground tiles,
matching3c1789..3c188a. It never reads native build-menu state. Eligibility remains
a separate input; this does not establish an independent farm placement validator.
Protected `build/construction-farm-warning-20261023-050021` matches16 native
rectangles across selected/Bed/closed menus (48 queries), including liquids,
occupancy, soil walls and mixed surface/underground plots. All16 full frontier/RNG
byte guards and sampled UI/path fields remained unchanged. Source preserved,
frame0, owned session closed, no unclassified diagnostics. Captures and copy are
retained in `farm_road_terrain.json.native_farm_warning`. Earlier045720 exposed
that soil alone is insufficient when all soil tiles have placement errors; that
failed probe is not acceptance.

Farm Preview/Place now passes the completed owned eligibility mask into that
query, transposing the Lua y-major mask into native x-major order. Known deep-water
refusals finish scanning to collect warnings while still prohibiting creation;
unknown native results fail immediately. Management54 carries bounded native
warning text separately from validity and refusal messages. Missing old-recording
warnings remain unavailable. The viewer exposes only the captured farm warning
pair and clears it on draft/site/session changes. Native visual capture
`build/farm-warning-native-20261023-050506` places yellow warnings below orange
refusals; the supported palette's yellow is255,225,17. Screenshot inspected.
Main-viewer `build/construction-farm-warning-ui-20261023-051450` matches six
native semantic previews: surface soil, underground soil, stone, water, occupied
soil and disconnected ground. It verifies cancellation clearing; no buildings
were allocated. Source unchanged, paused frame0, owned sessions closed; only
classified engine diagnostics. Water screenshot inspected. Adapter105 covers
mask transposition, incomplete scans, unknown warning results, accepted/refused
previews and deep-water refusal without jobs. Earlier051051 exposed early water
return;051255 exposed the missing FarmPlot Building present display entry. Those
failed viewer runs are not acceptance. The final proof and copy are retained in
`farm_road_terrain.json.native_farm_warning.runtime`.

Farm/road mixed-area refusal behavior is recorded in
`farm_road_terrain.json.native_mixed_area_click`. Protected native pointer run
`build/construction-area-mixed-click-20261023-052515` covers27 family/terrain
combinations. Mixed water and occupancy start from a valid opposite corner;
those rectangles refuse entirely. Raw-invalid ground can be skipped; native
farm/dirt-road jobs are created and cleaned up without saving, while paved roads
reach materials. The earlier052357 mixed cases never established a valid anchor
and do not establish rectangle behavior. Lua preserves the native terrain
predicate result separately from the final placement mask, uses it for native
SKIP handling, and collects all remaining errors after native connectivity.
Commit rechecks also reject a formerly skipped cell that becomes occupied
qualifying terrain, even when its final mask bit remains zero.

Main-viewer `build/construction-area-aggregation-ui-20261023-053024` matches15
native previews including Disconnected/Water, Water/Building present, and
Disconnected/Water/Building present. It checks warning text and cancellation,
allocates no buildings and stays at frame0. Paved-road screenshot inspected.
`build/native-farm-main-20261023-053146` exercises actual viewport clicks through
invalid-anchor rejection and reverse-corner placement, then naturally completes
farm1490 at frame700 with the dry center excluded and zero remaining jobs.
Completed screenshot inspected. Both sources unchanged, owned sessions closed,
and only known engine diagnostics. Adapter109 includes incremental aggregation,
partial-occupancy rejection, raw terrain precedence and stale skipped-cell changes.
This verifies those cases, not every same-tile error priority or map-edge rule;
non-Construction general tile validation remains under migration.

## Construction native route coverage

The placement adapter has no generic local terrain/liquid/occupancy fallback.
A recipe without a verified native route refuses placement with no invented
visible explanation. Existing family-specific native checks remain authoritative;
this does not certify material selection, visuals or all construction effects.
`fixtures/construction/catalog_native_routes.json.gz` records the supported-build
catalog from protected `build/construction-catalog-routes-20261023-085903`:
96 entries,93 supported, every supported key covered by an existing native route,
and every viewer menu key present. This inventory uses callback placeholders only
to represent installed service availability; native predicate evidence lives in
the family fixtures. Source preserved, frame0, owned session closed.

An earlier audit incorrectly treated standalone Kennels as a legacy runtime
family. It existed only in synthetic tests: supported building_type7 is Shop,
which the catalog excludes, and actual Kennels is Workshop:Kennels. Tests now
use the captured SCREW_PRESS/SOAP_MAKER custom keys for successful raw-ID
resolution and separately require unknown custom recipes/families to fail closed.
The obsolete local floor-shape table and terrain/liquid/occupancy branch are
removed. All122 adapter cases, the catalog check and construction headless suite
pass after removal; this inventory establishes route coverage, not full release
acceptance. Installed cleanup live check
`build/construction-paint-runtime-main-20261023-083106` matches35 native previews,
including compound refusals and recovery; no allocations, frame0, source preserved,
owned session closed. Floor compound screenshot inspected; only the documented
engine diagnostics occurred.

The legacy UpStair/DownStair/UpDownStair catalog entries are removed: the native
menu exposes the Stairs workflow, which still creates those three actual building
subtypes. Inspection and removal derive subtype identity from the building rather
than the build catalog; a regression verifies all three remain available there.
All current supported recipes with material inputs use explicit furniture/native
footprint ordering or the dedicated Track path. Unknown recipes cannot publish
an invented ordering. The squared geometric metric and local merge-sort fallback
are removed. Furniture route selection uses the verified family key rather than
inferring a recipe from its input item's enum. This is routing coverage, not
acceptance of every material eligibility/grouping detail or Track's retained issues.

`build/qa/construction-material-cleanup` passes the extension build, construction
headless suite, catalog check and all123 adapter tests. Synthetic tests now supply
owned navigation results and exercise native-list payload limits; none relies on
the deleted geometric ordering. The installed bridge passes protected
`build/construction-stairs-recovery-main-20261023-085929`: invalid middle-level
water refusal with no allocation, recovery, exact individual48520/48521/48522
selection, and natural completion of all three stair subtypes at frame3675 with
zero jobs. Source unchanged, owned session closed, material/completed screenshots
inspected. Both viewer streams contain only the three documented engine diagnostics;
status is passed_with_known_issues. This is focused cleanup verification, not the
full release gate or completion of the construction goal.

Queued stair replacement now has native evidence for mixed old/new columns in
`construction_paint_area.json.gz.queued_stairs`. Protected
`build/construction-stairs-queued-native-20261023-090843` covers90 combinations:
five queued subtypes, each of three elevations, both endpoint directions, and
manual cancel/manual commit/Closest. Cancellation retains the original building,
job, subtype and bound item; both commit modes retain its job/item identity and
create exactly two additional jobs with the recorded endpoint connections.
The adapter regression replays all90 subtype/reuse outcomes successfully. This
checks replacement and cancellation, not automatic material-order equivalence or
natural completion of the mixed column. Source unchanged, frame0, owned session
closed. Failed probe attempts used the full material label after native truncation;
they are excluded. The final probe uses its stable visible prefix for both clicks.

Protected viewer `build/construction-stairs-queued-main-20261023-091411`
completes the mixed queued/new stair workflow. The exposed launcher, map endpoints,
PageUp/PageDown and two individual material picks use input events; cancellation
and recipe reselection use controller calls. The picker requires exactly two new
inputs. Cancellation preserves Wall1490/job382794/item48520 without allocation;
retry retains that job/item, converts it to UpStair and adds two jobs using clicked
items48521/48522. Ordinary DF simulation completes Up/UpDown/Down stairs at
frame1675 with no remaining jobs. Source unchanged, owned session closed. Picker
and completed screenshots inspected; both viewer streams contain only documented
engine diagnostics (passed_with_known_issues). Earlier091219 omitted reopening
the panel after cancellation, timed out, and is excluded from acceptance.

`single_level_stairs` retains ten native checks across five floor/stair terrains
and widths1/3 from `build/construction-stairs-single-native-20261023-090259`.
All display `Must span multiple elevations` on hover and create no jobs after
same-level endpoint selection. The existing restriction needs no product change.
Source unchanged, frame0, owned session closed.

## Construction paint rectangle refusals

Construction Preview and Place reject a rectangle containing a known tile refusal;
accepted tiles do not turn a mixed blocked, hidden, flooded or occupied selection
into partial paint. They collect native tile results in x-major/y-minor order per
elevation and deduplicate sourced messages. Queued construction replacements
retain their separate reuse path. Unknown tile results abort immediately.
Before each creation batch, the bridge rechecks the remaining rectangle; a newly
invalid tile stops further work without silently skipping it. Earlier completed
batches remain completed, and the response reports that partial outcome.

`fixtures/construction/construction_paint_area.json.gz` records392 native evaluated
rectangles across eight construction subtypes and49 terrain pairs in protected
`build/construction-paint-mixed-native-20261023-074847`. Native pointer run
`build/construction-paint-mixed-click-20261023-074943` confirms20 selections across
Wall/Floor/Ramp/Fortification: four valid rectangles advance to materials and16
mixed invalid rectangles remain in placement with no buildings created. The valid
fixtures lack accessible stock; they establish material-stage entry, not completion.
Both native runs stayed paused at frame0, preserved the source and closed.

Viewer `build/construction-paint-runtime-main-20261023-075245` matches35 semantic
previews across Wall/Floor/Ramp/Fortification/ReinforcedWall, including compound
error ordering and dry-site recovery. The compound Floor screenshot was inspected.
No construction IDs were allocated, the source stayed unchanged and the owned
session closed. Diagnostics were the three documented engine signatures only.
All119 adapter tests, the construction headless suite and catalog check pass.
Coverage includes incremental scanning,392 recorded native expectations,
Place rejection before allocation, and stopping after a site changes between batches.
The previous partial-paint test expectations were incorrect and have been removed.
Protected `build/construction-stairs-mixed-native-20261023-075818` adds36 native
pointer cases over three elevations, with invalid initial anchors distinguished
from completed selections. Second-click validation rejects bad intermediate
levels, even when endpoint hover has no error. Six four-level comparisons in
`build/construction-stairs-compound-native-20261023-080145` establish forward
z-major error collection and per-level x-major ordering. The adapter replays
forward valid-anchor cases and compound refusals without allocation.
Protected `build/construction-stairs-refusal-events-20261023-091706` resolves the
reverse validation-order question with snapshots immediately after input and after
rendering. All six compound cases return identical ordered full-volume errors for
both endpoint directions immediately after the click. Validation leaves cached
request.pos.z at the upper level168. Forward rendering keeps that position and
error list; reverse rendering changes it to hovered level165 and replaces the
errors with only that level's results, sometimes empty. This supports endpoint
revalidation on redraw rather than different volume eligibility. The adapter
regression now checks both directions against native click-time results for
Preview and Place with no allocations. `stairs_refusal_events` retains the capture;
source unchanged, frame0, owned session closed. These are instrumented snapshots
with explicit viewscreen rendering, not proof of normally rendered refusal text.
The fixture retains failed hidden-capture probes rather than treating their missing
panels as fidelity evidence. Subsequent `parent_render_capture` uses a diagnostic
DFHack Screen's `onRender`/`renderParent` callback and preserves the native pointer,
matching the established Door capture method. Runs
`build/stairs-refusal-visual-20261023-141352` and `141547` recover the actual initial
placement panel and reverse water refusal. The native heading is
`Click a tile to place the Stairs.` with ` (spans 4 levels)` on the next line.
DF3D now uses that wording and updates the span from the local selection; cancelling
clears it. `build/qa/stair-heading` passes the headless construction regression.
Viewer `build/stairs-refusal-viewer-main-20261023-142233` verifies the heading and
all six forward/reverse full-volume refusals via controller selection intents.
No building IDs were allocated; frame0/source save remained unchanged, owned DF
closed, and both streams had only documented Godot signatures. The reverse
three-level-invalid screenshot was inspected. That run used controller intents.
Protected `build/stairs-refusal-pointer-main-20261023-152228` additionally verifies
all six cases through the public Build/category/Stairs controls, exact viewport
map clicks and three PageUp/PageDown elevation changes. The first corner survives
each elevation change; the full-span refusal appears on hover and after the ending
click, with the four-level heading. Escape releases modal input between cases.
No building IDs are allocated, frame0/source remain unchanged, and owned DF closes.
Both streams contain only documented Godot signatures. Reverse compound preview
and rejection screenshots were inspected. `stairs_refusal_events.viewer_pointer`
records this rejection/input coverage; successful construction is separate evidence.
A persistent diagnostic overlay and normal `onRender`/`renderParent` callbacks
recover visible post-click panels in `build/stairs-refusal-middle_pair-20261023-145856`
and `build/stairs-refusal-three_levels-20261023-145934`. Both assert first corner
and endpoint before capture. Four forward/reverse cases confirm identical
full-volume click validation, but reverse redraw replaces errors with only the
hovered level's errors (sometimes none); moving away and back also clears
intermediate errors in the forward direction. Thus absent panels in older
captures are not evidence that placement exits. All four cases allocate no
buildings, remain paused at frame0, preserve the source and close owned DF.
`persistent_render_capture` retains data and limitations. DF3D currently keeps
full-volume errors during preview and rejection; the maintainer approved retaining that
full-span error display on2026-10-23. This display-only exception leaves validation
and native refusal wording unchanged. Runtime never borrows
native request cache/menu state; placement validation remains unchanged.
Mixed queued/new selection is recorded in
`construction_paint_area.json.gz.queued_mixed`: protected native pointer run
`build/construction-queued-mixed-native-20261023-081216` covers24 cases with queued
Floor/Wall originals, Floor/Wall/Ramp/Fortification targets, and manual cancel,
manual commit or Closest. Each two-tile selection requests one new input. Manual
picker cancellation preserves the old subtype, building/job/item IDs and creates
nothing; commit changes the old subtype in place and creates one new job. The
adapter replays those counts and identities. Source stayed unchanged, frame0,
owned session closed. Mixed queued multi-level stairs remain outside this evidence.

Viewer `build/construction-queued-mixed-main-20261023-082032` verifies one queued
Wall plus three new tiles converted to Floor. Its picker requests three inputs;
cancel preserves the original subtype and IDs with no allocation. Commit keeps
building1490/job382794/item48520 and adds exactly three jobs with items48521..48523.
All four ConstructedFloor tiles naturally complete at frame725 with zero jobs.
Launcher/map/material actions use pointer input; recipe choice and cancellation
use controller calls. A native mandate paused frame1; the owned session was
explicitly resumed, without changing job suspension. Picker and completion
screenshots were inspected, source preserved and session closed; diagnostics were
known engine signatures only. Earlier081354/081805 are excluded: fixture stock
on the original construction tile left that job suspended. The successful fixture
places stock on separate reachable ground. The24-case adapter replay passes;
no runtime changes were needed for this mixed-job flow.

The viewer retains Stairs when browsing elevations before selecting its first
anchor. Previously its generic elevation cancellation cleared the recipe; native
pointer captures retain it. Headless coverage checks upward and downward changes
before anchoring, alongside the existing anchored multi-level selection checks.
Live `build/construction-stairs-recovery-main-20261023-080824` verifies a flooded
middle-level refusal without allocation, followed by fixture recovery, downward
navigation before anchoring, upward navigation with an anchor, and exact pointer
selection of items48520/48521/48522. All three stairs naturally complete at
frame3850 as ConstructedStairU/UD/D, with zero remaining jobs. Recovery back and
recipe reselection use controller calls; menu, map and materials use pointer input.
Refusal and completion screenshots were inspected. Source preserved, owned
session closed, only known engine diagnostics. Earlier075948/080214/080419/080622
recovery attempts failed and are excluded; the final diagnostic run identified
pre-anchor elevation cancellation after initial harness-reset mistakes.

## Native windmill terrain

Windmill preview and commit use native FloorTerrain when no machine connection
exists and OpenTerrain when native machinery support is present. The composed
terrain check precedes liquid refusals, matching DF's ordinary/machine-supported
validator branches. Unknown native results abort. The remaining Lua windmill
shape list is removed; water, magma and existing-construction refusals are shown
only with the recorded native copy. Fixed-footprint refusal collection preserves
native x-major/y-minor order and deduplicates per-tile reasons. The native hookup
query also returns whether its output vector is nonempty; if any tile failed,
that fact appends “Needs ground or near machine”, including when a machine
connection exists, matching native3c1c4e. The UI displays multiline refusals only
when every line is sourced for the selected recipe. Unknown copy stays hidden.
`placement_refusals.json.compound_fixed_footprint` retains literal-dispatch evidence,
69 matching existing windmill cases and four fresh main-viewer comparisons for
windmills and carpenter workshops with mixed water/hidden/occupied/blocked tiles.
Protected042552 matches complete native lists and order; four-line screenshot
inspected, no construction IDs allocated, paused frame0, source preserved and
owned session closed. Known engine diagnostics only. Adapter100 and focused
construction UI checks pass. Earlier042455 stopped during fixture setup because
its millstone case did not produce multiple refusals; it is not acceptance.
Construction-paint aggregation is described below; farm/road extents and warnings are described above.

`windmill.json.native_terrain_service` retains216 cases from protected
`build/windmill-terrain-oracle-20261023-012121`:18 terrain types, six liquids,
with/without a planned side gear. All nine footprint tiles match the composition.
OpenTerrain answers agree with Windmill selected, Well selected and menus closed;
sampled request/redraw/pathfinding state remains unchanged. Paused frame0 and
source manifest preserved. This covers uniform footprints; existing shape and
hookup fixtures provide separate mixed-footprint evidence.

Installed bridge,91 adapter tests, catalog, construction headless and19 CTest
checks pass. Viewer `build/windmill-terrain-main-20261023-012641` passes five
semantic refusals and dry-floor/supported-ramp recovery. Its earlier012525 harness
incorrectly expected Blocked for supported deep water; the native oracle and
product both return Water. That failed run is retained. Completion viewer
`build/machine-hookup-main-20261023-012729` naturally completed the corner-supported
windmill at650 frames with four exact logs. Screenshots inspected; successful
runs contain only known engine diagnostics, preserve source and close owned DF.

## Native machinery terrain

Screw Pump, Water Wheel, Gear Assembly, Horizontal/Vertical Axle, Rollers and
Millstone now share the native hookup query with Windmill. The query passes
explicit building type/subtype, footprint and `direction > 0`, matching the
native buildability caller; native methods own hookup geometry and connection
admission. Preview and commit independently resolve support. Connected machinery
uses OpenTerrain; unconnected machinery uses FloorTerrain. Support uses
FloorTerrain without a machinery query. The Lua machinery/Support shape lists
are removed. Unknown predicates abort; sourced water, magma and construction
removal refusals are exposed only for families with native evidence.

`liquid_refusals.json.machinery_terrain` retains ground/attached evidence:
`build/machine-ground-oracle-20261023-013002` compares3456 first-tile cases on
uniform terrain, including four diagnostic orientation values per family.
`build/machine-connected-oracle-20261023-013438` compares all footprint tiles in
1728 cases over supported orientations with a planned gear at a native hookup
where available. Actual support is checked per terrain. Both use18 terrains and
six liquids. `build/axle-below-oracle-20261023-013747` adds108 vertical-axle cases
with a gear below;12 connect, while floor-blocked combinations remain unsupported.
OpenTerrain selected-family/Well/closed queries agree and sampled native state
stays unchanged. All preserve source manifests and remain paused at frame0.

Two excluded attached-fixture attempts are retained:013213 used the helper's
Screw Pump pointer anchor instead of the native output-tile anchor;013337 included
an unsupported Water Wheel orientation. Product anchor/orientation handling was
already correct. Variable-length machinery and mixed-terrain geometry retain
their separate existing evidence; these new comparisons do not certify every
possible footprint or downstream machine operation.

Installed bridge,92 adapter tests, catalog, construction headless and19 CTest
checks pass. Viewer `build/machinery-refusal-main-20261023-014429` matches40
semantic refusal/recovery previews across all eight families against same-map
native captures. Earlier014155 used the wrong default orientation in the harness
for Water Wheel/Horizontal Axle; it is retained as failed. Completion run
`build/axle-terrain-main-20261023-014651` naturally built a vertical axle over open
space with a planned gear below, retaining one exact selected log at325
frames. Earlier014542 failed before placement on a fixture filename mismatch;
its partial passed field is invalid. Successful screenshots were inspected;
source manifests unchanged, owned sessions closed, known engine diagnostics only.

## Native magma-building terrain

Magma Forge, Magma Smelter, Magma Glass Furnace and Magma Kiln call FloorTerrain
at the center and OpenTerrain at the eight outer cells, before liquid checks.
Preview and commit use the same native predicates; unknown results abort. The
Lua magma footprint shape whitelist is removed. Sourced water, magma and existing
construction refusal messages are displayed for these four recipes. Magma supply
below the building concerns operation and is not required to admit construction.

`magma_placement.json.native_terrain_service` retains432 uniform3x3 cases from
protected `build/magma-terrain-oracle-20261023-014829`: four recipes,18 terrain
types and six liquids. All nine native tile results match the center/outer
composition. OpenTerrain selected-family/Well/closed results agree; sampled UI
and pathfinder state remains unchanged. Paused frame0, source manifest preserved.
Existing magma placement fixtures separately cover mixed center/outer terrain.

Installed bridge,93 adapter tests, catalog, construction headless and19 CTest
checks pass. Viewer `build/magma-refusal-main-20261023-015132` matches20 semantic
refusal/recovery previews across the four recipes against same-map native results.
`build/magma-terrain-main-20261023-015235` passes pointer menu/map/material
selection and natural Magma Forge completion at1550 frames with an exact anvil
and petrified-wood block. Screenshots inspected; source manifests preserved and owned sessions
closed. Diagnostics are the documented engine startup/shutdown issues only.
This verifies construction, not operation supplied by magma.

## Animal Trap terrain and perimeter

AnimalTrap Preview and Place use OpenTerrain before liquids, then SinglePerimeter.
This removes its incorrect floor-only rejection of ramps/stairs and supplies the
missing native `Needs walkable perimeter` refusal for isolated open space.
Water/magma and existing-construction messages are scoped to native evidence.
OpenTerrain composes surface14adea0 and open-tile14aa830/classifier1436f30 with
the supported validator's fortification exclusions and construction refusal.
SinglePerimeter calls coordinate-only aa93e0(x,x,y,y,z), which checks cardinal
neighbors through surface14adea0 with movement=false/flags=0. Fingerprints include
code and classifier tables; neither routine borrows buildreq or reindexes paths.
The open-terrain composition is the loaded-tile branch, not native unloaded-map
fallback behavior; product unloaded positions remain rejected separately.

Protected `build/native-open-oracle-20261023-003721` compared108 terrain/liquid
cases against AnimalTrap native validation. Three menu contexts agree for terrain;
perimeter matches on admitted dry sites. Tracked request/redraw/reindex/generations
stayed unchanged. Source preserved, paused frame0. The fixture records the results.
`build/animal-trap-main-20261023-004500` accepted a ramp, selected exact trap48520
and completed naturally at frame375. Recipe/target used semantic intents; material
selection used a pointer. `build/animal-trap-refusal-main-20261023-004552` passed
five semantic refusal/recovery checks. Completion and perimeter screenshots were
inspected. Saves stayed unchanged, owned sessions closed; successful runs had only
known engine diagnostics.87 adapter tests, catalog, Godot construction suite and
19 CTest checks passed; bridge built/installed. Full offline gate predates this.
The earlier004009 run created a job but stayed paused and timed out; it remains a
failed run. The follow-up added a frame-level pause observer and ran normally;
the pause cause is unresolved. No pause-guard settlement change actually applied,
so do not claim that the second run proves a pause fix.

## Native opening terrain integration

Well/Hatch/GrateFloor/BarsFloor now use OpenTerrain before liquid and their native
family-support predicates. The Lua floor/open/ramp-top/stair shape whitelist is
removed for these recipes. This admits native-supported ramps for floor openings
while preserving Well's separate `Needs open space` requirement. Constructed
fortifications return the sourced `Must remove construction` refusal.

`build/opening-terrain-oracle-20261023-004828` compared432 cases across four
families and18 terrain types. OpenTerrain was checked with the requested family,
Well selected and menus closed (the first two coincide for Well). Dry0/1 terrain
plus family support matched native tile results. Tracked state stayed unchanged;
source preserved, frame0, owned DF closed. Liquid fixture retains the comparison.
`build/hatch-ramp-main-20261023-005032` accepted a semantic ramp target and exact
hatch48520 selected by pointer; construction completed naturally at frame300.
The harness explicitly waited for pause-guard settlement before starting its
completion observer. This successful run does not resolve the earlier AnimalTrap
paused timeout. `build/opening-terrain-main-20261023-005129` passed20 semantic
refusal/recovery observations across all four families: water/magma, existing
construction, isolated open terrain and valid dry recovery. Completion and Hatch
removal captures inspected; source saves unchanged, owned sessions closed, known
engine diagnostics only.88 adapter tests, catalog, Godot construction suite and
19 CTest checks passed; bridge built/installed. Full offline gate predates this.

## Liquid refusals for floor openings

Well/Hatch/GrateFloor/BarsFloor now return sourced `Water at this location` and
`Lava/Magma at this location` from both Preview and Place, before their separate
support check. Natural solid walls retain the earlier blocked refusal. Other
families retain their existing liquid behavior; floor-only recipes need different
terrain precedence and are not covered by this presentation mapping.

`fixtures/construction/liquid_refusals.json` records protected native sweep
`build/liquid-terrain-native-20261023-001122`:5580 evaluations across93 keys,
ten uniform terrain patches and water0/1/2/7,magma1/7. Opening recipes report
liquid on all nine non-wall terrains; walls report blocked. This extends the
existing all-depth flat-floor capture, not arbitrary mixed-footprint precedence.
Main viewer `build/opening-liquid-main-20261023-001409` passed16 observations:
water2/water7/magma1 refusals and valid dry recovery for all four families.
These used semantic preview intents, not pointer placement or new construction.
Hatch magma screenshot inspected; source unchanged, frame0, owned DF closed.
Only known engine diagnostics occurred.84 adapter tests, catalog, construction
headless suite and19 CTest checks passed; bridge built/installed. The initial
adapter run had52 errors from a missing mock initialization, corrected before
acceptance. The full offline gate above predates this message-only extension.

## Construction coverage boundary

The installed catalog audit finds93 supported menu entries. All91 entries with
material filters are admitted by `native_material_family`; FarmPlot and RoadDirt
have no material picker. Normal C++ ConstructionMaterials/Place requests always
bind `nativeMaterialCandidates`, and Preview/Place bind native material quantities.
The construction workflow is verified for this installed catalog: menu navigation,
native eligibility/refusal copy, footprints/orientations/elevations, grouped and
individual material selection, native-supported Closest/Last/Keep behavior,
creation and natural completion, cancellation and stale/session recovery. Retained
natural completion records cover every one of the93 entries. Terrain construction
uses final native tiles and zero jobs; dirt roads use temporary-building retirement
and the resulting soil tiles. Building families use final stage and zero jobs.
These are representative workflows, not every combination of stock and terrain.

Native-reference rendering covers the enumerated furniture, opening, machinery,
workshop/furnace, trap and siege families; farm/road stages; all38 pending terrain
subtypes;150 constructed-ramp material/support/mask cases; and417 upright-weapon
states. Installed artwork is resolved locally. The approved exceptions are fresh
Track distances, stable first-preview Track routes, persistent full-span stair
errors, and correct lower artwork for five-to-ten raised spikes. Existing small
panel spacing differences and the documented Godot diagnostics remain.

Final offline verification is `build/qa/construction-upright-final-offline`:
187 selected checks,189 results, clean pass. The full GPU baseline
`build/qa/construction-current-integration-gpu` passed every check except an
intermittent last-row pressure-picker click. Two diagnostic reruns passed; the
test now waits for rendered layout and asserts row bounds before clicking.
`build/qa/upright-weapon-approved-verified` passes that capture, core tests and
all417 upright GPU cases plus reloads, with known engine diagnostics only. This
is combined full-baseline and focused-follow-up coverage, not a clean full-GPU
rerun. Runtime pressure controls were unchanged; the original miss has no proven
runtime root cause. The separately rebuilt MSVC Track callback passes36 terrain
and96 queued-construction cases.

Removal/cancel/requeue and natural material release are verified for terrain,
furniture and a multi-tile WaterWheel, including entity/outline retirement.
Post-construction production, minecart stopping/dumping, trap activation and the
rest of the building inspector belong to their respective screens. Arbitrary
modded recipes and unsupported DF builds are outside this installed-catalog
acceptance and fail closed. Native quantity wrappers that borrow menu route data
or have unguarded side effects remain excluded; their verified owned scalar/route
inputs are retained. No menu-driven fallback is used.

The shared copied Lua `screen()` is removed. Material lookup for an admitted
family requires a callable native collector; placement rechecks native admission.
Missing, failed or malformed callbacks cannot fall back to copied item screening.
Unknown custom recipes still reject material lookup: their previous fallback
always failed at the missing material-ordering service, so it supplied no usable
additional workflow. SCREW_PRESS and SOAP_MAKER retain their native paths.
Direct-Lua protocol tests inject an explicitly synthetic stock service; native
collector captures and explicit admission regressions establish eligibility.
`build/qa/native-candidate-required` passes construction headless, catalog and138
adapter tests. Protected repeats `build/native-bolt-completion-main-20261023-145043`
and `build/native-material-soap-main-20261023-145211` complete the four-filter
Bolt Thrower and two-filter Soap Maker naturally, at frames2225 and1975, with
exact selected inputs and zero jobs. Both cover pointer menu/material selection,
cancel/reopen and public Play. Picker/completion images were inspected. Both
preserved the source and closed owned DF; both streams classify as
`passed_with_known_issues`, with no unclassified diagnostics. Detailed completion
records are in `material_collector_native_study.json.gz:candidate_gate_removal`.
The Track copied gate and recipe modules are already removed. The historical
negative-distance release-defect record now points to the approved fresh-distance
policy and its verification rather than claiming that cause is still unknown.

The complete offline gate `build/qa/construction-candidate-cleanup-full` passes
on the candidate-gate removal runtime/test sources. Subsequent approval and
capture metadata do not change runtime behavior. This is not full visual acceptance.
Protected menu captures `build/construction-menu-visual-review-20261023-150805`
and `150942` traverse all categories and workshop subgroups via pointer input,
then release modal input. Simulation/building IDs and source remain unchanged;
owned sessions close, with only documented Godot diagnostics. All twelve menu
images were compared with native e2 references: hierarchy, labels and icons are
present, with minor anchor and compact-ancestor width differences. An initially
suspected full-scene painting problem is disproven: the aligned Workshops menu
matches the standalone capture at all254,016 pixels. Build-menu rows now use
DF's regular rectangle for the current level, dark rectangles for ancestors,
and light rectangles for the selected ancestor, removing the invented alternating
row colors. The shared material-picker caller preserves its existing light/dark
selection explicitly. Installed texture pixels establish each menu state.
Focused `build/qa/construction-menu-styles-final` passes construction and material
checks. Protected repeat `build/construction-menu-visual-review-20261023-152014`
passes all twelve menu navigation captures and modal release, preserves paused
simulation/building IDs and source, and closes owned DF. Both streams contain only
known Godot diagnostics. The Workshops screenshot was inspected; thirteen aligned
background crops across current, ancestor and selected states match native e2 at
all57,936 pixels. This is menu-background verification, not whole-screen pixel
identity. Runtime styling changed after the earlier full offline gate.

Protected `build/furnaces-completion-main-20261023-152458` covers all four
fuel-fired furnace recipes through public Build/Workshops/Furnaces controls,
verified map-center clicks and expanded individual material controls. Glass
furnace1490, Kiln1491, Smelter1492 and Wood furnace1493 naturally reach stage3/3
with zero jobs at frame3025, retaining exact granite boulders48520..48523.
Keep, Escape release and public Play are exercised. All four completed captures
were inspected and show the constructed graphics. The source remains unchanged,
owned DF closes and both streams contain only known Godot diagnostics.
`material_collector_native_study.json.gz:fuel_furnace_completion` retains results
and provenance. This proves construction effects and displayed completion, not
reaction execution, magma variants or native sprite pixel parity.

Protected `build/magma-furnaces-completion-main-20261023-152825` extends this
construction flow to Magma glass furnace1490, Magma kiln1491 and Magma smelter1492.
All three naturally reach stage3/3 with zero jobs at frame3700, retaining selected
bauxite48525..48527. Four fixture granite IDs are absent from each candidate list.
The initial run152717 incorrectly expected granite and failed its harness assertion;
installed raws specify granite melting11440 and bauxite13600. Correcting the fixture
required no product change. Public menu, map, individual materials, Keep/Escape and
Play pass. All three completed captures were inspected; source preserved, owned
DF closed, and only known Godot diagnostics remain. The study fixture's
`magma_furnace_completion` records provenance and results. These are construction
sites without magma supply, so this does not establish operational reactions or
native sprite pixel parity.

Protected `build/workshops-completion-main-20261023-153110` extends exact-input
natural completion to Bowyer1490, Carpenter1491, Jeweler1492 and Mechanic1493.
Public workshop menu controls, exact viewport centers, expanded individual granite
selection, Keep/Escape and public Play pass. All four finish at frame2225,
stage3/3 with zero jobs, retaining selected boulders48520..48523. Their completed
captures were inspected and show the constructed graphics. Source unchanged,
owned DF closed, and both streams contain only known Godot diagnostics.
`material_collector_native_study.json.gz:ordinary_workshop_completion` records
these results; production jobs and native sprite pixel parity are not claimed.

Protected `build/clothing-workshops-completion-main-20261023-153534` covers
Leather1490, Loom1491, Clothes1492 and Dyer1493 through the public nested menu,
map, individual material controls, Keep/Escape and Play. Dyer exercises both
barrel and bucket stages. All four naturally reach stage3/3 with zero jobs at
frame3625, retaining granite48520..48522 and Dyer barrel48525/bucket48526.
The observer compares native `PERM` building materials and records all contents
separately: Loom cloth48601 is `TEMP`. The initial run153338 completed buildings
but failed an invalid all-contents comparison after the Loom produced cloth.
All four final captures were inspected; source preserved, owned DF closed, and
only known Godot diagnostics remain. The study fixture's
`clothing_workshop_completion` stores results and observer provenance. This does
not establish every material, production job or native sprite pixel parity.

Protected `build/craft-siege-completion-main-20261023-154903` verifies Crafts1490,
Stoneworker1491 and Siege Workshop1492 through public menu/map controls, typed
material search and exact individual selection. DF reports the actual footprints
as3x3,3x3 and5x5. Siege selects three distinct granite boulders from one group.
All three naturally complete at frame5725, stage3/3 with zero jobs, retaining
48520,48521 and48522/48523/48525 respectively as permanent materials. Keep/Escape
and public Play pass; all three completed captures were inspected. Source unchanged,
owned DF closed, and only known Godot diagnostics remain. The study fixture's
`craft_siege_workshop_completion` records provenance. Earlier partial runs exposed
fixture errors: a3x3 Siege site, virtualized rows below the viewport, and material
staging inside the Stoneworker footprint. Native announcements confirmed the latter
suspended construction with `Item blocking site`; the final fixture reserves each
actual footprint away from its material staging tile. No product rule was changed.

Protected `build/farming-workshops-completion-main-20261023-155215` verifies
Butcher1490, Tanner1491, Fishery1492 and Kitchen1493 through the public Farming
submenu, viewport placement, typed material search and individual selection.
All four naturally complete at frame2100, stage3/3 with zero jobs, retaining
the exact selected granite48520..48523 as permanent materials. Keep/Escape and
public Play pass. All four completion captures were inspected; source unchanged,
owned DF closed, and only known Godot diagnostics remain. The study fixture's
`farming_workshop_completion` records results and harness provenance. This covers
construction and displayed completion, not production or native sprite pixel parity.

Protected `build/remaining-farming-completion-main-20261023-155621` extends this
to Still1490, Farmer's Workshop1491, Vermin Catcher1492 (native Kennels) and
Quern1493. Public submenu, exact viewport centers, material search, individual
selection, Keep/Escape and Play pass. Native catalog footprints are3x3,3x3,5x5
and1x1 respectively. Natural completion at frame2275 leaves zero jobs: the first
three reach stage3/3 with granite48520..48522; Quern reaches stage1/1 with the
selected granite quern48525. All four completion captures were inspected.
Source remained unchanged, owned DF closed, and diagnostics contain only known
Godot issues. `remaining_farming_workshop_completion` stores the results and
harness hashes in the study fixture, with the same construction-only scope.

Protected `build/forge-press-completion-main-20261023-155857` verifies the
Metalsmith's Forge and Screw Press through public Workshops menu routes,
viewport placement, typed material search and exact individual selection.
Forge uses two successive filters (iron anvil48524 and granite48520); Press
selects mechanisms48525/48526 in one filter, matching its installed custom raw.
Both naturally complete at frame2575 with zero jobs and exact permanent inputs:
Forge1490 stage3/3, Press1491 stage1/1. Keep/Escape and public Play pass.
Both completion captures were inspected. Source unchanged, owned DF closed,
known Godot diagnostics only. The study fixture's `forge_press_workshop_completion`
records results and provenance; workshop production and pixel parity remain
outside this construction-effects check.

## Rollers placement and offline verification

`fixtures/construction/roller_speed.json` records protected viewer run
`build/rollers-main-20261022-221434`: pointer menu/speed/endpoints created a
1x3 Rollers building at speed10000/direction0. Both material phases selected exact
mechanism48520 and chain48524; native fields and contained items were checked after
natural completion775. Screenshots inspected; source unchanged; known engine
startup/shutdown diagnostics only. This extends prior speed-control and semantic
coverage, not powered minecart operation or every size/orientation combination.

`roller_speed.json.native_material_integration` adds the owned native collector
and the length threshold. Native `build/native-rollers-length-five-20261023-142815`
uses a five-tile horizontal intent and confirms two mechanisms plus one chain;
closed/menu queries preserve observed request/world/item state. The native picker
screenshot shows Amount needed2. Viewer runs
`build/native-rollers-completion-main-20261023-142610` and
`build/native-rollers-five-completion-main-20261023-142935` use public controls for
direction1 and speed30000, endpoint picking, cancel/reopen, exact individual
selection, Keep and public Play. Three tiles naturally complete at frame975 with
mechanism48525/chain48527; five tiles complete at frame1625 with mechanisms48525/
48526 and chain48528. Native readback verifies both extents, direction, speed,
zero remaining jobs and exact contained inputs. All inputs were fresh, native-
admitted rotten-flagged items with alternatives. Picker/completion images were
inspected, both streams contain only documented Godot signatures, sources stayed
unchanged and owned sessions closed without saving. This verifies the existing
quantity behavior across the threshold, not a new native quantity wrapper or
powered minecart operation.

The current full offline gate
`build/qa/construction-current-offline-20261023/summary.json` passed169 selected
checks and both builds (171 passing result rows), including construction checks
after native farm/road terrain and scoped liquid-refusal integration. Source
identity stayed stable throughout the run.40 other checks were unselected; this
does not establish live/GPU/manual/package acceptance. The earlier
`build/qa/construction-stable-offline-20261022/summary.json` is also retained.

The earlier `build/qa/construction-goal-offline-20261022` remains a failed historical
run (Info frame assertions, missing mesh-test dependency, source instability).
The mesh test now links df3d_assets. The Info fixture expected manual1x pixels but
left adaptive scaling enabled, which correctly chose1.25x at1920x1080. The fixture
now explicitly disables automatic scaling and asserts1x; all exact frame assertions
remain. `build/qa/info-manual-scale-20261022` independently passed the Info and HUD
scaling suites before the full gate. No Info product behavior changed.

## Pressure Plate placement acceptance

Cart-weight labels use native whole-cell positions rather than continuous text
centering. `pressure_plate.json.cart_weight_alignment` records all 41 minimum
choices and 40 numeric maximum choices plus Any from protected native capture
`build/pressure-weight-alignment-20261024-014532`. The source stayed unchanged
and the owned session closed. `build/qa/pressure-weight-alignment` compares
17,534 foreground glyph pixels across all 81 states and passes with only known
Godot diagnostics; the retained 50/Any screenshot was inspected. This verifies
number/glyph positions, not whole-panel pixel identity.

`fixtures/construction/pressure_plate.json` records live viewer run
`build/pressure-plate-main-20261022-220616`: viewport menu, one-use mode, water
trigger/depth3, exact mechanism48520 selection and natural completion650.
Native building fields retain the requested mode/range; Keep building resets the
next draft as recorded by the existing native oracle. Screenshots were inspected,
source manifests stayed unchanged, and only known engine diagnostics occurred.
Earlier220425 clicked behind the option panel and timed out without submitting a
placement; the corrected harness moves the camera to expose the map target.
This verifies construction of one profile, not linked-device activation.

QA catalog inventory now explicitly classifies setup_launcher_test.gd,
setup_session_test.gd and setup_mock.gd as manual workflows under their existing
`tools/release` runners. They require disposable installations/package inputs or
interactive capture and are not standalone offline tests. Catalog validation and
its14 tests pass; this classification does not claim those workflows ran.

## Track Stop placement and option persistence

`fixtures/construction/track_stop.json` now records a complete viewer placement:
`build/track-stop-main-20261022-220134` selected Track Stop, west auto-dump and
friction10 through viewport controls, selected exact log48520, and naturally
completed building1490 after325 simulation frames. Native fields retained the
requested profile; Keep building reset the next draft to no dump/friction50000.
The native oracle `build/track-stop-persistence-native-20261022-220055` confirms
that reset and material-picker Escape returning to the map. No global request
fields are used by the product. This supplements the existing25 profile effect
and25 option-control combinations; minecart operation is not tested here.

The fixed-recipe placement string incorrectly included the separate right-panel
heading from a whole-screen text capture. It now contains only the left prompt;
the existing option panel supplies its own native heading. Headless construction
regression passes. Viewer captures were inspected; known startup/shutdown issues
only. Source manifests stayed unchanged and owned sessions ended without saving.
The final native oracle's placement screenshot is black under its capture overlay
and is excluded from visual evidence; prior native option/picker captures remain.
Existing frame/spacing differences remain open, as does full construction.

## Native removal workflows (2026-10-04)

Maintainer direction is to match native removal semantics. In the mining toolbar,
the remove-stairs/ramps/constructions tool now designates completed constructed
tiles through DFHack's native `Constructions::designateRemove`. The eraser cancels
designations, including active `RemoveConstruction` jobs; it is not a bulk ordinary
building demolition tool. Native captures and sourced tooltips are recorded in
`fixtures/construction/removal.json`.

Selecting an ordinary building now exposes DF's `BUILDING_SHEET_REMOVE` action,
then `Slated for removal` and `Cancel removal`. The existing right-click/Escape
path closes the sheet. The selection-owned controller reads authoritative state
before enabling actions, detaches on selection/closure, rejects late replies and
does not replay unknown mutations. Explicit cancellation invokes native job
cancellation; it cannot toggle back into removal. Management protocol 53 isolates
this new intent from older peers: rebuild/install bridge and viewer together
(see `PINS.md`). No automatic inspector polling or alternate removal algorithm
was added. Native worker activity text is omitted because this payload does not
establish that fact; this is not acceptance of the entire existing building sheet.

Verification: all 19 CTest checks, 76 construction-adapter cases, QA catalog
validation and four headless suites (building removal, semantic service,
fortress HUD, construction) passed. Protected live runs
`build/removal-live-20261004-135228` and `build/removal-live-20261004-135654`
verified real area drags, four active removal jobs cancelled by the eraser,
map-click building inspection, removal/cancellation/requeue, and natural removal
of four completed walls and a bed. The final run includes the corrected native
building-sheet icon and removal of an overlapping local Close button; its UI
captures were inspected. It finished removal after 925 simulation frames.
These are `passed_with_known_issues` for the pinned engine startup/shutdown
diagnostics, with no unclassified errors. Source manifests stayed unchanged and
owned sessions ended without saving. This does not establish every building kind
or every multi-level removal shape.

Protected `build/waterwheel-removal-main-20261024-012258` adds a naturally
completed three-tile WE WaterWheel selected through the real build/material UI.
Map-click inspection, removal, explicit cancellation and requeue were each
verified against paused DF state. Native workers dismantled the wheel in 300
ticks; all three exact selected logs remained registered and were released from
the building, and the viewer retired its entity. Screenshots were inspected;
only the known three engine diagnostics occurred. The source was unchanged and
owned DF closed. This is a dry supported wheel, not powered-machine graph
teardown or general building-inspector layout acceptance. Scoped provenance is
in `removal.json.machinery_acceptance`.
Construction placement no longer owns a hidden inspection/removal mode. The
player inspector's selection-owned `building_removal.gd` state uses the shared
action service; the bridge Inspect/Remove/RemoveConstruction API remains intact.
Diagnostic controller acceptance scripts perform cleanup directly through that
service and validate exact native identity/key receipts. Focused construction,
material, removal and service tests passed in
`build/qa/construction-inspector-cleanup`. Both migrated manual scripts pass
Godot parsing; their broad live scenarios were not rerun for this cleanup.
Protected player workflow `build/waterwheel-removal-main-20261024-013507` repeats
natural exact-input completion, removal/cancellation/requeue and material release
with the obsolete mode deleted. It passed with only known diagnostics and
preserved the source save.

Construction placement receipts are bookkeeping only. Preview geometry contains
only the active draft; confirmed buildings and jobs render from the DF-backed
model. Closing also clears the draft mesh. Historical receipts therefore cannot
resurrect removed buildings' outlines when Build is reopened.
Focused construction, Track and material tests pass in
`build/qa/construction-receipt-geometry`. Protected
`build/waterwheel-removal-main-20261024-013800` repeats exact-input construction,
removal/cancellation/requeue, material release and viewer retirement, then reopens
Build and checks that the retained receipt produces no outline. The reopened
screenshot was inspected, source preserved, and only known diagnostics occurred.

Earlier run `build/removal-live-20261004-134433` timed out in the construction
setup's stress reopen loop before reaching removal; its cause remains unresolved.
Subsequent removal acceptance uses the simpler construction setup and does not
erase that failure. Logs/provenance are in `build/notes/pm/removal-*`.
Installed development plugin SHA256:
`39eb30bf3f01f935be996558495158ebe58392dac821b5073999f704e16bea69`.
Development bridge and extension are updated together; packaged RC5 is unchanged.
This section preserves the distinct native workflows and their acceptance scope.

## Superseded material-distance code removed (2026-10-04)

The independent distance flood, Lua adapter, comparison-only tests and duplicate
native POC have been deleted, including their build flag and command. The shared
Lua serialization helper now lives in its remaining Track-test caller. Retained
native fixtures, current native bridge diagnostics, Track routing tests and live
construction acceptance remain. Historical POC captures under ignored build output
are evidence, not an alternate implementation to maintain. Production uses
`construction_material_native.cpp`; no fallback algorithm is retained.

Verification: core and bridge builds, all 19 CTest checks, QA catalog validation,
and 36 retained Track-shape cases passed. Protected live run
`build/construction-receipt-final-20261004-131511` passed six cancel/reopen cycles,
22 checked selections and natural completion of four walls. It reported only
known engine diagnostics (`passed_with_known_issues`); the protected source stayed
unchanged and owned sessions ended without saving. Build/test logs are
`build/notes/pm/material-removal-*.log`. Installed development plugin SHA256 is
`a21d037094872e1e5e0bbda11ce6db34977dc5d9c3258f82e4809015387b86bb`.
Packaged RC5 remains unchanged.

## Picker receipt profiling and fix (2026-10-04)

Follow-up tracing found avoidable main-thread CPU work. In
`build/construction-phase-trace-20261004-023131`, viewport GPU time near the
receipt was roughly 0.6–1.0 ms and render CPU time 1.7–2.9 ms. The semantic-service
call took 20.6 ms, including 2.8 ms converting 1163 candidates into Godot values,
2.8 ms retaining a receipt, 2.9 ms accepting/copying draft rows and 8.7 ms binding
visible controls. These nested measurements must not be added together.
Unchanged terminal payloads were then converted and destroyed on every poll,
consuming roughly 6–9 ms per service call. Render-queue marker delays are not GPU
execution time; asynchronous viewport samples do not identify an exact same-frame
GPU interval. Probes perturbed frame cadence, so those frame intervals are not
normal-player acceptance results.

`poll_management_header` now polls transport and returns receipt metadata only.
After session invalidation checks, the service requests
`management_payload(epoch, revision, sequence)` only for its matching terminal
request. The getter validates all three identities against retained native state
without polling again, then returns a fresh owned Godot value. An empty result
retains the active ticket for draining; no partial payload is published. Existing
`poll_management` callers retain the full-value API. The construction observer
transfers its already-isolated candidate rows into its draft; other draft callers
keep copy-by-default behavior. Service retention and signal recipients remain
isolated. No worker, shared engine resources or frame budget was introduced.

`build/construction-phase-receipt-20261004-024147` measured receipt processing at
15.1 ms, draft acceptance at 0.64 ms and unchanged polls around 0.4 ms. Four walls
completed. Remaining one-time CPU work includes conversion, retention and visible
control binding. Temporary GDScript probes were removed; opt-in native management
profiling scopes remain.

Final unprofiled `build/construction-receipt-final-20261004-024426` measured a
largest opening interval of 21 ms, with ordinary frames mainly 16–17 ms. This
includes eight frames after readiness and excludes screenshot/export work. It
improves the previous 27–30 ms measurement below, but is not strict 60-fps
acceptance or a large-stock benchmark. Six cancel/reopen cycles and 22 strict
material clicks passed, followed by four naturally completed walls (+350 simulation
frames). Live assertions verified header payload omission and rejection of
mismatched epoch, revision and sequence.

`build/construction-furniture-clear-qa-20261004-024529` passed pending cancellation,
exact item, Last, Reports/Play and both beds' natural completion. Five headless
suites passed: semantic service, construction draft, material view, pause guard
and Reports controller. New regressions verify no payload conversion during 120
pending/idle polls, matching delivery, refused-payload retention, generation
replacement and transferred/default-copy row ownership. Logs and source hashes:
`build/notes/pm/receipt-implementation-validation.json`.

Live checks are `passed_with_known_issues` for the pinned renderer shutdown and
two-object diagnostics, with no unclassified diagnostics. Protected manifests
stayed unchanged; owned sessions ended without saving. The unexplained earlier
four-click failure below remains an evidence gap; subsequent passes do not
establish its cause. Development sources/extension are updated; packaged RC5 is
unchanged. This section preserves the measured cause and receipt ownership
contract for subsequent agents.

## Construction picker presentation cost (2026-10-04)

The material picker no longer rebuilds its full control tree on every refresh.
`construction_material_view.gd` retains a viewport-sized pool of native rows in
`construction_material_row.gd`; the complete semantic list determines scroll
extent and exact identities, while only visible rows bind widgets. Selection,
filtering, expansion and scrolling reuse those controls. Lock changes update
button state without rebinding rows. A press records its binding generation so
releasing after scrolling/recycling cannot select a different item. Hiding the
picker clears its callbacks and snapshot references. Shared styles and unchanged
palette roles avoid repeated theme propagation. These are main-thread controls,
not worker-created engine resources or a per-frame work-budget mechanism.

`ui_texture` now crops the retained CPU atlas image instead of calling
`Texture2D.get_image()` and synchronizing with the GPU. Original art is still
loaded from the supported install and cached for the asset owner's lifetime.
This does not establish that all game art fits resident in VRAM. Material icon
palette baking itself was only about 3 ms total in the initial detailed trace;
the larger problem included repeated UI creation and receipt copying.

The semantic service retains an isolated receipt and gives its last owned local
payload to the one-shot observer; it no longer makes another deep copy for that
observer. Signal delivery remains isolated and is skipped without listeners.
The construction pause guard subscribes only while draining a submitted mutation,
including an unknown result, rather than copying every material-list read while
idle. Ownership and late-receipt behavior have explicit regression coverage.

Measured ordinary-stock workload: 1163 items and 30 groups. Initial deep capture
`build/construction-hitch-baseline-20261004-014246` recorded a 91 ms opening frame;
the earlier native-integration runs measured 90–103 ms. Final unprofiled runs
`build/construction-hitch-final-repeat-20261004-021427` and
`build/construction-hitch-stress-20261004-021719` measured largest opening frames
of 27 and 30 ms respectively, with surrounding frames generally 16–17 ms.
The measurement includes eight frames after readiness, before screenshot GPU
readback. This is a substantial reduction, **not a strict 16.7 ms frame guarantee**.
Detailed profiling and screenshot/trace-export stalls are not compared as ordinary
player frames. Temporary GDScript timing wrappers were removed.

Verification:

- The repeat naturally completed four walls (+475 simulation frames). The stress
  run checked every one of 22 clicks without retries, cancelled/reopened six times,
  and naturally completed four walls (+675 frames).
- `build/construction-furniture-clear-qa-20261004-021839` passed pending cancellation,
  exact item selection, Last, Reports/Play and two beds' natural completion (+575).
- Six headless scripts passed: construction materials, semantic service, pause
  guard, construction controller, Closest and item icons. New tests cover a
  5000-item expansion without pool growth, scrolling to/selecting its final item,
  recycled press/release identity, pending locks, hidden callback retirement,
  replacement snapshots and retained/signal/observer payload isolation.
- GPU material and original-UI assertions passed. Raw logs are
  `build/notes/pm/hitch-final-*.{stdout,stderr}.log` and `hitch-gpu-*`.
  GPU/live results remain `passed_with_known_issues` for the existing pinned
  render-thread finalization/two-object shutdown diagnostics. The original-UI
  test also deliberately exercises its missing-art fallback.
- One earlier run, `build/construction-hitch-final-20261004-021204`, opened in
  26 ms but failed the harness's four-click placement assertion. It did not record
  per-click selections, so its cause remains unresolved; successful repeats do
  not erase that failure. The subsequent harness records group counts and verifies
  each click, selecting an enabled group rather than assuming the first has four
  available items. The repeat used the first group for all four successful clicks.

All owned live sessions ended without saving and preserved the protected source
manifest. The unrelated Godot editor in the pf2 project was left running. The
native bridge is unchanged by this presentation fix. Development extension/source
are updated; the existing packaged RC5 executable is unchanged. Keep the residual
frame cost and unexplained earlier QA failure visible when assessing the next RC.
## Native material candidate collection study

Bed, Chair, Table, Coffin, Cabinet, Box, Statue, Slab, Cage, Chain, Door, Hatch,
GrateWall, GrateFloor, Floodgate, Armorstand, Weaponrack, TractionBench, Bookcase,
DisplayFurniture, OfferingPlace, Instrument, NestBox, Hive, AnimalTrap, WindowGlass,
Well, ScrewPump, WaterWheel, Windmill, GearAssembly, AxleVertical, AxleHorizontal,
Rollers, non-Track construction, and the 23 standard Workshop/7 standard Furnace
recipes now use the owned native collector for candidate admission. Other shared picker families still reconstruct screening
in Lua (`screen`); connected Track now also uses the owned native collector. Placement
connectivity and distance ordering are separate from candidate admission. `fixtures/construction/material_collector_native_study.json.gz`
retains supported-build boundaries/fingerprints and ownership findings for the
next migration, including the constrained diagnostic captures described below.
Collection diagnostics alone do not establish complete picker parity; scoped
product integration evidence follows.

Recipe builder RVA0xaae4b0 accepts a buildreq pointer; collector0xa29630 accepts a
job_item_filter and separate candidate output vector. Suitability0xa27c60 and
container gate0xc93380 are subordinate routines. The inspected bodies contain no
direct buildreq-range RIP reference or RIP-relative global write, which does not
prove transitive safety. The collector mutates owned filter counters and may
update context-dependent burrow/stockpile fields. Both collector and suitability
can reach lazy walkable-group reader0x10afe0, so a wrapper must prove those paths
excluded or restore their complete effects. Native constructor0x1fb050 initializes
an unset position, null unit/job/building/site/stockpile context and empty vectors;
context-free building recipes are a promising constrained entry point. Native
requirement construction0xa69bf0 supplies owned filters; their cleanup follows
DFHack generated destructors. Broader lifecycle acceptance remains separate.
The whole UI caller0x406170
must not be wrapped. Candidate population remains distinct from later placement
enablement and material grouping.

The diagnostic `df3d material-recipe-read <type> <subtype> [custom-id] [plate-flags]` calls the fingerprinted
recipe builder with an independently allocated request, restricted to those
verified standard families, Construction and guarded custom recipes described below.
It returns copied scalar fields and releases native requirements
and the owned request; it never calls the candidate collector or reads global
build-menu state. Protected run `build/native-material-recipe-20261023-093606`
compares Bed, Wall, Floor, Ramp, Stairs, Fortification and Track against the native
menu. Filter fields match; candidate count, total dimension count and required
quantity are excluded because later native stages populate them. Repeated queries
for all 39 admitted recipes match closed-menu baselines under each of those menus.
Observed request/menu fields, item/building/job counters, navigation generation
and reindex flags, window/cursor/mouse state remain unchanged by the queries.
The session stayed paused at frame0, preserved its source and closed. The same
compressed study fixture retains these results and input hashes. This establishes
recipe initialization only: candidate collection, transitive side effects and
allocation lifetime instrumentation remain separate acceptance work. There is
product integration for the verified family sets, including Track, described below.

Recipe initialization is not necessarily the final picker quantity. Protected
`build/native-pressure-quantity-20261023-125332` compares all64 constructor flag
masks and60 valid native Pressure Plate picker configurations. Trigger controls
are operated in DF; requested, configured and picker flags match. The picker
retains `count_required=1` after configuration, while initializing a fresh recipe
with the final flags returns1..4. Product quantity therefore remains1. Do not
replace it with that intermediate constructor result. The diagnostic optional
`plate-flags` accepts0..63, with nonzero values restricted to Pressure Plate;
runtime candidate queries leave this diagnostic input unset. The same optional
argument is accepted by candidate and cold-cache diagnostics.

`pressure_plate.json.native_quantity` retains the complete phase comparison,
input hashes and corrected harness boundaries. Owned queries preserve observed
menu/counters/navigation and full-map path/walkability/item digests; native picker
activity is excluded from query-only digest comparisons. The source stayed
unchanged, frame stayed0 and owned DF closed without saving. The recorded-profile
adapter regression now checks item count against this native evidence. Headless
construction, catalog and131 adapter cases pass in `build/qa/native-pressure-quantity`.
No Pressure Plate runtime quantity or UI change is made from this investigation.

Fixed recipe Preview and Place now obtain required counts from the owned native
initializer through `nativeMaterialRequirements`. The callback accepts semantic
type/subtype/custom ID only, does not collect candidates and does not take final
Pressure Plate flags. The adapter reads it once per operation, validates recipe
arity and count bounds, and rejects missing/non-callable callbacks as well as
failed native results instead of falling back to the helper quantity. Adapter
tests inject an explicit synthetic quantity boundary; these defaults are not
evidence of native quantity parity. DFHack still supplies catalog/filter metadata.
Construction, Bridge, RoadPaved, AxleHorizontal and Rollers are excluded because
their final quantities are calculated at later native stages. Variable weapon
selection retains its separately verified1..10 selection bounds.

The collector fixture's `fixed_quantity_integration` records38 prior native
comparisons and the phase exclusions. Headless construction, catalog and133
adapter cases pass in `build/qa/native-fixed-quantity`. Regressions cover native
counts overriding legacy helper values, invalid native results, unchanged area
quantities and Pressure Plate's default recipe inputs. Protected viewer
`build/native-fixed-quantity-main-20261023-130122` shows a three-gem requirement,
exercises group/individual addition and subtraction, and selects exact rotten-
flagged rubies48525/48526/48527 from four alternatives. DF completes the window at
frame1525, stage1/1, retaining those inputs with zero jobs. Picker and completion
images were inspected; a unit obscures the completed window, so rendered-window
parity remains unproven. Both viewer logs contain only known engine diagnostics.
The source stayed unchanged and owned DF closed without saving.

Missing-callback enforcement is covered by `build/qa/native-callback-required-final`
(construction headless, catalog and135 adapter tests). Protected repeat
`build/native-fixed-quantity-main-20261023-144429` verified the normal native
three-gem flow, group/individual add and subtract, and natural completion at
frame1575 with exactly rubies48525/48526/48527 and zero jobs. Picker/completion
captures were inspected; both logs contain only known Godot diagnostics
(`passed_with_known_issues`). The source stayed unchanged and owned DF closed.
This run verifies the fixed-quantity boundary; full construction acceptance
remains separate work.

The companion diagnostic `material-candidates-read <type> <subtype> [custom-id]` invokes
collector0xa29630 on owned requirements and copies candidate IDs. It verifies
collector/suitability/container/material-lookup fingerprints. Contextual filters,
flags1 other than empty, flags4/5, flags3 other than metal, reaction strings and
contextual containment constraints
are rejected. Unset position and null unit/building contexts bypass the inspected
lazy navigation-reader branches; burrow and stockpile restrictions are disabled.

Paved-road quantity diagnostic: `material-recipe-read <RoadPaved-type> -1 -1 0
<eligible-tiles>` accepts0..961 and runs native0xaafd10 on the owned recipe request.
Collection/cold-cache calls and other families reject this argument. The RoadPaved
branch uses owned total_sq and an empty owned group vector, avoids native Track
route vectors and lazy walkability queries, and produces a temporary No access
string that the owner releases. Native functions and their guarded footprint,
empty-vector-copy and string helpers are fingerprinted. Protected
`build/native-road-quantity-20261023-132427` matches five actual road pickers,
including an excluded center tile, and repeats13 counts across closed/open menu
states without changing query snapshots or full-map/item digests. It stays paused
at frame0, preserves the source and closes owned DF. Evidence is in
`material_collector_native_study.json.gz.paved_road_quantity`. Production preview
and placement now pass their accepted-tile count as the optional fourth semantic
argument to nativeMaterialRequirements. The helper forwards it to the guarded
RoadPaved stage with neutral pressure flags and candidate collection disabled.
Lua requires the callback, validates a single positive integer quantity and
recomputes it for each operation; the copied paved-road quantity formula is removed.
An adapter regression verifies masked count6, commit count9 after terrain changes,
and failure without a valid native response. Other area/route quantity stages
remain separate. Final guarded build56644 installed successfully; protected
`build/native-road-quantity-guard-20261023-132956` accepts13 valid counts and
rejects7 invalid range/family/subtype/collection inputs, with source unchanged,
paused frame0 and owned session closed. Three focused adapter quantity/material
regressions passed for that diagnostic step. Integration build76796 and focused
headless construction/catalog/adapter checks passed in `build/qa/native-road-integration`.
Viewer `build/native-road-integration-main-20261023-133329` uses public menu and
map pointer input for a3x3 road, displays Amount needed3, exercises group and
individual add/subtract, reserves exact granite48525/48526/48527 from four native
candidates, releases placement ownership and resumes using public Play. Natural
frame7300 completion reaches stage3/3 with zero jobs and those exact three inputs.
Expanded picker and visible completed-road screenshots were inspected. Both
viewer streams classify only the known startup/finalize/paired-ObjectDB issues;
no unclassified diagnostics. Source stayed unchanged and owned DF closed. This
accepts the scoped road workflow, not every irregular extent or full artwork parity.

The full offline gate `build/qa/construction-native-full` passes all171 results
(169 selected checks plus two builds), including construction/Track/material,
consumer, lifecycle and rendering checks. This does not establish live UI parity.
Additional viewer `build/native-bolt-completion-main-20261023-134621` verifies
Bolt Thrower's four-filter workflow: public cancel/reopen, exact parts48525,
mechanism48527, chain48529 and bin48531, Keep placement and absent Last control,
then public Play and natural frame2200 stage3/3 completion with zero jobs and all
four inputs retained. Both streams have only known engine signatures, source is
unchanged and owned DF is closed. Picker and completion images were inspected.
`material_collector_native_study.json.gz.trap_siege_extension.bolt_thrower_viewer`
retains the evidence. Native capture `build/native-bolt-icon-20261023-135351`
confirms the parts sprite beside the picker group. The mirror/model now append
`BoltThrowerParts` (93), admitting DF item_type92 through bridge and selection
bounds and resolving installed `ITEM_BOLT_THROWER_PARTS` at ITEM_CONSTRUCTION
(2,9). Existing enum values remain unchanged; generated validators admit the new
value. No DF art is shipped. Classic tile evidence is absent, so that path retains
an explicit unknown-glyph fallback. The synthetic resolver regression distinguishes
these parts from Ballista Parts. Gate `build/qa/bolt-parts-final` passed all
19 CTest checks plus construction headless, catalog and adapter checks against
unchanged sources. Viewer `build/native-bolt-completion-main-20261023-140230`
shows the matching group and two individual icons, passes cancel/reopen and all
four exact selections, then naturally completes at frame2225 with zero jobs and
all four selected inputs retained. Both streams contain known Godot signatures
only; source save stayed unchanged and the owned session closed without saving.
Picker/completion screenshots were inspected. The fixture's
`trap_siege_extension.bolt_thrower_parts_icon` retains this evidence. This closes
the parts-icon omission, not the remaining full-screen visual audit.



Material resolver0x14add70 can call creature lookup0x701e70. Historical-figure
materials can populate `creature_handler.hist_fig_to_creature_map` on a cache miss
(0x701ff6..0x702023). A scoped copy/swap preserves the original cache nodes and
buckets while the collector uses a private copy, then restores the original
before Lua allocation. Returned material pointers do not point into cache nodes.
This permits the reinforced-wall metal filter. Diagnostic command
`material-candidates-cold-read <type> <subtype> [custom-id]` clears only the private copy and
checks restoration using original map header bytes, node addresses, keys and
values. Protected `build/native-material-cold-20261023-100836` forces a miss using
a synthetic bar with historical-figure bone material (type222, figure8490).
All20 calls insert one private entry, match ordinary query IDs/filter counters,
and restore the original cache. Full map/item hashes and scalar snapshots remain
unchanged, the source is preserved, simulation stays paused at frame0 and owned
DF closes. This tests cache lifetime, not ordinary bone-bar gameplay.

Protected full capture `build/native-material-collector-full-20261023-095957`
passes eight native picker comparisons: Bed (one candidate), Wall, Floor, Ramp,
Stairs, Fortification and Track (2,153 each), and ReinforcedWall (2,153 building
materials plus1,202 metal bars). Complete IDs/order and total dimensions match.
All39 recipes repeat identically with menus closed and each picker open. Native
menu-selection vectors can be empty before placement, so they are not a candidate
oracle. Track uses a two-tile route in this capture. Earlier incomplete probes
are retained in the study fixture with their failure status; this full capture
supersedes them for these eight comparisons.

`build/native-material-collector-matrix-20261023-095521` additionally passes44
Bed/Wall comparisons using synthetic flags, actual bin containment and hidden
ground. It exposes differences from the Lua `screen` approximation: for these
items DF admits garbage_collect, hostile, rotten, trader and spider_web flags,
rejects melt/location_reserved, admits missing on_ground and a dumped outer bin,
and admits hidden ground at this stage. These are observed fixture semantics,
not a blanket policy for other item families or real hauling/job lifecycles.
Native candidate enablement is recorded separately from collection.

Full-capture query batches preserve hashes of every map path-cost/walkability
cell and item IDs/flags/positions/reference counts, plus the scalar state listed
above. Sources remain unchanged, sessions stay paused at frame0 and owned
processes close. Reference contents and every world field are not covered by
these hashes; the44-case matrix checks scalar snapshots per query. The study
fixture retains results and input hashes. The family extensions below establish
native candidate collection and product integration beyond this original matrix;
that matrix alone does not prove placement enablement or grouping. Wrapper0xaafd10
reads global Track route vectors in its Track branch, so unrestricted use is
prohibited. RoadPaved has a separately guarded owned-request branch, described
above. Bridge/AxleHorizontal/Rollers visit lazy group reader0x10afe0 before their
quantity calculation; pending reindexing can rebuild world walkability and alter
shared path costs. No side-effect restoration contract has been established for
those branches, so their native-matched quantity behavior remains in the adapter.
Calling an internal basic block or suppressing reindexing is not a supported API.

Connected Track also consumes that collector for every fresh snapshot, including
synchronous Place revalidation before creating jobs. The copied flags/containment
and recipe modules and their embedded wiring have been removed. Failed, missing,
duplicate or malformed native IDs fail closed. Route-based group enablement and
fresh native distance ordering remain separate stages. Protected
`build/track-native-collector-20261023-114207` compares all 2157 IDs and enablement
with the actual Track picker across three menu histories: all match, with 2105
enabled items and 32 groups. Full-map path/walkability and item digests, observed
menu/counters/navigation and the source save stay unchanged. The owned session
closed without saving. `material_collector_native_study.json.gz.track_integration`
retains records, hashes and limits. All 23 remaining candidate/group/copy/ordering
checks and 128 adapter tests pass; six tests of deleted approximations are retired.
Viewer `build/track-native-collector-main-20261023-115038` subsequently verifies
public Track placement over a natural ramp, search/expand/scroll/exact selection
of items4917/4981/5024, released modal/pause ownership, and public Play. Native
readback matches subtypes7/26/8; all three tiles complete in dolomite at frame1650
with zero jobs. Both viewer streams contain only known startup/finalize/ObjectDB
diagnostics. The source stayed unchanged and the owned session closed. Exact
picker and completion screenshots were inspected; the completion view obscures
lower tiles and is not full rendering-parity evidence. Construction headless and
catalog QA also pass. The fixture retains all results and hashes.

The first viewer attempt failed because the harness searched only instantiated
rows; scrolling fixed that. A second attempt placed the exact items but timed out
with DF paused after diagnostic unpause. Its pause transition remains unexplained.
The successful run uses explicit public Play from a paused fixture and does not
claim automatic resume from a running starting state. Neither failed run counts
as completion evidence; their unclassified harness diagnostics remain retained.

For those thirty-four families and non-Track Construction, the bridge injects
this collector into
Materials and Place. The scanner iterates returned IDs instead of applying Lua
flags/containment/suitability/visibility approximations. Reservation and final
creation use fresh membership once per Place safe-point invocation, so a yield
between reservation and creation cannot retain stale admission. Local placement
walkable-group checks remain a distinct stage. Native-query failure stops the
operation with blank player text; no approximate list is published. Standalone
synthetic tests can omit the callback to exercise legacy families, while runtime
always injects it. Recipe quantities and other families are not migrated by this.

Focused headless construction, catalog and adapter checks pass. Regressions cover
native-admitted flags, native-query failure and membership changing before
reservation or after reservation yields. Protected viewer
`build/construction-stairs-recovery-main-20261023-101757` verifies no-allocation
water refusal/recovery, exact items48520..48522 and natural three-level completion
at1,675 frames. `build/native-material-bed-main-20261023-102051` completes a Bed
using Closest and exact item48520 at575 frames. The flagged-bed regression
`build/native-material-bed-flag-20261023-102753` sets rotten, which native collection
admits and the old Lua screen rejected; it places the same item and completes
naturally at350 frames. Its trace required no additional simulation resume.
Two earlier flagged-bed attempts timed out without completion-progress snapshots;
they remain excluded and their cause is unproven. Sources are preserved and owned
sessions close. Successful viewer runs have known startup/finalize/shutdown
diagnostics only; both log streams were classified and completion screenshots
inspected. These are scoped integration checks, not full construction acceptance.

Machinery capture `build/native-material-machines-20261023-112032` compares
complete native lists/order and counters for Well (803/10/19/13 candidates),
ScrewPump (803/4/7), WaterWheel135, Windmill135, GearAssembly13, both axle types135,
and Rollers (13/19). Horizontal axle and roller intents span three tiles; required
quantity remains a later-stage field. Repeated queries for all eight recipes
match closed-menu baselines under each native picker and preserve observed
map/item hashes and menu/counter/navigation state. The paused frame0 source is
preserved and owned DF closes. These families now use native collection.

The screw filter's virtual slot0x1b0 resolves to0xc620d0 and reads the trap-component
definition. Well bucket flag bit27 reads containment references and classifies
contents through0xc91b60, which uses the existing isolated material lookup and
string-vector membership0x6b8af0. That helper calls the VCRUNTIME140.dll memcmp
import. These routines are fingerprinted; inspected persistent mutation remains
covered by the existing material-cache isolation. The study records addresses,
fingerprints, complete lists and scoped observations.

Native material cache identity includes family and requirement index in scanning,
preview invalidation and Place lookup. DFHack metadata alone can be identical for
distinct native requirements. A three-input regression reproduced first-list
aliasing before this fix; now it preserves disjoint candidate lists and refuses
construction when the third input becomes stale. This protects candidate mapping;
quantities and powered/liquid gameplay effects still need their own evidence.
Focused headless/catalog/128 adapter checks pass and the bridge is rebuilt and
installed. Protected viewer `build/native-material-pump-main-20261023-112707`
uses public controls, cancels/reopens the picker and selects all three inputs
explicitly. Native-oracle IDs48526/48528/48530 are marked rotten after cancelling
the oracle build; the viewer retains them through Keep building and natural
completion atframe1625 with zero jobs. Exit releases the temporary pause before
the observer resumes simulation. Both log streams contain only known engine
diagnostics; picker/completion screenshots were inspected. Source preservation
and owned-process cleanup pass. This proves construction, not powered pumping.

The remaining single-item furniture capture
`build/native-material-tools-20261023-110859` compares complete native lists/order
and counters for TractionBench1, Bookcase4, DisplayFurniture2, OfferingPlace2,
Instrument6, NestBox1, Hive1, AnimalTrap1 and WindowGlass1. All nine recipes match
the closed-menu baseline under every picker; query batches preserve full map
path/walkability and item-state hashes plus observed menu/counter/navigation
state. The paused frame0 session preserves its source and closes. These nine
families now use native collection in Materials and Place.

Tool-use suitability invokes virtual slot0xe0. For item_toolst this resolves to
RVA0x28a180, which reads the raw definition and searches its tool-use vector via
0xec0d0. The inspected helper reads that vector and writes only its caller-owned
result; both routines are fingerprinted. AnimalTrap uses the already admitted
empty-container flag. The compressed study retains branch/getter addresses,
fingerprints, exact comparisons and input hashes. These checks do not prove
animal capture, nest/hive production, instrument performance or book storage.
Focused headless/catalog/127 adapter checks pass; admission/stale membership now
covers26 families (52 scenarios). Bridge build/install passes. Protected viewer
`build/native-material-bookcase-main-20261023-111426` uses public controls and
expanded exact selection of rotten-flagged48520, with an unflagged alternative
available. DF naturally completes the Bookcase at650 frames with no remaining
jobs. Both viewer streams classify only known engine diagnostics; expanded-picker
and completion screenshots were inspected. The source is preserved and owned
DF closes. Book storage and the other listed interactions remain separate.

Door, Hatch, GrateWall, GrateFloor, Floodgate, Armorstand and Weaponrack use
native candidate collection as well. Protected capture
`build/native-material-openings-20261023-110028` compares all candidate IDs/order
and filter counters against their native pickers:18 Door,1 Hatch,2 of each grate,
3 Floodgate,1 Armorstand and1 Weaponrack. All seven recipes also match the closed
baseline under every picker. Full map path/walkability and item-state hashes,
observed menu/counters/navigation/window/cursor state remain unchanged by query
batches. The source is preserved and the paused frame0 session closes. Static
recipe branches all allocate owned requirements and join the previously verified
common initialization path; no collection guard was relaxed. The compressed
study retains branch addresses and exact lists. Broader interaction effects are
separate from this material-selection evidence.
Focused headless/catalog/127 adapter checks pass, with native admission/stale
membership exercised across all17 families. Bridge build/install passes.
Protected viewer `build/native-material-hatch-main-20261023-110514` verifies
public-control empty-space hover/click refusal (`Surrounded by empty space`),
recovery with the footer shrinking, and exact selection of rotten-flagged48520
with an unflagged alternative present. DF completes the Hatch naturally at375
frames with zero jobs. Both viewer streams contain only known engine diagnostics;
refusal/completion screenshots were inspected. The source is preserved and owned
DF closes. This does not establish linked operation of grates/floodgates or the
remaining full-construction interaction matrix.

Cage and Chain also use the native collector. Protected capture
`build/native-material-restraints-20261023-105355` compares all15 cage and12
restraint candidates, including ordering and filter counters, under both pickers
and with the menu closed. Map/item hashes and observed scalar state are unchanged;
the source is preserved and the owned session closes. Recipe branches0xaae95c
and0xaae935 share the already verified context-free path. Unlike Box, Cage does
not add the empty-container filter: a cage containing a real Blocks item remains
in both lists. This does not establish creature-containing cage behavior.
Two initial fixture failures (an incorrect empty-cage assumption and category
navigation) are retained as excluded attempts. Stale-selection regressions cover
both added families; focused headless/catalog/127 adapter checks pass.
Protected viewer `build/native-material-cage-main-20261023-105657` uses public
launcher/category/Cage/Closest/map controls and naturally completes exact
rotten-flagged item48520 at325 frames with no remaining jobs. Both logs classify
only known engine diagnostics, and the completion screenshot was inspected.
The source is preserved and owned DF closes. This verifies empty-cage construction;
animal assignment and restraint attachment effects remain separate coverage.

Core furniture capture `build/native-material-furniture-20261023-103738`
compares complete native candidate lists and counters for Bed1, Chair27, Table26,
Coffin1, Cabinet1, Box29, Statue3 and Slab3. Repeated queries under each picker
match closed-menu results and preserve full map/item hashes and observed scalar
state. Box adds native flags1.empty: branch0xa28004..0xa2803d checks containment
reference types. The guard admits that bit; a real filled-box control is excluded.
An earlier probe stopped at this guard and is not acceptance evidence.

The runtime family dispatch and stale-selection regression now cover all eight
families. Focused headless/catalog/127 adapter checks and bridge build/install pass.
Protected `build/native-material-table-main-20261023-104354` verifies Table native
inside refusal/recovery and exact flagged-item selection with an unflagged
alternative available. DF naturally completes rotten-flagged item48520 at400
frames with no remaining jobs, demonstrating an admission rejected by the old
Lua approximation. Public controls are used without forcing launcher visibility.
Both viewer logs contain only known engine diagnostics; the completion screenshot
was inspected. Both protected captures preserve their source and close owned DF.
The compressed study fixture retains these comparisons and their scope. This does
not migrate the remaining furniture, machinery, trap or variable-size families.

Standard workshops and furnaces now use native collection for Materials and
fresh Place validation. Native recipe branches are Workshop0xaaf194 and
Furnace0xaaee84; custom raw-defined recipes and Workshop Tool remain separate.
Temperature safety adds fingerprinted item getters0xcb1ec0/0xcb1f00 (53 bytes
each) and helper0x149ef80 (296 bytes). The getters pass native11000/12000 limits;
the helper reads material thresholds through the already isolated historical-
figure material cache. No new global UI inputs or filter guard relaxations are
introduced. Native filter quantities remain distinct from candidate admission.

`build/native-material-workshops-20261023-115710` verifies all30 recipe results
with menus closed and under ten representative native pickers. Exact native
candidate IDs/order/filter counters match Carpenters2181, Forge[10,2059], Magma
Forge[10,1094], Quern4, Millstone[11,5], Ashery[799,106,14], Dyer[106,14], Still2181,
WoodFurnace2059 and MagmaSmelter1094. Full-map path/walkability and item digests,
plus observed menu/counters/navigation stay unchanged. Source preservation and
owned-session closure pass. This covers representative branches, not each of the
30 native menu routes. The durable collector fixture's `workshop_furnace_extension`
retains all results, branch mappings, temperature traces/fingerprints and limits.

Headless construction/catalog and128 adapter cases pass in
`build/qa/native-material-workshops-final`; added standard-workshop/furnace cases
verify native-admitted flags and fresh stale-item rejection. Initial new test
fixtures supplied wrong family dimensions; the corrected final run passes.
Protected viewer `build/native-material-ashery-main-20261023-120336` verifies
public cancellation/reopen, all three exact native-reference items48526/17160/
48530 with rotten set, Keep building, Escape ownership release and public Play.
The Ashery completes naturally at frame1400, stage3/3, with those same inputs
and zero jobs. Picker/completion screenshots were inspected; both viewer streams
contain only known startup/finalize/ObjectDB diagnostics. Source stayed unchanged
and the owned session closed without saving. Ashery production, other workshop
use effects, custom recipes and full presentation coverage remain unverified.

Installed custom Screw Press and Soap Maker recipes now use the native collector.
Materials and Place resolve the semantic raw code to its stable raw ID and pass
that ID through a shared candidate callback; no native menu selection is read.
The optional diagnostic `custom-id` is validated against the correct workshop or
furnace raw vector before initialization. Missing/wrong-family IDs fail closed,
as does a custom ID supplied for a standard recipe. Raw filters with unreviewed
flags, ore constraints or nonempty reaction strings are rejected before native
recipe construction. Empty-string copy helper0x6f8d0 is fingerprinted over256
bytes; its admitted path copies zero bytes through VCRUNTIME140 `memmove` and
writes only the owned string length/terminator. No allocation branch is reached.

Protected `build/native-material-custom-20261023-120959` matches native Screw
Press5 and Soap Maker[10,2157] candidate IDs/order/filter counters. Both baselines
repeat under both native pickers while full-map path/walkability, item digests
and observed menu/counters/navigation remain unchanged. Source preservation and
owned-session closure pass. The collector fixture's `custom_recipe_extension`
retains all records and the helper/import trace. Guarded custom Furnace input is
available diagnostically, but no custom Furnace has native picker acceptance;
other custom raw codes remain on the existing runtime path pending evidence.

Headless construction/catalog and129 adapter cases pass in
`build/qa/native-material-custom`. A new regression keeps two raw IDs distinct
with identical requirement metadata and rejects stale admission before creation.
Viewer `build/native-material-soap-main-20261023-121408` verifies public picker
cancel/reopen, exact rotten-flagged bucket48526 and granite boulder48528, Keep
building, Escape ownership release and public Play. The workshop completes at
frame2300, stage3/3 with both inputs and zero jobs. Four invalid raw-ID cases
reject without candidate output. Picker/completion images were inspected;
both logs contain only known startup/finalize/ObjectDB diagnostics. The source
stayed unchanged and the owned process closed. This does not establish soap
production, Screw Press completion, arbitrary custom filters or full UI parity.

All six Trap and three SiegeEngine subtypes now use native candidates for
Materials and fresh Place validation. Their recipe branches use the already
verified owned constructor/allocation/vector helpers; no filter guard relaxation
or global menu input is added. Weapon Trap retains separate mechanism and weapon
requirements, and Bolt Thrower retains native parts/mechanism/chain/bin order.
Required quantities, placement connectivity and subsequent building use remain
separate from candidate admission.

Protected `build/native-material-traps-20261023-122357` matches all nine native
pickers: Lever25, PressurePlate25, CageTrap25, StoneFallTrap25, WeaponTrap[25,60],
TrackStop2157, Catapult4, Ballista4 and BoltThrower[4,25,15,76]. Closed-menu
results repeat under every picker. Full-map path/walkability and item digests,
plus observed menu/counters/navigation remain unchanged at frame0. The source
was preserved and the owned session closed. The collector fixture's
`trap_siege_extension` retains the complete comparisons and branch review.
Headless construction, catalog and131 adapter cases pass in
`build/qa/native-material-traps`, including separate requirement identities,
variable weapon selection and stale-input rejection before any building creation.
This does not establish trap activation, pressure-plate linking or siege firing.

Viewer `build/native-material-weapon-main-20261023-123217` verifies public
Closest selection, cancellation/reopen, three weapon groups, adding two weapons
and Done. DF naturally completes the trap at frame3550, stage1/1 with no jobs,
retaining the exact native-reference mechanism48580 and weapons48536/48537/
48538/48552/48566, all marked rotten in the fixture. The harness waits for the
released host and enabled Play button before resuming; an earlier run clicked
without that readiness check and timed out. No production pause change was made.
Both final logs contain only known startup/finalize/ObjectDB diagnostics. Picker
and completion images were inspected, though a unit obscures the completed trap
tile, so this does not establish full trap-art parity. Source preservation and
owned-session cleanup pass; no session was saved.

BarsVertical, BarsFloor, WindowGem, Support, ArcheryTarget, TradeDepot, Weapon,
Bridge and RoadPaved now also use native candidates for Materials and fresh
Place validation. Their branches require only the existing owned constructor,
allocation and vector-append helpers. No filter guards or native state ownership
rules change. FarmPlot and RoadDirt have empty native recipes and do not need a
material collector. Custom recipes outside the two installed workshop codes
remain separate; native quantities and placement connectivity are not migrated
by this change.

Protected `build/native-material-remaining-20261023-123605` matches all nine
native pickers: both bars1210, gem window4, support/target/depot2181 each,
upright spikes15, bridge2181 and paved road2181. Bridge and road use3x3 selections.
Closed baselines repeat under every picker with full-map path/walkability, item
digests and observed menu/counters/navigation unchanged at frame0. Source
preservation and owned-session closure pass. The collector fixture's
`remaining_standard_extension` retains the complete comparisons and branch map.
Headless construction, catalog and131 adapter cases pass in
`build/qa/native-material-remaining`; the native-admission/stale-reservation
regression now covers each of these nine families.

Viewer `build/native-material-bridge-main-20261023-124108` verifies a public3x3
Bridge placement, expanded material list, group and individual addition/removal,
then exact boulder48525/48526/48527 selection from four rotten-flagged candidates.
After pause ownership releases and public Play resumes DF, the bridge completes
naturally at frame6475, stage3/3, retaining those three inputs with zero jobs.
Expanded-picker and completed-bridge images were inspected. Both viewer streams
contain only known startup/finalize/ObjectDB diagnostics. The source stayed
unchanged and owned DF closed without saving. This does not establish bridge
linking/raising/lowering, full rendering parity or effects for every new family.

## Native material navigation integration (2026-10-04)

Construction material distance lookups call DF53.16's native flood through
`bridge/plugin/construction_material_native.cpp`, including connected Track.
Candidate admission, grouping, placement geometry and construction commands have
separate owners; this callback computes material-navigation distances only.

The internal distance callback accepts owned seed/target arrays and an optional
construction subtype. The unused Lua material-terrain reader chain and search
bounds/limit parameters have been removed from the callback and its callers.
The separate Track routing terrain reader remains. Developer console commands
retain their legacy trailing argument for compatibility with captured harnesses;
it does not impose a native flood work limit. Native frontier/storage limits
remain enforced by the wrapper.

Material selection has one implementation in `construction_draft.gd`. Its
`construction_exact_selection_test.gd` exercises all 558 recorded native kernel
transitions plus recorded group clicks, final reserved IDs and exact-item repeat
clicks. The test-only Lua selection copy and tests of the unused terrain reader
were removed; native evidence fixtures retain their historical provenance.

Cleanup verification (2026-10-22): bridge build/install, 76 adapter cases, 28
candidate/order cases, catalog/embedding checks and all 19 root CTest checks
passed. Godot draft and exact-selection suites passed with the known rendering
thread notice. Protected run `build/construction-native-cleanup-20261022-094556`
passed six cancel/reopen cycles, 22 material clicks and natural completion of
four walls after 425 simulation frames. Its picker capture was inspected; the
owned source manifest was unchanged and the session ended without saving.
The run is `passed_with_known_issues` for the documented rendering-thread,
render-device shutdown and two-object diagnostics. Installed development plugin
SHA256: `98ca87ae03d80d8ce20ecd7bb3b1939f0f3efc9f897349dc0b7f236a902f7605`.

The older `build/construction-acceptance-20261022-094424` run failed at the
TradeDepot material oracle: `construction-acceptance-verify.lua` still compares
squared geometric distance and tuple ties, superseded by native navigation.
Its source was preserved; that harness needs a separate oracle update and is
not a passing check. The QA gate also remains blocked by unregistered
`setup_launcher_test.gd`, `setup_mock.gd` and `setup_session_test.gd`; the focused
checks above ran directly. No full offline-gate or packaged-release pass is claimed.

The callback runs synchronously at the bridge safe point. Godot still sends and
receives asynchronous semantic requests. It validates the supported PE identity
and complete flood fingerprint plus compiled structure offsets, allocates its own
request, snapshots/restores generation/clear fields, all loaded block path costs
and both frontier buffers, then returns only owned scalar results. No native UI
request is read or driven. The supplied semantic seeds are encoded in a native
Construction rectangle/mask (one level, at most 31 by 31); construction subtypes
are passed through so DF supplies its own stair-specific vertical origins. Other
families retain their previously verified semantic footprints. Item and geometry
limits remain distinct from simulation throughput; scratch snapshots reject more
than 250000 loaded blocks and retain no pointers across calls.

Both frontier tails receive invalid-coordinate sentinels after backup. If either
last slot is written, the callback rejects all distances as ResourceLimit,
conservatively including exactly-full frontiers. RAII restores scratch on normal
and C++ exception exits. Developer reasons remain internal: overflow uses native
"Building Placement Distance Overflow" verbatim (DF string RVA 0x16bebc8), and
other native-wrapper failures have no invented player-facing substitute. The
native error text is not prefixed with authored material-list prose.

Verification and retained evidence:

- `build/native-material-integration-20261004-001427`: Wall, Floor and Bed
  comparisons matched their native pickers, including generation reset; reopened
  pickers remained identical and simulation resumed. Invalid footprint rejected.
  Development-only frontier fault injection returned ResourceLimit with no
  partial distances and restored generation state. This validates the rejection
  path, not a naturally occurring 120000-entry overflow stress case.
- `build/native-integration-stairs-reverse-20261004-000920`: all 12 stair-selection
  variants matched native distances normally and after forced generation reset.
- `build/native-integration-bridge-20261004-001011`: 1x1, 2x2, 3x3, 1x3 and 3x1
  matched native distances at 2402 candidate/nearby positions each, normally and
  after reset. Nearby solid/air positions cover reachable and unreachable
  outcomes. Target path costs were identical after scratch restoration.
- `build/connected-track-material-item-distances-20261004-001756`: four normal-build
  cases matched native per-item costs and all 33 groups' order, names and members
  for 60 candidates each.
- `build/construction-furniture-clear-qa-20261004-002139`: cancellation during
  lookup, exact item, Last, Reports/Play and two beds' natural completion passed
  (+600 simulation frames). Earlier `...-001840` timed out at Catalog without a
  construction request or opened panel; its screenshot/result are retained. The
  harness now waits for layout before calculating click coordinates. The repeat
  does not erase the failed attempt.
- `build/native-material-open-perimeter-20261004-003515`: final default build,
  four walls naturally completed (+350 frames), 1163 items/30 groups prepared in
  188 ms (native navigation 47 ms), picker wait 283 ms after pointer release.
  This fixture selects naturally empty floor with a clear perimeter and does
  not rewrite terrain. The earlier same-site run `construction-material-profile-
  20261004-000019` also completed all four walls: preparation 188 ms, navigation
  62 ms, picker 284 ms, versus RC5's sampled 906/781/925 ms respectively.
- 76 construction adapter tests passed, including native stair subtype plumbing
  and verbatim failure-copy propagation. Normal and diagnostic bridge builds
  succeeded. `build/notes/pm/native-integration-adapter-tests.log` and
  `native-integration-final-build.log` retain results.

The final build's ordinary-site runs `construction-material-profile-
20261004-002611` and `...-002957` passed lookup/placement but FAILED the strict
natural-completion gate. In the latter DF advanced beyond 8700 frames, completed
three walls and suspended the remaining job. Follow-up evidence at
`build/native-material-suspension-20261004-003411/native-suspension.json` records
DF's exact reason: "Item blocking site." That failed gate remains failed; do not
reinterpret it as a pause stall, erase it using the empty-floor pass, or override
DF suspension to force completion. Native job admission does not promise that
all jobs will finish despite later site obstructions.

At this native-integration checkpoint, Godot had a roughly 90–103 ms picker-opening
frame hitch (93 ms in the final empty-floor run). The presentation work above
supersedes that measurement with 27–30 ms samples; it still does not establish
a strict 16.7 ms frame guarantee.
Existing render-thread shutdown and two-object-leak diagnostics also remain;
live result classification is passed_with_known_issues where gameplay passed.
This is bounded coverage, not every possible footprint/mask/terrain combination.
Existing release defects, including the separately observed RC5 resume timeout
and cold-route ordering limitations, are not silently marked fixed.

All owned integration-test processes closed without saving; protected source
manifests were unchanged. The bridge tested in those runs had SHA256
`af2a7507ba8f55bc855c597c54747d6d9116ce012403d67f40e4a22bac1af71a`;
source/binary provenance is in each run's `implementation-validation.json`.
These results establish the tested source build, not a packaged release.

## Construction lookup performance: 0.1.0-rc.5

The maintainer authorized prioritizing explicit gameplay actions over simulation
throughput. Profiling the ordinary-stock four-wall case found navigation consumed
1438 ms of 1578 ms preparation; batching gaps were small and item details took
15 ms. Increasing the builder share alone would not address that cost.

The RC5 package used hash indexes for visited tiles and per-search facts.
Source builds use the native callback described under Native material navigation
integration; the following measurements describe the RC5 implementation.
Explicit frontier/target vectors determined traversal and output order. The Lua
fact reader shared one tile observation among its destination/opening predicates
within a synchronous call, without retaining native pointers or dynamic facts
across reads or safe points. This optimization preserved movement rules, item
eligibility, distance metrics and wire format; the viewer remained asynchronous.

The repeated live case prepared 1163 items in 30 groups in 906 ms (navigation
781 ms), about 43% less preparation time. The measured picker wait was 925 ms
versus 1621 ms in the baseline; this harness interval begins after pointer release,
not at click-down. During lookup, 95% of 58 viewer frames were at most 17 ms,
maximum 90 ms. Four walls completed naturally at +400 observed simulation frames.
These are sampled timings on this machine, not promises for every fort. A paired
reader probe produced identical facts at 11163 real tile positions. Evidence:
`build/construction-material-profile-20261003-115713` (baseline) and
`build/construction-material-profile-20261003-120445` (optimized).

An earlier optimized run (`build/construction-material-profile-20261003-120158`)
populated choices in 799 ms and placed four walls, but timed out waiting for
automatic resume. It remains an unresolved intermittent QA finding, not a passing
gameplay result or a proven startup-state issue. The repeat explicitly observes
the initial running state and captures final session/guard state. Existing
RC4/RC3/RC2 defects remain applicable. Final gameplay/package verification is
recorded in the RC5 external validation record when complete.

Opt-in diagnostics: set `dfhack.df3d_construction_profile={}` before a lookup in a
protected development lane and read its scalar rows afterward. Navigation/details
are nested intervals; do not sum them with elapsed or active time. Disable by
setting the field to nil. No timers run inside ordinary unprofiled coroutine steps.
Final furniture gameplay (`build/construction-furniture-clear-qa-20261003-121120`)
passed cancellation, exact item, Last, Reports/Play and natural completion of two
beds. All owned sessions closed without saving; live status is
`passed_with_known_issues` for the documented engine diagnostics.
Offline evidence: `build/qa/material-performance-final-core`,
`build/qa/material-performance-viewer`, native callback replay, 74 adapter
regressions and 10 terrain-reader tests. RC5 work-count coverage checked shared
observation and dynamic occupancy changes across recorded tiles.

## Busy indication and gameplay QA: 0.1.0-rc.4

RC4 adds the maintainer-requested animated activity marker to construction
material loading and placement. It is indeterminate, uses the native palette,
adds no status copy or invented percentage, and stops when choices are ready.
The explicit 2026-10-03 request authorizes this asynchronous-wait indication;
it does not loosen native-copy requirements elsewhere. Lookup latency remains.

Gameplay QA found and fixed another input defect: immediately after closing
Reports, Play could remain disabled until the next HUD refresh, losing a quick
click. UI-host ownership/gate changes now refresh HUD controls synchronously.
A regression checks enablement without waiting for another frame; paired live
input verifies that the immediate click submits Resume and DF actually runs.

New tests click the actual build-menu hierarchy and controls. A running fortress
completed four wall tiles. A paused fortress cancelled a pending lookup, placed
two beds through expanded item selection, Keep building and Last, visited Reports,
resumed, and naturally completed both beds after 600 observed simulation frames.
Furniture tests seed two beds; the wall test retains ordinary stock. A separate
running-stock test confirmed the native shortage display while the seeded bed
was already in a DF job. An occupied-site case was retained: DF suspended a bed
job with its announcement "Item blocking site." This is not counted as completed
construction; clear-floor placement completed. These are targeted QA passes,
not proof of every recipe, viewport, long-session state or gameplay system.

Evidence: `fixtures/construction/material_candidates.json` →
`busy_gameplay_qa_reference`; `build/qa/construction-busy-corrected` and
`build/qa/gameplay-hud-dismissal`. Live runs are `passed_with_known_issues` for
pinned engine diagnostics. Earlier harness failures and script preflight failure
are retained, not passed off as product successes. All owned sessions closed
without saving, preserving the existing source manifest; no new save/game clones.

RC4's exact package passed local installation/restoration, fresh-asset startup
and live GPU smoke (`passed_with_known_issues`):
`build/release-0.1.0-rc.4/validation.json` and
`build/package-smoke-rc4-20261003-084921`. This post-package status update
supersedes the bundled document's in-progress wording. Earlier
release executables remain immutable. Retained RC3/RC2 defects and clean-machine
validation requirements below remain applicable.

## Construction gameplay follow-up: 0.1.0-rc.3

RC3 fixes the running-game material picker failure reproduced against RC2.
Native DF stops simulation during material selection. DF3D now acquires a
confirmed semantic pause before material lookup and retains it through the
placement receipt. Cancellation or confirmed placement restores a previously
running fortress. A pre-existing pause, newer player/Reports pause, native
interruption, changed session or unknown command outcome prevents unsafe resume.
There are no native-widget runtime reads or replacement visible strings.
The existing two-click construction gesture is unchanged; it was not the
cause of the reproduced failure. A lost connection can leave DF paused rather
than issue an unowned resume. Picker loading remains slow: 1627 ms in the
ordinary-stock four-tile capture; the poll interval is now 50 ms instead of 250 ms.
This is an open performance defect, not a native-parity acceptance decision.

Regression evidence: `fixtures/construction/material_candidates.json`
`running_picker_reference`. Native and viewer probes use the same existing
protected source without saving. Running-game cancellation/reopening and a
single wall completed naturally; four individual material clicks placed four
walls, all naturally completed 500 simulation frames after observation began.
Live status is `passed_with_known_issues` (documented Godot shutdown diagnostics).
Targeted guard/controller/input checks and root CTest pass; the prior controller
poll-timing assertion was corrected for the new interval. Evidence is in
`build/qa/construction-running-final` and
`build/qa/construction-running-poll-correction`. The other RC2 feature evidence
below is baseline evidence, not a claim that every workflow was revalidated.

RC3 is packaged and its exact artifact passed local installation/restoration,
fresh-asset startup and live GPU rendering (`passed_with_known_issues`). Evidence:
`build/release-0.1.0-rc.3/validation.json` and
`build/package-smoke-rc3-20261002-232113`. This is a post-package status update;
bundled ENGINEERING retains the earlier in-progress wording. RC2 and
RC1 executables remain immutable. Neither this follow-up nor previous local
smokes establish clean-machine/account or secondary-drive compatibility.
Reports initial-off Pause on new remains explicitly accepted. The retained
construction/native-copy/navigation and visual issues listed below still apply.

## Feature release candidate: 0.1.0-rc.2

**Construction gameplay blocker reopened (2026-10-02):** the maintainer's ordinary
running-game material-selection failure reproduced in
`build/construction-player-running-repro-20261002-225721`: the picker took 1772 ms,
then Place rejected an unavailable selected item and silently returned to placement.
The matching paused case passed. Native capture
`build/construction-native-running-20261002-230247` establishes that opening the
material picker stops simulation frames (90 -> 90 over 60 UI frames), with the
explicit pause flag still false; cancellation resumes progression. RC2 omitted
that temporary simulation hold. The immutable RC2 package still contains this bug;
controlled earlier construction tests do not establish normal running-game usability.
The RC3 source fix and ordinary-inventory verification are described above. Do not call the immutable RC2 package ready.

RC2 exposes Reports/alerts and construction across the native build catalog.
Its exact package passed local installation/restoration, fresh asset loading and
live GPU rendering (`passed_with_known_issues`). It has not been published. RC1's
artifact remains unchanged. Exact artifact/evidence: `build/release-0.1.0-rc.2/validation.json`; checksums are
in the adjacent `SHA256SUMS.txt`. Clean-machine/account and secondary-drive
validation remain outstanding. This status update follows packaging; the artifact
retains its original source-input manifest. Construction covers furniture, workshops, furnaces,
traps, machines, roads, tracks, stairs and reinforced walls, including the native
material modes and applicable orientation/options. Reports covers notification
entries, tabs, unit histories, scrolling, recentering, dismissal and running-game
refresh/pause behavior. Evidence is retained in the existing family fixtures.

Maintainer-approved simplification: Reports Pause on new starts off for each
fortress session and remembers explicit toggles during that session. The
maintainer accepted this on 2026-10-02 ("Player can pause"). Native initialization
matching is no longer an RC2 blocker; explicit on/off effects are live verified.

Retained defects for this cut (not permanent product departures):

- Some construction placement refusals lack native explanatory text. Invalid
  placement is refused; internal diagnostic prose stays hidden. Native error
  presentation remains a defect, not permission to invent replacement copy.
- Cold or unusual material-navigation states can refuse otherwise eligible
  stock. Captured negative/unreachable navigation and a cold Carpenter admission
  anomaly remain unresolved; ordinary verified family selection paths work.
- Reinforced Wall Closest produced one different native reinforcement-bar group
  across equivalent fresh captures. The later exact-input run passed, but the
  inconsistent choice remains unresolved; failed evidence is retained in
  build/construction-reinforced-main-20261002-222343.
- Small panel/frame spacing and captured minimap footprint differences remain.

Verification limits: maximum aggregate Reports heap use and arbitrary viewport
sizes are not live accepted. Snapshot limits fail closed at 32 MiB/65,536 entries;
ordinary, long-text, paging and recovery paths have separate evidence. Modded
custom recipes, machine operation, workshop production and trap triggering are
not established by construction-completion tests. These limits do not remove
project requirements. Packaged save-and-close remains excluded; closing the
viewer sends no save and leaves DF running. Clean-machine release validation
is separate from the developer-machine package smoke test.

## Prior release candidate: 0.1.0-rc.1

This cut targets verified HUD corrections and the existing exposed viewer/tool
baseline. Reports/alerts and the new native Options launcher remain gated for
this release; their project requirements and retained implementations remain open.
Save-and-close is excluded because the old close dialog called the retired implicit
SaveReturn API. Closing the packaged viewer now requests viewer exit only, without
submitting a save or terminating DF. This preserves the existing separate-process
release lifecycle and adds no substitute native UI copy. Source Play.cmd ownership
is unchanged. Release scope and remaining gates are tracked in build/notes/pm/TRACKER.md.
This is a candidate under validation, not an accepted or published release.

### Next feature release: Reports/alerts and full construction

The next candidate adds Reports/alerts and full construction. RC1 remains an
immutable baseline. Launchers are exposed for RC2 final verification;
no package containing these features has been published.

Construction now has exact material snapshots for 56 recipe definitions, alongside
28 single-item families and the terrain/track workflows. Native material names,
identities, distances, quantities, Last validity and actual reservations are
retained in `fixtures/construction/material_candidates.json` and the family
fixtures. Native navigation and widgets are offline references only. Runtime
queries use owned semantic facts, independent navigation and pinned revisions.

Recent completed main-scene workflows include Dirt Road (temporary building
retires into FurrowedSoil), Paved Road, Horizontal Axle, Rollers, Soap Maker,
Screw Pump, Millstone, siege workshops, upright weapons and Weapon Traps.
Construction completion does not establish machine power, minecart operation,
workshop reactions or trap triggering; those are separate project requirements.

Weapons use the native 1-to-10 picker with explicit Done. Closest takes one item
from each displayed group, capped at ten; the former one-item-total assumption
was a defect and is fixed. Three- and twelve-group native cases establish that
rule. Last selects one matching ordinary item; decorated-only Last can remain
unselected. Both main-scene five-weapon structures complete naturally with exact
native inputs. The Done control maps native confirmation art; small frame and
panel spacing differences remain.

Reinforced Wall uses two building materials plus one metal bar per tile. Its
material admission uses full-width walkability tags at the minimum rectangle
corner and outer perimeter, including unmarked ground stock. This differs from
ordinary terrain construction. Native Closest carries its group cursor between
stages; selected bars disappear from the following metal-bar picker. Sixty native
admission cases, nine native material scenarios and 18 installed paired placements
cover quantities, group names/order, distances, overlap and exact reservations.
The shared request validator now permits its material anchor. Actual viewer
manual/Closest two-by-two placements, cancellation, subtraction and both material
stages complete eight reinforced tiles by frame 4200 with the native primary and
secondary materials and reinforced flags.

Current verification: construction adapter 73 tests pass; material/draft/Closest
engine checks pass; root CTest and the rebuilt bridge/extension pass. Live runs
with only documented Godot diagnostics are `passed_with_known_issues`. All owned
sessions close without saving and preserve the protected source manifest.

Reinforced geometry now matches 33 native cases. Ten replacement cases establish
completed floor/ramp admission, completed stair/wall refusal, and reuse of queued
construction jobs with their original inputs. Final local Reports/lifecycle and exact-package checks passed. Clean-machine
validation remains outstanding. The maintainer has accepted the simple initial-off,
session-persistent Pause-on-new preference; native initialization matching is not
an RC2 blocker. Track retained defects in `build/notes/pm/TRACKER.md`.

Construction material selection uses owned semantic snapshots, pinned revisions
and independent navigation. It never reads native widgets or pathfinder scratch
at runtime. Different recipes have distinct material-admission rules: the eight
verified furniture types use the placement tile's full-width walkability group,
except Statue, which uses cardinal neighbors. Bridge uses cardinal perimeter
groups; Windmill and standard magma buildings use footprint navigation seeds.
Do not extend those rules to another family without native evidence.

The eight furniture types are Bed, Chair, Table, Coffin, Cabinet, Box, Statue and
Slab. Their material snapshots now supply exact candidate identities, descriptions
and navigation costs. Place validates those identities against the pinned group
before reservation. Their native one-item picker has expansion and individual
selection, framed icons, no All/None/subtract controls, and distance at relative
column320. Full native headings differ from menu labels: Chair uses Seat, Coffin
uses Burial Receptacle, and Box uses Container. Group labels are plural even for
singletons; Statue group copy omits the depicted subject. See
`fixtures/construction/furniture_material_copy.json`. Bed exact selection and
Coffin Closest have main-scene natural-completion evidence. Management51 adds
standalone item identity: decorated furniture and artifacts are distinct from
ordinary same-material groups and require their exact item ID. Sixteen improved
furniture rows and an actual artifact coffin match native names, grouping,
distances and job reservations. Main-scene pointer selection naturally completes
both an improved bed and that artifact coffin. Standalone rows have no expander;
artifact copy comes from its untranslated name, not its readable description.
Other recipe families' standalone-item semantics remain unverified. Legacy
aggregate families retain their existing grouping until their exact-item migration.

Fourteen additional single-item families now use the same exact snapshot and
reservation path: Traction Bench, Bookcase, Display Furniture, Offering Place,
Instrument, Door, Hatch, Cage, Chain, Armor Stand, Weapon Rack, Wall Grate, Floor
Grate and Floodgate. Ninety-eight native admission cases establish full-width
site groups: Hatch, both grates and Floodgate use cardinal neighbors; the other
ten use the placement tile. Twenty-eight installed ordinary selections and
32 improved-item selections match native names, row order, identities, distances
and exact native job reservations. Bookcase and Hatch also naturally complete
through main-scene pointer selection. Native headings and item frames are mapped;
All22 single-item families have native Closest reservations, manual/Closest
zero-supply copy and cancellation-to-map evidence in `single_item_options_reference`.
Instrument has no workshop hint. Placement uses full native building names,
including Seat, Burial Receptacle, Floor Hatch and Restraint. Their evidence is in the `additional_single_item_*` sections of
`furniture_material_copy.json`; these are milestones within full construction.
Bookcase and Hatch main-scene flows expand the framed item rows, cancel to map,
reopen and choose Closest; both naturally complete with the native oracle's exact
item. Native Keep-building captures also correct the Bridge/Pressure Plate
forced-close exception: checked placement stays open, and Pressure Plate resets
its trigger options. Native Last appears after a matching material is remembered;
Bridge's direct Last control is restored. Management52 supplies an explicit generic
Last-material label; old recordings cannot invent it from a decorated display name.
Native ordinary/improved captures cover all22 single-item families. Last remembers
the generic class, and improved/artifact Specific rows still require an explicit
selection. The artifact coffin also has native reference evidence. Bookcase Last/Keep
has main-scene natural completion, and32 installed improved placements retain the
explicit Last labels. Six more recipes now use this path: Nest Box, Hive, Quern,
Animal Trap, Glass Window and Pressure Plate. Native42 admission variants establish
Animal Trap's cardinal-neighbor groups; the other five use the placement tile.
Twenty-four installed ordinary/improved placements match native copy, identity,
ordering, distance and actual reservations. Main-scene Pressure Plate and Quern
Closest/Last/Keep flows naturally complete; Pressure Plate preserves the submitted
water trigger and resets next-placement options. Its native full-height options pane
remains present with creature triggers off, including the refreshed main-scene capture. Native picker-side captures show
that the target tile selects the side, not precise pointer movement within it.
The viewer projects its own target tile, and Quern's left picker is live-verified.
Other recipes' material admission and Last behavior remain unfinished.

Other retained construction evidence:

- `bridge_placement.json`: native/installed placement, perimeter admission,
  navigation ordering, exact-item picker and main-scene natural completion.
  Bridge inherits Closest and Last from visible Wall controls; both have main-scene natural completion with
  native expected items. Bridge assigns selected IDs in ascending order and
  remembers the first item, including mixed selections. Native checked Keep resets
  East-facing and retracting bridges to West for the next placement. The controller
  now follows that rule; an actual East-facing bridge naturally completes through
  the viewer while its retained placement resets to West. Partial Last preselects
  remembered supply and waits for explicit replacement. Normal cancellation and
  manual/Closest shortage copy match.
  The earlier hidden-footer claim is superseded by `native_placement_hover_correction`:
  native Bridge has the left placement pane alongside its direction pane.
  Hidden-desktop oracle captures must feed mouse hover/tracking before rendering;
  absence of a panel in an unfocused capture does not establish native layout.
- `stairs_placement.json`:21 native/installed cases verify carved endpoint
  connection preservation and single-level refusal. Materials requests use a
  full volume plus a semantic last-corner material anchor (management50). Main-scene PageUp selection
  and natural three-level completion are verified. An unfinished one-level anchor
  does not submit Preview. Six additional native/installed cases cover reversed
  endpoints,2x2x3 volumes and rebuilding real completed stairs/floors, including
  matching stair shapes. Seventy-two paired material-admission cases verify full-width
  cardinal neighbors at every selected level plus the final endpoint center;
  forward/reverse endpoints differ. Volume and anchor participate in snapshot
  identity and paused Preview invalidation. Eleven paired native/installed picker
  cases verify exact identities, names, ordering and navigation costs; distance
  seeds cover the selected XY footprint at the FIRST gesture elevation. Actual
  main-scene individual clicks produced three naturally completed stair levels.
  Zero/partial shortage copy and normal/shortage Escape are mapped from native
  captures. Fifteen native Last cases establish cross-recipe Wall history,
  partial preselection and retained preference when the material is unavailable;
  controller regressions cover the corrected behavior. Fourteen installed option
  cases match native item assignment per tile: sort the selected set by item ID,
  then visit z/x/y, keeping wire masks x-fast. Mixed Last follows the final assigned
  item. Main-scene Closest naturally completes a column; a subsequent Last gesture
  creates new jobs and naturally rebuilds the completed column.
- `farm_placement.json`: first-anchor admission, irregular extent masks and
  main-scene natural completion; invalid cells are not a filled rectangle.
- `windmill.json`: ground/machine attachment, four-log selection, Closest and
  natural completion. Broader power operation remains separate.
- `magma_placement.json`: four standard magma recipes, placement, material order,
  exact selection, Closest and natural completion. Operational captures verify
  magma access, not actual reaction execution; custom magma recipes remain gated.
- `connected_track.json` and `material_candidates.json`: semantic routing,
  placement planning, exact selection, paging, and natural flat/ramp completion.
  Additional terrain replay covers36 brook/tree/boulder/pebble cases through the
  real Lua reader. Track is now available in the staged catalog when all semantic
  services are installed. Main-scene natural ramp completion passes through that
  catalog entry without a harness support override; the public construction
  launcher is exposed for RC2 verification; full construction remains unfinished.

Track's callback regression requires the separately built MSVC target
`df3d_track_callback_test`: run `python tools/test_track_shape_callback.py <exe>`.
This is explicitly manual in the QA manifest; the ordinary MinGW build does not
execute it. The superseded material callback and its comparison-only tests have
been removed. The shared core regressions are
`worldmodel_tests` and `track_path_native_fixture`.

Reports running refresh has main-scene enabled/disabled auto-pause evidence in
`fixtures/reports/pause_on_new.json`. Native initialization captures contain
noncanonical boolean bytes and inconsistent reopen state. DF3D initializes its
owned boolean off per fortress epoch and retains explicit toggles within that
session. The maintainer explicitly accepted this simplification on 2026-10-02.
It is not a claim of native-parity evidence. Explicit toggle behavior is verified;
do not reopen initialization matching as a release blocker or read native widgets.

Track Closest may differ from native stale-distance ordering under the narrow
maintainer exception below. Current defects include cold-first-preview routing,
and incomplete furniture icon composition (notably bed bedding and generic group
icons). Manual natural-ramp exact selection works. These limitations do not remove
project requirements. Generic construction material semantics, remaining recipe
families/options/lifecycle and Reports capacity/lifecycle acceptance still require
release review; no package or full-feature completion is claimed here.

# Engineering guide

Agent-maintained reference for building, running, verifying and releasing DF3D.
`README.md` is reserved for the maintainer to write; keep technical maintenance here. Architecture
constraints and contributor rules live in [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md),
and supported dependency builds live in [PINS.md](PINS.md).

## Project overview and current scope

DF3D is an experimental 3D frontend for Dwarf Fortress. Explore your fortress in Godot while
Dwarf Fortress runs the simulation, with DFHack connecting the two.

It has three pieces: the **bridge** (a DFHack plugin running inside Dwarf Fortress that publishes
game state), the **core** (`schema/` and `worldmodel/`, engine-independent C++), and the
**viewer** (a Godot project plus a native extension).

**Status.** The viewer loads a fortress from a running game and renders its terrain, creatures,
items and animations; you can pause, unpause and save. The toolbar exposes Dig, Chop trees, Gather
plants, Smooth, Remove, Inspect and Inspect buildings, plus read-only Residents, Work Details and
Work orders panels; build, stockpile and zone editors exist but are hidden, and other management
screens are not implemented. Windows x64 packages bundle the viewer and a bridge setup launcher;
source builds are also supported. Both require the pinned Steam release of Dwarf Fortress.

## Viewer preferences

The upper-right gear opens the viewer preferences. Escape opens
this menu from normal play and closes it again; active panels, designation tools,
and captured Walk input retain their back/cancel behavior first. Holding Escape
does not repeatedly toggle the menu.

Display contains saved Windowed and desktop Borderless fullscreen modes, with
standard windowed resolution presets. Apply previews the choice; Keep changes
persists it. Revert, closing Settings or a 15-second timeout restores the previous
actual window mode, size and position. Borderless fullscreen uses desktop resolution;
windowed sizes are clamped to the current screen work area. Startup restores them
only after an explicit display selection. Automatic interface scaling (the default), manual interface scale,
targeting grid, visual style, creature scaling
and combat effects are independent. Disabled manual scale controls cannot change
the automatic preference through value-change signals. Camera contains view mode and movement speed. Audio contains
mute and the existing four volume controls. Tabs keep the menu compact, with
independently scrolling contents and a fixed Close button. Preferences continue
to use the existing presentation/audio configuration stores. This viewer-owned
surface is an explicit exception to native gameplay UI parity; it does not expose
unfinished native Options routes. F10 remains the interface recovery shortcut.

Automatic scaling uses the native default 190x64 target grid with whole-pixel
8x12-derived cells, independently of world zoom. Manual sizing supports 75-400%
and fits small windows. Existing non-default manual sizes remain manual; legacy
default-size preferences gain automatic sizing. The HUD, minimap, information,
construction, hover and inspection canvases share both scale axes. Captured native
geometry is recorded in `fixtures/hud/automatic_scale.json`; `hud_scale_test`
checks those sizes, manual input coordinates and preference persistence.

The main HUD retains native visible slots independently of route availability:
all eight information icons, Stocks, the four bottom action groups, map controls,
and military/world buttons keep their native footprint. Unfinished routes remain
inert, per the maintainer's visual-parity direction. The upper-right gear opens
DF3D Settings; the separate bottom-right Settings text button is removed. Help
remains unwired. DFHack logo/Sitemap adornments are omitted at the maintainer's
request. No extracted artwork is packaged.

`native_hud.gdshader` reconstructs each installed 8x12 UI cell independently with
bounded, byte-rounded Lanczos3 at fractional scales and nearest at integer scales.
The bitmap font keys magenta to transparent black, preserving native straight-alpha
filtering; neighboring glyphs cannot bleed into one another. Text tint is applied
before reconstruction so native colored-edge overshoot is preserved. The moon
uses a Sprite2D at physical-pixel coordinates to avoid Control rounding before
canvas scaling. One shared material
also covers arriving notifications and rebuilt tool rows. This canvas path is
independent of world color postprocessing. Protected DF53.16 evidence in
`build/notes/visual-polish/native-20261013-114704/w1920h1080.png` establishes the
1920x1080 anchors and source filtering. `build/notes/hud-fidelity/` contains the
GPU comparison and full-scene replay. The replay transcribes native header values
only in its ignored harness; product labels remain driven by session data.


## Windows package

Run `DF3D-0.1.0-windows-x64.exe`, select your installed Dwarf Fortress, and use **Set up bridge**
with the game closed. The launcher discovers Steam libraries and also accepts `DF3D_DF_PATH`
or a folder selected with Browse. Godot and the required runtimes are included.

Setup verifies file hashes and backs up replaced files under `%LOCALAPPDATA%/DF3D/backups`.
**Restore bridge files** reverses setup, refusing to overwrite files changed afterward.
Extracted application files and logs are under `%LOCALAPPDATA%/DF3D`.

The release launcher starts DF and the viewer inside one Windows kill-on-close
job. It refuses to attach to an existing DF instance. Either child exiting ends
the owned session; launcher failure and partial-startup errors also clean it up.
The Settings menu includes **Exit game**, and the window close button uses the
same native DF quit-without-saving confirmation (installed frame, bitmap font and
Quit/Cancel artwork). Unsaved progress is discarded only after explicit confirmation;
known pending saves/operations disable confirmation until they settle. Exit does
not initiate a save. Abrupt process failures still terminate the owned session.
The native DF window remains available during play. Explicit developer `-Attach`
sessions retain their separate contract and never terminate an unrelated game.
Existing packaged RC5 binaries are unchanged until a new package is built.

Run `python tools/release/test_lifecycle.py` to compile and test Windows process
ownership using stand-ins: normal cleanup, failed startup, owner crash, duplicate
cleanup and unrelated-process preservation. `release_close_test` covers exit
confirmation/cancellation, pending saves and duplicate requests; `fortress_hud_test`
covers Settings. These checks do not exercise a real fortress save or certify a
new packaged release.

## Build from source

### What you need

- Git, and CMake 3.20 or later.
- MSYS2 with `mingw-w64-x86_64-gcc` and `mingw-w64-x86_64-make`: builds the core and the Godot extension.
- Visual Studio 2022 C++ build tools with the Windows SDK: builds the DFHack fork (MSVC is
  required for ABI compatibility with the game).
- Strawberry Perl with `XML::LibXML`: DFHack's df-structures code generation.
- Python 3.12: the test suite.
- Dwarf Fortress 53.16 and Godot 4.7.2 (editor build), both from Steam.
- PowerShell 7 (`pwsh`) or Windows PowerShell 5.1.

The exact supported builds are listed in [PINS.md](PINS.md). DFHack and godot-cpp are pinned Git
submodules; a source ZIP does not include them.

### Get the source

Run everything below in one PowerShell session from the repository directory. The path assignments are
the standard install locations; edit them if yours differ:

```powershell
git clone --recurse-submodules https://github.com/UncertainCat/DF3D.git
cd DF3D
$mingwBin = 'C:\msys64\mingw64\bin'
$godotExe = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$dfPath = 'C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress'
$env:Path = "$mingwBin;$env:Path"
```

The same paths can be set once as environment variables instead: `DF3D_DF_PATH`, `DF3D_GODOT` and
`DF3D_MINGW_BIN` are read by the viewer, the QA gate and the smoke scripts.
`Play.cmd` discovers DF and Godot across Steam libraries when paths are omitted;
`tools/build_bridge.ps1` discovers DF before installing. Explicit command-line paths take
priority over environment variables, then discovery. An invalid override fails rather than
silently selecting another installation. `DF3D_STEAM_ROOT` can select the Steam root whose
`steamapps/libraryfolders.vdf` lists your libraries.

### Build the core and viewer

The core and its tests need only Git, CMake, MSYS2 and the submodules.

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j
ctest --test-dir build --output-on-failure

cmake -S presentations/godot/extension -B build/godot-ext -G "MinGW Makefiles" `
    -DCMAKE_BUILD_TYPE=RelWithDebInfo `
    "-DCMAKE_CXX_COMPILER=$mingwBin/g++.exe" `
    "-DCMAKE_MAKE_PROGRAM=$mingwBin/mingw32-make.exe"
cmake --build build/godot-ext -j
& $godotExe --headless --editor --path presentations/godot/project --import --quit
```

The import step registers the extension's native classes; run it after every extension build,
with Godot closed.

### Build and install the bridge

Register DF3D as a DFHack plugin (once), then with Dwarf Fortress closed build and install the
DFHack fork and DF3D plugin into your game installation (`-SkipInstall` builds only):

```powershell
New-Item -ItemType Directory -Force external/dfhack/plugins/external | Out-Null
'add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../../../bridge/plugin" df3d-plugin)' |
    Set-Content -Encoding ascii external/dfhack/plugins/external/CMakeLists.txt
./tools/build_bridge.ps1 -DfPath $dfPath
```

## Play

With Dwarf Fortress closed, start the viewer and choose a fortress in the selector; it opens paused:

```powershell
./Play.cmd -DfPath $dfPath -GodotExe $godotExe
```

For Steam installations, `./Play.cmd` alone discovers both paths. Run
`./Play.cmd -CheckInstall` to print the resolved paths and check that the executable,
extension and bridge files exist, without starting the game or changing preferences.
This checks file presence only; version compatibility and runtime loading require the
connection check below.

This launcher starts a temporary game session on a hidden desktop. **Closing the viewer or
launcher ends that session without saving**, so save through Settings first. Sessions also end
after 120 minutes by default; pass `-MaxMinutes` to change that.

### Recovering by hand

A session rewrites `prefs/init.txt` in the Dwarf Fortress folder (backup: `prefs/init.txt.df3d-backup`)
and adds `dfhack-config/init/dfhackzzz_df3d_menu.init` (`enable df3d`), reverting both on exit.
If a session is interrupted, the next launch restores the backup unless you changed settings since.
To recover by hand, copy the backup over `prefs/init.txt` and delete the menu init file while the
game is closed.

### Attach to a running game

To use a game you have already started, run `enable df3d` in its DFHack console, then attach:

```powershell
./Play.cmd -Attach -DfPath $dfPath -GodotExe $godotExe
```

Attach mode requires exactly one running Dwarf Fortress process. It preserves the game's pause
state and leaves the game running when you close the viewer.

## Tests and known problems

Recorded mirror fixtures are stored as deterministic `.df3dfix.gz` archives with
sibling manifests under `fixtures/recorded`. The QA gate verifies their hashes,
expands them and checks every snapshot's schema before scheduling dependent tests.
Run `python tools/qa/expand_fixtures.py` before standalone fixture checks. Consumer
validation remains authoritative; the gate's bounded header check only detects
missing or incompatible recordings early.

After a breaking snapshot change, capture fresh semantic data through the protected
lane and update the archive hashes, schema, camera/clock metadata and provenance
together. Never invent missing facts to migrate an old recording. Scene tests and
smoke tools read the manifest view instead of hardcoding coordinates from an older
fortress. The paused fixture establishes replay behavior, not running-simulation,
deep-pit visibility or complete native UI acceptance.

Connected Track remains disabled. The independent world-model search and piece
planner have fixture coverage, but production terrain eligibility, semantic bridge
placement and controller integration are unfinished. Native DF behavior is the
authority; the existing generic construction validator is not suitable for Track.
Native viewscreens, buildreq and cached path state are oracle inputs only, never
runtime inputs. Carved-track runtime routing remains unchanged.

`fixtures/construction/connected_track.json` retains bounded semantic evidence and
provenance from protected DF53.16 captures; raw captures stay under ignored build
output. Accepted captures verify unchanged owned source saves. Synthetic terrain,
copied walkable groups and bounded instant-build/one-tick settling are fixture
setup, not evidence of natural construction, hauling or minecart traversal.

`wm::routeTrackPath` implements destination-seeded three-dimensional search with
native frontier ordering, the 80K frontier cap, directed edges and linked ramp/top
marking. Callers supply semantic eligibility, forward-edge and linked-tile rules
plus inclusive loaded bounds. Wider arithmetic protects int32 boundaries.
`routeFlatTrackPath` delegates with a single-level bound and rejects unequal z.
`track_path_native_fixture` compares 342 retained flat rows and 154 elevation and
directional rows, including repeated observations. Controlled fixture callbacks
do not establish general terrain eligibility. The linked-tile bookkeeping resolves
the earlier two erroneous upper-level detours; the older 18/20 scratch comparison
is diagnostic history, not the current implementation result.

`wm::trackPathPieces` converts a validated path and independent ramp terrain facts
into cardinal connections and ramp flags. `wm::planTrackConstruction` produces a
pure Create/Update/Unchanged plan without reservations or mutations. It preserves
separate expected pending-job IDs/connections/shapes and terrain connections/kind/
shape for later safe-point validation. It rejects invalid routes, duplicate or
invalid snapshots, shape conflicts and pending masks missing terrain connections.
The last condition is conservative pending native evidence. Ten native placement
cases and thirteen invalid planner inputs are covered, alongside piece validation.

Native placement evidence establishes the following controlled cases:

- Initial flat and east-facing ascending paths request four materials and create
  four jobs, including TrackRampEW on the ramp; Keep-building false returns to map.
- Pending flat or ramp crossings retain the crossing job ID, merge connections
  and request materials only for new jobs. An endpoint join updates EW to NEW.
  Identical pending overlap opens material selection; selecting the captured
  material row returns to map with the four job IDs/subtypes unchanged. Inventory
  reservation and stack effects were not measured.
- Completed or carved track gets new replacement jobs even on identical overlap;
  old terrain/material fields remain unchanged until completion. Pending
  replacements over completed track merge in place. Completed ramp crossings
  create a TrackRampNSEW replacement. Replacement completion is unverified.
- Entering and cancelling the tested crossing material selection does not change
  pending jobs; Escape returns to map. This does not cover every material lifecycle.

Terrain eligibility evidence remains separate from production implementation:

- The 88-row tile/liquid matrix tests endpoint and intermediate positions. Tested
  walls/fortifications, water depth above1 and any magma reject endpoints and cause
  detours. Tested floors, ramps, stairs, shrubs, saplings and open shapes permit
  paths; seeded shape tags do not cover full plant/object state.
- Hidden endpoints allow routes while hidden intermediate tiles are bypassed.
  Native hover text says “Hidden, cannot build at this location”, yet the controlled
  hidden-start and hidden-end placements create four jobs after material selection.
  The start remains hidden afterward; endpoint post-placement visibility was not
  sampled. Do not turn the hover warning into a claimed refusal. Natural hidden
  terrain remains unverified.
- A pending Support (occupancy1) and completed Support (occupancy2) reject endpoints
  and cause detours. This is not evidence for every building family.
- The 126-row above/below matrix allows direct routes across seven center shapes
  with wall/floor/open neighbors above and below. Horizontal floor neighbors remain;
  isolated support and actual job placement are untested.
- A fixture Stockpile and overlapping Civzone have occupancy2 and routes avoid
  their tile. The separate zone-alone capture permits direct endpoint/through
  routes with occupancy0. Its 32 samples across11 pre-existing stockpiles all have
  occupancy2 and resolve to matching Stockpile IDs, corroborating fixture occupancy.
  Routes on those saved stockpiles and their creation histories were not sampled.
  See `terrain_eligibility.zone_alone_and_existing_stockpiles`, captured in
  `connected-track-zone-alone-20260930-174054`; no zone placement effect is claimed.
- `map_edge_previews` retains 72 endpoint-checked direct paths from
  `connected-track-map-edge-20260930-174846`: all four boundaries, target depths
  0..8, with subterranean false and true. Anchors are nine tiles from each edge
  on prepared building-free floor strips. A five-tile restriction traced in a
  native building helper does not apply to these previews; do not impose it from
  disassembly alone. `map_edge_reverse` adds 72 direct routes starting at depths
  0..8 toward depth9; 24 confirmations enter material selection but report no
  access. `west_edge_placement` separately verifies ten actual jobs from x9 through
  x0 on nonsubterranean floor, ten materials requested and return to map. That
  capture moves fixture blocks beside the route and copies their walkable group;
  natural hauling, completion, other-edge job effects and z boundaries remain
  unverified. All follow-up owned source saves are unchanged.

`wm::trackSiteEligibility` now classifies semantic shape, occupancy, visibility and
liquid facts as Eligible, Ineligible or Unverified. Hidden endpoints are allowed;
hidden intermediate tiles are not. PendingConstruction identifies a stage-zero
construction job; it may have no track connections yet. Occupied non-construction
buildings are BlockingBuilding under the verified native occupancy branch.
Unresolved occupancy and transient construction stages remain Unknown. Unknown shapes and malformed liquid data
remain Unverified, not native refusal. Callers must not use this result alone to
authorize placement: directed movement, current job stages and material effects
remain separate checks. The bridge reader supplies these facts at safe points.
The fixture regression now uses this predicate to reproduce 224 retained native
terrain/liquid/occupancy routes, including exact detours, alongside the previous
342 flat and154 elevation cases and placement-planner checks.
`wm::trackMovementConnected` and `wm::trackLinkedTile` now implement the directed
ramp/support/clearance and linked-partner rules from semantic movement facts.
The elevation regression uses these world-model helpers and the site predicate;
it no longer calls the carved-track schema helper through a test-only adapter.
Movement and site eligibility remain distinct, and callers must establish complete
terrain/clearance inputs before interpreting a route as authoritative. Carved
runtime routing is unchanged. Full core19/19 passes in
`build/qa/track-movement-core-test.log`; additional missing-input, invalid-step and
int32 limit checks pass in `track-movement-bounds-test.log`, with no build warnings.
`wm::routeTrackConstruction` composes eligibility, directed movement and linked
marking over a stable semantic lookup, sampling each coordinate once. Bounds must
describe the actual map rather than a cropped resident window. Missing loaded
tiles, unverified site facts or missing clearance needed for a ramp transition
return UnverifiedTerrain with no path, even if another explored route exists.
Confirmed blocked clearance remains NoPath; known flat routes do not require
irrelevant clearance facts. This distinction is internal, not new visible copy.
The native terrain/elevation regressions now use this combined entry point.
Core19/19 passes in `build/qa/track-construction-route-test.log`; additional
unknown/clear/blocked ramp-clearance checks pass in
`track-construction-route-clearance-test.log`. Neither build emits warnings.
Integration requires independent native movement facts: brook beds map to Wall
for display, while native ramp support is published separately. Movement helpers
now take explicit support/open facts; the combined routing API preserves unknown
values instead of inferring them from display shape. The site predicate likewise
requires native shape classification, not an unchecked display-tile copy.
Core19/19 passes in `build/qa/track-native-movement-facts-test.log`; the additional
known/false/unknown support regression passes in `track-support-facts-test.log`.
Terrain streaming already carries clearance/support/open movement flags, but not
general building occupancy or pending construction-job identity. A construction
semantic query must provide those facts before runtime integration; existing
carve-track designation bits are not pending construction jobs.
`bridge/plugin/construction_track.lua` now reads native map/building records into
semantic site facts without native UI inputs. It keeps raw shape, pending job
identity/connections and underlying carved/constructed track separate, and leaves
unclassified occupancy or unresolved dynamic clearance unknown. Stage-zero Track
jobs marked for removal are not accepted as compatible pending jobs.
Protected `connected-track-facts-reader-20260930-181103` checks eight native-created
flat jobs, nine seeded tile variants and fixture zone/stockpile occupancy, with
unchanged source saves; `semantic_reader` retains provenance and coverage limits.
Follow-up `connected-track-reader-ramp-20260930-181433` verifies that a pending
TrackRampNSEW replacement retains its own ID/mask15 while the underlying completed
ramp retains EW/mask12; settled upper track has no pending job. The protected
source save is unchanged. `semantic_reader.ramp_replacement` retains that evidence,
and a regression checks the reader against it. All32 offline adapter tests pass
in `build/qa/track-reader-ramp-adapter-test.log`.
The reader is embedded and injected into the construction closure and now supplies
connected Track Preview requests in source. Dynamic clearance and broader
job/family lifecycle still need live reader coverage.
Remaining work includes broader edge placement and occupancy/support rules,
production terrain extraction, bridge safe-point revalidation/material effects,
controller rendering and end-to-end protected placement acceptance. Core fixture
success alone does not authorize Track exposure or complete Construction parity.

Oracle instrumentation must feed and render native pointer events synchronously
and assert cached endpoints. Yielding between injection and render can invalidate
the mouse state. The stale-anchor probes and pre-settling completed-track capture
are excluded from acceptance. Fixture sections retain diagnostic limitations so
future agents do not mistake an oracle script's success for product acceptance.

Management protocol34 adds `ConnectedTrackOptions.destination` to construction
Preview, Place and Materials requests for `Construction:Track`. The ordinary origin
is the first point; endpoint order is preserved, including z and stationary drafts.
The request must use unit rectangle dimensions, zero direction and no retracting
flag. The destination is required for these intents and rejected for other actions
or definitions. The model codec and bridge Lua argument dispatch preserve it.
The source Preview handler now routes using the native reader and shared rules.
Material mutation and the controller remain unfinished; the catalog disables Track.
That change used `Local\\df3d_management_v34`. The current transport is
`Local\\df3d_management_v37`; older management peers cannot connect.

Management protocol35 adds optional `ConstructionMaterial.candidates`, carrying
stable item ID, native individual name and navigation distance in expanded-row
order. Absence means aggregate-only data, not a complete empty item list. When
present, the vector must match group count, have nonempty valid native text,
unique nonnegative IDs across the page and increasing (distance, ID) order.
The page is bounded to16,384 candidates independently of the512KiB transport cap.
The bridge producer must still fit the encoded page; the count bound does not
authorize oversized payloads. Typed model/Godot decoding and bridge encoding/Lua
parsing preserve this distinction. Eleven contract cases cover valid decode,
aggregate-only data and malformed candidates. Production Track Materials now
composes semantic route/plan, candidate collection and independent distances into
an owned snapshot. Epoch/endpoints and content revision identify retained pages;
reset invalidates them. Pages contain at most128 complete groups and use a
conservative384KiB byte budget within the512KiB envelope. Oversized groups and
unverified ordering fail without a partial candidate vector or invented copy.
Existing aggregate producers continue to omit the vector.

Protected `build/track-material-production-20260930-230230` verifies the actual
ConstructionMaterials request through bridge, model and Godot:33 ordinary groups,
60 exact item IDs/native individual names/distances, required count5, estimated=false,
and an identical revision-bound reread. Native generation/reservations, paused
frame0 and the owned source save remain unchanged. This is transport acceptance
on controlled flat terrain, not rendered UI, artifacts, hauling or placement
acceptance. The run is `passed_with_known_issues` for the pinned rendering-thread
warning; no other diagnostics. Candidate evidence retains the bounded result.
All34 construction adapter tests pass, including130-group paging, retained reads,
changed/stale revisions, reset and unverified ordering. Bridge build/install pass.
The earlier matching core/extension build and19 root CTest suites also pass.
The local construction draft now retains exact item IDs for complete candidate
snapshots. Group selection chooses nearest unselected candidates and deselection
chooses farthest selected candidates, both using highest-ID ties; expanded-row
selection keeps the requested ID and repeat clicks are no-ops. Remaining distance
is the minimum unselected cost, with no group resort. Draft invalidation clears
IDs and snapshots together. The engine regression replays558 recorded native
transitions plus exact farther-item selection, cross-group requirement caps,
repeat clicks, ownership and reset. Existing draft/material-view regressions pass;
all three runs report only the pinned rendering-thread warning. This verifies
local state, not rendered expansion or placement. The draft still refuses to submit exact choices until semantic placement exists.

Management protocol36 adds optional `ConstructionSelection.item_ids`. Presence
means exact identities; absence retains aggregate intent. Schema/model/Godot/bridge
preserve that distinction. Exact vectors require a positive per-selection snapshot
revision, count equality and nonnegative IDs unique across the request, bounded
to16,384 IDs. Godot rejects noninteger values before encoding. Request codecs cover
absence, explicit empty, identity/order preservation, stale revision shape, count
mismatch, negative/duplicate IDs, cross-group duplicates and the item cap.
The bridge rejects every exact-ID Place before entering aggregate reservation;
it cannot silently substitute a group member. Fresh semantic stale-item validation,
rendered expansion and actual exact placement remain unfinished.

Matching core, bridge and extension builds pass; all19 root CTest suites and35 Lua
adapter tests pass. Protected `build/track-exact-contract-20260930-231206` verifies
six malformed requests fail before send, two well-formed exact requests (Track and
Chair) reach rejected receipts with empty player-facing copy, and the ordinary
material response remains exact. Buildings, next building/job IDs, reservations,
native generation, pause frame0 and owned saves stay unchanged. The transport lane
and558-transition draft replay pass with only the known render-thread warning.
This is protocol/rejection acceptance, not exact placement acceptance.

Native assignment captures `build/track-material-assignment-20260930-231456` and
`build/track-material-assignment-reverse-20260930-231544` record selected item IDs
on each of five newly created Track jobs. Reversing the drawn route reverses world
positions assigned to ascending item IDs; changing group click order does not set
job assignment order in these cases. Both owned paused runs preserve the save.
No hauling, completion, ramps or pending updates are accepted by these captures.

`construction_track_placement_plan.lua` is a pure preflight helper embedded as the
fifth construction closure argument and connected to Track Place. It compares a retained snapshot and
fresh semantic facts captured at the same safe point as eventual commit, including
a canonical route/plan identity. It validates epoch, route identity, requirement,
per-selection revision, complete exact membership in both snapshots and group
identity; it rejects duplicate/invalid IDs and incomplete counts. It assigns globally
ascending IDs to Create pieces in route order, copying scalar plan expectations.
Update/Unchanged pieces consume no new item in the synthetic regression. Native
assignment replay,20 malformed/stale cases and output ownership pass in
`test_construction_track_placement_plan.py`, registered in the core gate. The material cache now owns a copy of every plan piece and a canonical ordered
identity covering position, action, building ID, connection and ramp expectations
for both pending jobs and terrain. This identity contributes to the material
revision; equal endpoints/material counts cannot hide changed plans. Adapter tests
change each of12 fields independently and confirm a changed revision, then restore
the original plan and confirm its revision. All35 adapter tests pass. The rebuilt
bridge passes protected transport regression `build/track-exact-contract-20260930-232107`
with exact native materials and unchanged world/save state, plus only the known
render-thread warning. That live run does not test changed-plan rejection.
The production collector now returns a separate fresh snapshot before any cache
replacement. Track Place compares that fresh result with the retained epoch/plan
and exact selected membership through the preflight helper. Refusal preserves the
retained snapshot; it cannot fall through to aggregate reservation. Adapter tests
verify fresh rescanning, changed-plan rejection and retained paging after refusal.
All35 adapter tests plus the native-assignment preflight tests pass.

Protected `build/track-preflight-integration-20260930-232448` exercises the installed
bridge: a complete five-item exact selection passes fresh preflight, an incomplete
selection fails it, and both return Rejected because commit remains disabled.
`placement_valid` records only preflight validity; Rejected is not a successful
placement receipt. No building/job/reservation/search changes occur; pause frame0
and the owned save are unchanged. The only engine diagnostic is the pinned
render-thread warning. Native construction/update commits, partial-outcome handling
and controller activation remain unfinished; this is not placement acceptance.

Protected `build/track-native-constructor-20260930-232720` compares native picker
jobs with semantic `dfhack.buildings.constructBuilding` results. After recording
five native jobs, the oracle removes only those owned stage-zero jobs and creates
five replacements using their exact item IDs, subtypes and positions. Native and
semantic job item IDs, roles and job-item indices match. Pause frame0 and the owned
save remain unchanged. This proves constructor parity for new flat Track pieces,
not production Place, pending updates, ramps, hauling or completion.

`construction_track_commit.lua` is the embedded sixth construction closure argument for an
already validated owned plan with an injected native operation. It distinguishes
complete, rejected-before-any-confirmed-write, partial and unknown outcomes.
It stops on the first failed operation, preserves prior confirmed creations and
updates, and never replays a callback. Exceptions or malformed native receipts
are unknown, not evidence of no mutation. Synthetic tests cover12 failure cases,
unchanged-piece skipping, counts and result ownership; the core gate includes them.
Management protocol37 now adds ConstructionOutcome(None/Complete/Rejected/Partial/
Unknown), confirmed `updated` count and one-based `failed_index` (-1 if unavailable)
to ConstructionState. `placed` still counts confirmed new jobs. None preserves
legacy producers without implying atomicity. Validation rejects conflicting status,
a rejected receipt with confirmed effects, a partial receipt without confirmed
effects, wrong actions and malformed bounds. Model/Godot decode preserve the fields.
The action service classifies Partial and Unknown, retains confirmed counts, and
permits no success continuation or automatic replay. Existing controller rejection
handling retains confirmed placement information and invalidates the draft.

Matching core, installed bridge and extension builds pass. All19 CTest suites and
35 Lua adapter tests pass. Twelve wire cases and action-service tests cover outcome
preservation, contradictory receipts and no replay; exact-selection and controller
engine regressions also pass. Protected `build/construction-outcome-contract-20260930-233420`
verifies typed Track Rejected outcomes in production transport with complete versus
incomplete preflight unchanged. World/pause/source save remain unchanged. Engine
checks report only the known render-thread warning. Partial/Unknown coverage is
synthetic in that contract run. Production commit acceptance below supersedes
that limited scope for new flat Track jobs and injected failures.

Production Track Place now runs fresh preflight and the native commit executor
synchronously at one safe point. It derives Track/TrackRamp subtypes from semantic
connections, resolves exact item IDs before writes and uses the accepted native
constructor. Update pieces validate the pending building ID, position, stage0, expected subtype,
removal state and single ConstructBuilding job before any write. They update only
the persistent construction subtype, preserving the native job and reserved item.
Unchanged pieces consume no new item. Complete,
Partial and Unknown receipts preserve confirmed new-job counts and the failed index.
Every attempted commit retires its cached selection; it cannot be replayed using
that snapshot. Confirmed changed tiles, and all planned tiles on uncertainty,
invalidate world presentation data. Helper/contract failures during Place are
classified Unknown rather than implying zero effects.

Protected runs `build/track-commit-integration-20260930-233931` and
`build/track-commit-reverse-20260930-234030` verify five native jobs in each direction:
exact item-to-tile assignments, subtypes, job-item roles/indices and only selected
item reservations. The reverse run confirms consumed-snapshot rejection creates
no duplicates. Runs `build/track-commit-partial-20260930-234137` and
`build/track-commit-unknown-20260930-234208` inject refusal/exception on constructor
call2. Both retain exactly one confirmed native job and stop further writes;
receipts distinguish Partial and Unknown with failed_index2. These are controlled
fault injections, not naturally occurring failure coverage. All four runs preserve
pause frame0 and owned source saves; only the known renderer warning is present.
35 adapter tests, pure executor tests and19 CTest suites pass; bridge build/install
passes. Ramps, hauling/completion, rendered expansion/controller and
stale-live selection changes still need acceptance. Track stays disabled until the controller workflow is integrated.

Pending crossing acceptance: `build/track-pending-update-20260930-234608` records
native EW->NSEW on a stage-zero crossing. Building/job IDs, stage, material fields,
job flags/type/subtype/position, item role/index and reservation stay unchanged;
only the construction subtype changes. Replaying that one field reproduces the
sampled state. `build/track-pending-production-20260930-234916` then verifies a real
production Place with the same selected items: four exact new jobs and one pending
update, retaining the existing building/job/material reference. The receipt reports
placed4/updated1. Both owned runs preserve frame0 and source saves. The engine run
has only the known renderer warning. Adapter tests cover mixed create/update and
refusal before writes for wrong stage, removal, position, job type or subtype;
all35 adapter tests and pure plan/executor tests pass. The first native capture
attempt failed its label-case matching and is not acceptance; corrected234608
supersedes it. This acceptance is a flat crossing, not every pending lifecycle or
ramp update.

The local Track draft now preserves ordered start/destination endpoints with
singleton wire dimensions instead of normalizing a rectangle. Preview acceptance
owns the bridge path and verifies status, endpoint order, bounded length, unique
nonnegative Vector3i positions. Endpoint changes/reset invalidate path, materials
and selections. Material requests carry the destination and ignore replies for
obsolete destinations even when the origin matches. Track Place requires that
validated path and explicit item IDs; aggregate constructors still reject exact
ID submissions. The catalog's supported flag continues to gate ordinary exposure.

Protected `build/track-draft-production-20260930-235341` uses the actual local draft
for Preview, Materials, native-rule exact selection and Place. Five native jobs
match the selected IDs, route positions and Track subtypes; frame0 and the owned
save stay unchanged. It uses a test-only enabled definition, not public catalog
activation. New `construction_track_draft_test` covers endpoint order, geometry
ownership, obsolete destinations, malformed paths, exact submission and identity
copying. It and existing draft/exact-selection/controller tests pass with only the
known renderer warning.

The controller now retains the first Track endpoint across elevation changes,
sends no premature one-tile preview, and outlines the returned path cells at the
viewed elevation. Rejection clears and redraws obsolete path geometry. It does
not infer persistent Track job geometry from the singleton request footprint or
first-building ID. Exact persistent job markers remain unfinished.
The missing marker source is now identified: `bridge/plugin/entities.cpp` excludes
Construction from hinted, full and incremental building scans, and the mirror
BuildingKind contract excludes it on the assumption that constructions are terrain.
That assumption misses pending jobs. Native024400 captures five actual pending
Track buildings (stage0/max1) as white directional markers over terrain/items;
the centered screenshot was inspected. Installed
`vanilla_buildings_graphics/graphics/graphics_planned_constructions.txt` supplies
named planned Track and ramp sprites. See `pending_visual_capture` for semantic
facts and the raw-file hash. The owned session ended paused with unchanged saves.
Snapshot schema **8** now appends a pending Construction building kind, preserving
existing kind values. Management remains39 and session9. Bridge hinted/full/incremental
scans publish pending native subtypes and retire completed constructions back to
terrain. The asset resolver uses the installed planned-construction names without
material recolouring or the furniture ghost tint. The synthetic demo recording was
regenerated; old native snapshots remain version-incompatible and must not acquire
invented pending-job evidence through migration. Matching bridge and extension were
built/installed, import is clean, and core CTest19/19 passes, including new asset and
entity-lifecycle regressions. See `build/qa/pending-construction-*`.
Protected GPU025325 opens the viewer after five native pending jobs already exist.
All stable IDs, incomplete stages and exact tile footprints reach the model and GPU
meshes. The screenshot was inspected against native024400; directional white markers
are visible. Native jobs/reservations and source saves remain unchanged at frame0,
with only known engine diagnostics. See `pending_visual_capture.production_capture`.
This accepts initial streaming/rendering for the captured flat Track pieces, not
pixel identity, live removal/completion, reconnects, ramps or other construction types.
The broader pending-art reference is now `pending_tile_rendering.json`: 76 paused
native cases cover all 38 construction subtype IDs with granite and oak. Every
native maximum stage is one; the only pending stage is zero. All 38 textures
match the corresponding installed PLANNED_CONSTRUCTION token without palette
or alpha modification. `pending_tile_render_gpu` verifies uploaded RGBA, cell
position, white vertices and fresh-source reloads for all 76 cases. Core passes;
`build/qa/pending-tile-native` passes GPU checks with the three documented Godot
diagnostics. ReinforcedWall is diagnostic coverage, not authorization to expose
an additional menu entry. These paused cases establish pending source artwork,
not completed terrain, natural labor or final composited-pixel equivalence.
Protected025536 exposed stale pending markers after native cancellation while paused:
no simulation tick or DF3D command triggered publication. The bridge now compares
the native building pointer sequence while paused and requests an entity Full when
it changes; unchanged lists cause no additional publication. Corrected GPU025852
removes the canceled job from the model and renderer while preserving four other
markers. Native verification confirms the released item, unchanged remaining jobs
and counters, frame0 and unchanged source save. The screenshot was inspected and
only known engine diagnostics remain. See `pending_visual_capture.removal_capture`.
This uses a native deconstruction fixture action, not a native UI click. In-place
native subtype changes, completion, newly placed jobs and reconnect remain separate
live scopes. The matching bridge is rebuilt and installed locally.
Protected GPU030045 additionally recreates the entire fortress scene/world client
after native cancellation. The fresh client restores the four surviving pending
entities and markers; the canceled ID remains absent from both model and renderer.
Native verification preserves the remaining jobs, reservations and counters, and
the owned session ends paused with unchanged saves and only known diagnostics.
The screenshot was inspected. See `pending_visual_capture.reconnect_capture`.
This covers a fresh client in the same Godot process, not native world reload or
bridge restart. Completion, newly placed jobs and in-place subtype changes remain open.
Protected GPU030242 accepts newly placed pending markers: full-scene bent Closest
creates five jobs after attachment, and exact native entities/markers arrive with
no local intent footprints. Native item/subtype/reservation checks pass; see
`pending_visual_capture.creation_capture`.
Accelerated completion exposed two more paused-update defects. A native completed
building can remain in the list at stage1/max1, so the bridge now checks existing
pending stages/subtypes as well as the pointer sequence. Changed pending tiles also
hint terrain before entity publication, preventing a retired marker from leaving
stale terrain. The bridge is rebuilt/installed. Protected GPU031228 uses `build-now`
on one controlled native job: its entity/marker retires and constructed steel terrain
arrives while four other jobs and counters remain unchanged. The native tile is
`ConstructedFloorTrackSW`. See `pending_visual_capture.completion_capture` and
`build/qa/pending-completion-bridge-build.log`. Saves remain unchanged at frame0;
only known diagnostics remain. Earlier fixture/publication failures are rejected.
This accepts accelerated entity-to-terrain handoff, not ordinary hauling/labor or
completed Track directional artwork. The inspected screenshot currently resembles
ordinary constructed floor; that rendering path remains an explicit parity gap.
Native031450 confirms the gap: completed steel SW Track displays curved rails and
sleepers. The installed `graphics_tracks.txt` names `TRACK_CONSTRUCTED_STONE_SW`
at TRACKS(3,1), matching the inspected native appearance; WOOD and CARVED families
are separate. See `completed_visual_capture`. Completed direction now crosses the
source terrain contract, model, mesh face and artwork query as `completedTrack`
(N=1, S=2, E=4, W=8), independently of pending carve metadata. The bridge derives
it from native TRACK tile types and directions. Snapshot schema 9 validates the
four-bit mask; resident terrain layout 4 uses the previously spare upper nibble
of `track_blockers`, preserving its existing lower-bit meanings. Tile sizes remain
8 bytes for the snapshot terrain struct, 12 for the resident tile and 14 for the
model tile. Equality and face-cache identity include completed direction.

Compatibility: rebuild the bridge and all consumers together. Older snapshot
readers and grid readers are rejected by their respective versions; old recordings
must be recaptured rather than relabeled, since they lack completed direction.
The synthetic demo was regenerated. Core build and all 19 CTest checks pass
(`build/qa/completed-track-core-build.log`, `completed-track-ctest.log`), including
independent pending/completed directions, invalid-mask rejection and changed face
metadata. Matching schema 9/grid 4 bridge and extension builds are now installed;
editor import has no diagnostics (`completed-track-bridge-build.log`,
`completed-track-extension-build.log`, `completed-track-import-diagnostics.json`
under `build/qa`). Protected GPU032806 observes zero completed direction at all
five pending sites, then completed SW=10 independently from pending carve=0 after
native `build-now`. Pending entity/marker retirement and four surviving jobs,
reservations and counters pass. The owned DF31096 ends paused/frame0 with unchanged
source saves. Known startup/D3D12 shutdown diagnostics only: passed_with_known_issues.
See `completed_visual_capture.semantic_capture`. Read-only `tile_hover_info`
exposes both semantic masks without adding visible labels. The inspected screenshot
from that run still shows ordinary steel flooring. The subsequent implementation
and steel SW acceptance are described below; broader material/ramp/carved evidence
remains open. The owned native capture ended paused with unchanged saves. This is
a flat steel SW reference, not acceptance of all materials, ramps or carved tracks.
Protected native033040 additionally resolves the completed tile's base layer to
`STONE_FLOOR_5` (FLOORS index37, 9 columns, coordinate1,4), not `METAL_FLOOR`.
Rails occupy `screentexpos_background_two` with a generated texture ID, whose
color transformation remains unidentified. See `completed_visual_capture.layer_capture`.
These native render buffers are oracle-only. A retained planned layer after
accelerated `build-now` also needs a native redraw/normal-completion comparison;
this capture does not establish completed cleanup fidelity.
Protected native033404 identifies the generated texture exactly: all 1,024 rail
pixels match installed `TRACK_CONSTRUCTED_STONE_SW` after default palette row0
maps to steel's `BLUE-GRAY` row116, taking the first matching palette column.
Alpha is unchanged. All 1,024 base pixels match unmodified `STONE_FLOOR_5`.
Thus completed steel Track needs a separately recolored transparent rail layer
over the original floor, not recolored or mean-filled backing. The read-only
SDL pixel oracle uses offsets verified against bundled SDL2 headers; its images
remain ignored capture output. See `completed_visual_capture.pixel_capture`.
Owned DF36620 ended paused with source manifest unchanged. Broader materials and
completed-state redraw behavior remain open.

Completed floor Track now emits a transparent feature decal above its slab. The
resolver maps N/S/W/E tokens to original constructed STONE/WOOD or CARVED artwork,
with a material palette swap and no alpha fill. Constructed backing uses original
`STONE_FLOOR_5` independently of rail coloring. Ramp Track rendering remains open.
Core build and all 19 CTest checks pass (`completed-track-art-ctest.log`); the
extension rebuild/import passes with clean import diagnostics. Protected GPU033945
verifies steel SW completion and captures the displayed rail. Both the actual
runtime rail texture and background match all 1,024 native pixels each. The
screenshot was inspected for orientation/placement. Four other jobs, reservations
and counters remain intact; DF56928 ends paused/frame0 with unchanged saves.
Only documented engine diagnostics occur (passed_with_known_issues). See
`completed_visual_capture.production_capture`. Synthetic token tests for wood and
carved variants do not establish native acceptance of those variants.
Native034206/034302 expand the pixel reference to dolomite S/NE, petrified wood
SW/NE, jet W, willow S/NE, date palm SW/NE and durian W. Every rail tile matches
all 1,024 pixels after the corresponding palette swap; every backing matches
unmodified `STONE_FLOOR_5`. Actual plant woods use WOOD artwork; petrified wood
uses STONE. See `additional_material_captures`. These runs establish native
references, not viewer acceptance for the added materials. Moving fixture items
changed native Closest selection, so actual materials are recorded rather than
assuming the earlier steel/wood mix. Both owned sessions ended paused with saves
unchanged. The native planned layer persisted even after camera redraw following
accelerated completion; normal construction cleanup still requires separate evidence.
Protected GPU034443/034517 now verify matching viewer output for all ten added
stone/wood tiles. Each material and completed mask agrees with native state,
pending markers/model entries are absent, and runtime rail/background textures
each match all 1,024 pixels for every tile. Both rendered paths were inspected for
orientation. These are fresh viewer attachments after completion, complementing
the earlier steel SW handoff while attached. Both sessions end paused/frame0 with
unchanged saves and only known engine diagnostics (passed_with_known_issues).
See `additional_material_production_captures`; remaining flat directions, ramps,
carved Track and ordinary labor completion are not covered.
Native034718 sweeps all 15 constructed steel floor directions and 15 carved
floor directions by controlled tiletype changes. Native034827 repeats four-way
Track in isolation. Steel four-way NSEW unexpectedly uses
`TRACK_CONSTRUCTED_WOOD_NSWE` with steel palette row116 in both captures; the
current nonwood resolver selects STONE and therefore has a known parity defect.
The other 14 constructed directions match STONE sprites. Carved sprites match
CARVED at row0 in this fixture, but its geology/material was not retained, so no
general coloring rule follows. All backing references identify `STONE_FLOOR_5`.
See `direction_sweep`. These controlled rendering references do not establish
construction or routing acceptance. Both owned sessions ended with unchanged saves.
The four-way resolver defect is now corrected: constructed mask15 selects native
WOOD crossing artwork while retaining material coloring. A regression keeps both
STONE and WOOD four-way sprites present and requires the native WOOD choice.
All19 CTest checks pass; extension rebuild and clean import pass (`track-cross-*`
logs under `build/qa`). Protected GPU035052 extends native evidence and matching
viewer acceptance to dolomite, petrified wood and jet: five masks15, exact materials,
no pending markers, and all1,024 pixels matching for each rail and background.
The rendered screenshot was inspected. DF46760 ended paused/frame0 with unchanged
saves and only known engine diagnostics. See `four_way_production_capture`.
These controlled crossing tiletypes do not establish four-way construction workflow.
Carved floor Track required a separate correction. GPU035220 reported dolomite
and completed mask15 correctly, but runtime material recoloring matched only344
of1,024 native groove pixels and the resolver selected smooth flooring. That run
is rejected for visual acceptance. Carved grooves now retain their original art
colors, and all completed flat Track uses original `STONE_FLOOR_5` backing.
Regression checks cover unchanged carved palette and backing despite smooth flags.
Core/all19CTest and extension/import pass (`track-carved-*` under `build/qa`).
Protected GPU035434 verifies both texture layers pixel-exact and displayed placement
for the dolomite four-way carved tile. DF28684 ends paused/frame0/source unchanged;
only known engine diagnostics occur. See `carved_production_capture`. This is a
controlled tiletype reference, not natural carving labor or other terrain classes.
Native035624/035801 extend the rendering oracle to all15 constructed and15 carved
ramp directions, both lone and north-supported. All60 rail samples equal their
floor counterparts byte-for-byte; aligning construction subtypes in the repeat
preserves that result. Carved ramp backing is exactly original `STONE_RAMP_OTHER`
or `STONE_RAMP_WITH_WALL_N`, respectively, with fully opaque pixels unaffected by
palette swaps. Constructed background index0 in these controlled fixtures remains
unresolved: complete a genuine ramp job before inferring a native absence rule.
See `ramp_reference`. Both owned sessions end paused with unchanged source saves;
this is neither ramp viewer acceptance nor construction/traversal acceptance.
`constructed_ramp_rendering.json.gz` resolves the missing constructed background
reference with 150 paused cases: actual bituminous-coal boulder and willow-log
constructions completed through `build-now`, each with 15 track directions and
lone/N/S/E/W support. Native `completeBuild` creates the construction records;
direction and support are then controlled diagnostic mutations. The background
texture is held in the descriptor ramp-graphics cache keyed by the viewport ramp
flag, not the background texture slot. All five backgrounds match installed
STONE_RAMP artwork; its pixels are palette-insensitive. All 30 rail textures
match the constructed STONE/WOOD tokens with material palettes, including the
WOOD four-way crossing for coal. Diagnostic cache reads remain outside runtime.
The native pending building layer retained by accelerated completion is recorded
and excluded from these terrain references. This closes the native source-art
question, not natural completion cleanup or final compositing. Both protected
captures preserve the source save and close DF. `constructed_ramp_render_gpu`
now verifies all 150 cases and three fresh-source reloads: model materials,
uploaded background/rail RGBA, correct texture-array layers, support orientation,
matching footprints and rail planes immediately above their ramp surfaces.
Core passes; `build/qa/constructed-ramp-native-verified` passes with the three
documented Godot diagnostics. The initial test incorrectly sampled the bank's
first texture instead of each triangle's selected layer; the renderer required
no change. These checks cover constructed ramps with these two materials and
cardinal/lone support, not arbitrary multi-wall arrangements or carved ramps.
Ramp rail geometry is now implemented: a feature quad follows each supported
slope at a small vertical offset, or sits at the lone ramp's top height. Resolver
rail selection accepts ramp top/slope faces while retaining existing ramp backing.
Tests check all four slope directions, lone height, no side overlays, and removal
when completed Track clears. Core/all19CTest and extension/import pass
(`track-ramp-*` under `build/qa`). Protected GPU040131 verifies a north-supported
dolomite carved NS ramp: exact mask/material and all1,024 native pixels matching
for both runtime rail and backing. Both screenshots were inspected for the target.
DF35780 ends paused/frame0/source unchanged with only known engine diagnostics.
See `carved_ramp_production_capture`. Other ramp cases remain unaccepted.
The same clear-floor screenshots expose a separate pending-Track question: native
gray path artwork beneath white markers is absent from the viewer. Earlier marker
checks do not close this visual gap; investigate its native layer and lifecycle.
The gray path is now traced to partial alpha in the original planned sprite
(115/255), previously discarded by alpha-scissor0.5. Flat Construction markers
now use alpha blending with vertex alpha1, keeping native opacity. Extension
build/import pass. Protected GPU040505 verifies blending configuration and exact
RGBA texture equality for all five pending tiles, including964 pixels per tile
below the former cutoff. Native and production screenshots show the gray path
restored, but translucent regions appear brighter in the viewer; final blend
color-space/compositing parity remains open. Do not equate these matching source
textures with fully matching composited pixels. DF35056 ends paused/frame0 with
unchanged saves and only known diagnostics. See `pending_visual_capture.alpha_capture`.
Analysis of125 uniform source neighborhoods gives viewer mean RGB-byte error0.18
against linear source-over versus12.11 against encoded-RGB blending. Native is
closer to encoded blending (5.81 versus17.83), but that residual means background,
scaling or rendering modulation still needs isolation. The cause is not yet fully
accounted for. Raw analysis stays beside the capture. A simple screen-sampling
fix is not implemented: [Godot's documented screen texture](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)
is captured before transparent geometry and would omit transparent underlays.
Protected native capture `build/track-pending-blend-baseline-20261001-041304`
now compares the same five tiles before and after removing their stage-zero jobs.
Using the actual rendered background reduces encoded-RGB blend error to 0.53–0.74
RGB bytes per tile across 2,419 uniform foreground samples; linear blending gives
13.54–16.20. This isolates most of the earlier native residual to the background
comparison. Filtering/rounding outliers remain, so this is evidence for the blend
model, not exact pixel acceptance. These captures establish the native blend model. The world color pipeline
described below now applies encoded-RGB blending to ordinary 3D layers; this is
not a fresh live acceptance of every Track workflow or sort order. Native screenshots were inspected;
DF49752 ended at frame zero with the clone manifest unchanged and no classified
or unclassified errors in captured logs. See `blend_analysis.matched_native_baseline`.
Protected `build/track-controller-production-20261001-000209` exercises the actual
controller, action service and material group signals with test-only activation
of the disabled Track leaf. Five native jobs match exact item IDs, positions and
subtypes; confirmed placement clears the draft, and keep-building/close transitions
pass. DF stayed paused at frame0, the source manifest stayed unchanged and the
owned process ended. `construction_test` covers input, elevation, path outlines,
rejection redraw and cancellation. Both runs are passed_with_known_issues with
only the known renderer warning. See `controller_capture` in the material fixture.
The material view now expands complete candidate groups with native open/closed
expander art, exact item buttons, native text/count/distance columns and the
verbatim Track recipe heading. Group distance is the minimum remaining candidate
distance and disappears when exhausted; child distances remain visible. Repeated
specific clicks are no-ops. Collapse/reopen and filtering retain local expansion;
snapshot replacement clears it. Aggregate-only rows do not claim item identity.
Protected `build/track-material-art-20261001-000724` records rendered native cells,
column positions and fully-selected behavior. The earlier000559 oracle failed a
field lookup; corrected000638 and the extended000724 capture pass. Evidence is
`picker_art_capture` in the material fixture; palette values map the pinned game's
`data/init/colors.txt` and captured foreground indices.

Protected `build/track-controller-individual-20261001-001133` drives actual expanded
item buttons through the controller and action service. Five native jobs match the
exact chosen IDs, positions and subtypes, including repeated-click checks. It uses
test-only Track activation. Native capture and live effects remain paused at
frame0 with unchanged source manifests and ended owned processes. Headless view,
controller and exact-selection checks pass with the known renderer notice. The
material-view GPU check also passes with classified D3D12 shutdown diagnostics;
`build/qa/03-U/materials_track_individual.png` was inspected. See
`individual_controller_capture` and `build/qa/track-individual-diagnostics.json`.
This proves the scoped input/effects and rendered columns, not full native visual
parity. Item artwork, custom palettes, pointer/GPU workflow, broader stale-state
and native lifecycle acceptance remain unfinished.

Protected `build/track-stale-live-20261001-001848` verifies seven stale Track Place
refusals against real DF: forbidden item, already-reserved item, changed material
group, blocked endpoint, stale revision, foreign item ID, and a retained selection
after bridge disable/enable/reconnect. Every request reports typed Rejected with
placed0/updated0. Native building/job counters, candidate flags/positions/material
fields and native pathfinder generation remain unchanged relative to the explicit
fixture mutation; mutations are restored between cases. DF stays paused at frame0,
source manifests match and the owned process ends. Only the known renderer notice
appears. See `stale_placement_capture` and `build/qa/track-stale-diagnostics.json`.
Six-case001612 also passed;001749 failed its test harness by sending Catalog before
opening the replacement management client, corrected by waiting for live transport.
The restart retained the same world epoch, so this establishes cache retirement
and reconnect rejection, not world replacement or controller/GPU stale-state parity.

Controller lifecycle acceptance now adds two protected runs.
`build/track-controller-stale-20261001-002211` exercises actual item/group controls
and Place after forbid/in_job/material/site changes. Refusals clear material
snapshots, selections, preview and ordered path. Bridge restart clears the local
catalog and definition. Stale controls submit nothing; a shared-service read-only
Catalog claim on reconnect is allowed. Native effects remain zero.
`build/track-controller-epoch-20261001-002559` uses the lane helper's in-process
quit-without-saving and reload. Epoch193995082825729 changes to193995082825730 in
the same owned process. The controller invalidates the old draft; stale controls
submit nothing and replacement-fixture native readback confirms zero effects.
All684 source file hashes match; the paused owned session ends. Both runs have only
the known renderer notice. See `controller_lifecycle_capture` and
`build/qa/track-controller-lifecycle-diagnostics.json`. Earlier002124 and002320
failed harness assumptions about the reconnect read claim and panel toggle;
the corrected runs supersede them. This is headless controller acceptance, not
pointer/GPU parity or an outstanding sent/unknown mutation during unload.

Protected `build/track-picker-icons-20261001-003017` establishes the ordinary
material-picker icon source. Native anchored layers contain32x32 icons positioned
18px after the expander and2px below the row top; ordinary text-cell reads expose
only their background. The paused texture diagnostic records bounded RGBA in
ignored output. A probe calling production `resolveItem` and comparing installed
page crops/palette replacement matches all48 visible-pixel observations across
16 visible rows in initial, expanded Iron and selected Iron frames. These cover
ordinary bars, blocks, wood and rock salt. Native zeroes RGB underalpha0 while the
source PNG retains hidden RGB; raw byte differences are recorded rather than
claimed identical. See `picker_icon_capture`. DF stayed paused at frame0, the
source manifest matched and the owned process ended.
Management version38 adds optional, owned material candidate appearance facts:
material/subtype/color raw tokens, stack size and semantic artifact/web flags.
Both peers must rebuild; the shared region is `Local\\df3d_management_v38`.
Old recordings without these facts keep appearance absent; do not infer raw tokens
from translated captions or invent a fallback. Validators reject malformed UTF-8,
invalid lengths, stack counts and flags. Appearance participates in snapshot identity.
Native texture IDs and screen anchors remain oracle-only.

Cut-gem candidate snapshots additionally publish the optional descriptor raw ID
`gem_shape_raw`. It is valid only for SMALLGEM and participates in snapshot
identity and payload limits. The picker uses installed
`SHAPE_GRAPHICS_SMALL_GEM` definitions, with the native item-ID arrangement and
native compositing/palette order. Asset cache format9 invalidates earlier indexes
that omitted these definitions. Generic groups use `ITEM_GEMS`; absent shape
facts keep that generic icon rather than guessing a cut. An empty item color
uses the material color. This change does not publish individual map-item shapes.

Generic gem group and Last names come from DF's native item-description method
on an owned, unregistered `item_smallgemst` containing only the material, default
stack and unspecified shape. The temporary is deleted on success or error;
live items, IDs, menu state and graphics caches remain untouched. Individual
rows use their actual item descriptions. Native capture
`build/gem-generic-name-native-20261024-034149` matches ruby, emerald and all three
glass group names and verifies unchanged world item count and next ID.
`material_candidates.json.cut_gem_native_reference` records all88 native cut
composites plus four colored picker references. The icon regression matches
these hashes and checks material-color fallback. Protected viewer
`build/cut-gem-picker-main-20261024-034511` verifies four candidate shapes,
generic/history names, pointer group/individual selection and natural completion
at frame1575 using exact items48525/48526/48527, with zero jobs. The expanded
picker screenshot was inspected; source save unchanged, owned DF closed, known
engine diagnostics only. Core, adapter138, material UI, icon and group-helper24
checks pass in the fixture's referenced gates. Earlier033353 did not establish
completion: its screenshot exposed color/name defects and Public Play timed out.
The corrected run waits for rendered frames before clicking Play.

The presentation resolves candidate icons through the existing installed-asset
resolver without terrain residency. The actual extension matches48 canonical RGBA
hashes from the native capture (transparent RGB is normalized). Protected
`build/track-appearance-live-20261001-004132` verifies all60 candidate appearance
records against independent native item facts, resolves each icon, and exercises
individual material controls to create five exact native Track jobs. DF stayed
paused at frame0; the source manifest matched and owned DF44188 ended. See
`material_appearance_capture` and `build/qa/track-appearance-diagnostics.json`.
Core19/19 and adapter35 tests pass; engine checks pass with classified known
renderer diagnostics. The GPU material view was inspected with group/child icons.
This does not establish full pointer/GPU workflow parity, artifact/improvement
groups, appearance overrides or custom palettes.

Material picker row colors now use `ui_palette_color(index)` from the loaded
asset provider's classic palette. Captured roles are WHITE for row text, LGREEN
for distance, YELLOW/RED for All/None and DGRAY for disabled actions. No additional
bridge data or native UI reads are involved. `construction_material_test.gd`
checks all16 colors against installation tokens and injects distinct fixture
colors to verify role mapping. GPU picker and controller checks pass with known
engine diagnostics only (`build/qa/construction-palette-diagnostics.json`); the
rendered picker was inspected. This verifies palette plumbing, not live DF with
a modified palette, full pointer behavior or other panels' color fidelity.

Protected `build/track-pointer-live-20261001-004830` extends material acceptance
to GPU viewport mouse events: expand groups, click individual candidates and
repeat a specific click. Actual controller completion creates five native Track
jobs with verified positions, subtypes and exact item reservations; keep-building
clears the completed path. Source save unchanged, paused frame0, owned DF13180
ended. See `pointer_controller_capture`; only classified engine diagnostics remain.
The GPU material test also checks locked pointer refusal and search right-click
cancellation. Catalog selection and map endpoints in this live harness still use
controller methods; full scene pointer/layout acceptance remains open.

Protected `build/track-scene-pointer-live-20261001-005048` adds the actual fortress
scene: launcher, Constructions/Track leaf, both ray-verified map endpoints and
individual material rows are exercised through viewport mouse events. The native
verifier confirms five exact jobs and reservations, with paused frame0 and unchanged
source save. Owned DF12412 ended; only classified engine diagnostics remain.
Track activation is test-only. See `scene_pointer_capture`. The full-scene GPU
capture was inspected. Earlier005000 failed because the harness clicked before
new panel layout settled; the corrected harness awaits layout frames. This straight
route does not establish reversed/bent/elevation pointer behavior, full native
layout, pending ramps, hauling or completion.
Protected GPU023801 now accepts the reversed straight-route Closest input case:
the actual fortress scene receives viewport clicks on the launcher, Track leaf,
Closest option and both ray-verified map endpoints, from105,39,165 to101,39,165.
Native readback matches all five reference jobs, directional subtypes and exact
reserved items, and construction returns to the map. Track activation remains
test-only. See `scene_closest_reverse_capture`. The owned session ended paused
with unchanged saves and only classified diagnostics. The completion screenshot
was inspected; it does not establish persistent Track geometry or native layout.
Bent/elevation pointer behavior, hauling and completion remain separate gaps.
Protected GPU024006 adds a bent route through the same full-scene input path.
Native endpoints101,39,165 to103,41,165 produce a five-tile zigzag; production
readback matches each site, corner subtype, exact assigned item and reservation.
The panel returns to the map, the owned source save remains unchanged at frame0,
and diagnostics contain only known signatures. See `scene_closest_bent_capture`.
The screenshot was inspected; persistent pending-job markers remain unfinished.
Reverse bent paths, elevation changes, hauling and completion need separate evidence.

Protected010602/010835 add pending ramp mutation evidence: native and production
crossings change `TrackRampEW` to `TrackRampNSEW`, preserving the existing job and
reserved material while creating four new jobs. An already-covered overlap needs
zero materials; native still opens the picker without quantity or All/None controls,
and a row click finishes without reserving an item or changing jobs. Production
empty-selection Place confirms zero new/updated effects. See
`pending_ramp_commit_capture`; paused frame0, unchanged saves, owned processes ended.
The material view now supports that row-click behavior and passes GPU pointer
regression with known engine diagnostics only. Live controller integration of the
zero-material click, full ramp elevation workflows and hauling remain unverified.
Protected011019 now verifies that zero-material click through the actual controller
and GPU viewport input: the picker waits across12 processing frames, then the row
click completes with empty selections and zero placed/updated jobs, closes the
panel and releases map input. Native readback confirms exact final jobs and item
reservations with no extra counters. Source unchanged, paused frame0, owned
DF30896 ended; known engine diagnostics only. See
`zero_material_controller_capture`. Endpoint input is programmatic in this case;
other material preferences, child-row completion and full ramp lifecycle remain
unverified.

Zero-material preference captures011156/011240 show native Last retaining the
picker even after a known single-material construction, while Closest completes
without new jobs. The controller now skips automatic Last reuse when required0;
GPU live011319 verifies it retains Last, waits for the row click and completes0/0
with unchanged native reservations. A controller regression also passes, with only
classified engine diagnostics. All owned sessions preserve saves and pause.
See `zero_material_preference_capture`.

Protected native011510 captures three nonzero Closest cases: forward, reverse and
rearranged item positions. Native fills displayed groups in order, choosing nearest
items within a partially consumed group; globally sorting every candidate by
distance produces different selections. The connected Track controller now follows
that rule after collecting the complete immutable material snapshot. Closest stays
selected across mixed-material placements and resets when changing to another
construction family. Protected GPU controller011641 clicks the actual Closest
option and verifies the third case's exact five jobs and item reservations against
native readback. Both owned sessions ended paused with unchanged source saves.
See `closest_capture` in `fixtures/construction/material_candidates.json`.
The registered `construction_closest_test` replays all three native identity sets
and checks pagination deferral and zero-material completion. Both it and the
existing controller regression pass with only classified engine diagnostics.
Native shortage012338 verifies three available items for five required sites:
all three candidates are selected, Closest stays enabled and the picker stays open,
but no items are reserved and no jobs/buildings are created. The native screen
shows `No access to 5 building material non-economic items` without ordinary
picker rows. `closest_shortage_capture` preserves those facts and the registered
Closest regression checks selection identities and refusal to place incomplete
coverage. This does not accept the production shortage layout or live effects.
Settled native012534 retains that display after twelve UI frames. Empty-candidate
012634 additionally shows `Needs building material non-economic item` and
`- mine rock or chop trees`. Native012634/012746 cancellation exits to Default
with Closest retained, no jobs or reservations. The controller now closes construction
on cancellation of a complete Closest shortage snapshot, rather than returning to
placement. Offline regression covers that decision and excludes incomplete pages;
live production cancellation and shortage rendering remain unaccepted.
Native visual013136 now establishes the compact upper-left message frame. The
controller renders this shortage state separately from the ordinary picker, using
the captured native copy, including the two-line empty-candidate hint. Protected
GPU013349 verifies three-of-five selection, message visibility, right-click return
to map and native readback with no job/building/reservation changes. The owned
session ended paused with the source save unchanged; only classified engine
diagnostics occurred. Offline controller regression covers both three and zero
available candidates. Full pixel parity remains open: the current compact border
has square corners and its text/panel vertical spacing is four/eight pixels too
short relative to native. Live zero-candidate rendering and retry remain unaccepted.
An initial headless controller run exited with access violation (-1073741819)
without diagnostics; subsequent recheck and final regression passed. Preserve
`build/qa/construction-shortage-panel.*.log`; that initial crash is unclassified.
Protected GPU013602 now verifies the empty-candidate hint/shortage state through
the actual controller, with zero selections, no Place, right-click exit and native
no-effect readback. Vertical padding is corrected to twelve pixels top/bottom;
rounded frame corners and multiline spacing remain visually unaccepted. Native
retry013718 adds two candidates to a three-of-five shortage: twelve UI frames
retain the old three-candidate selection without creating jobs. Cancel/reopen and
placing the route again creates all five native jobs. The controller regression
checks that shortage processing does not automatically refresh or place; production
material arrival followed by explicit retry still needs live acceptance. Both owned
sessions ended paused with unchanged source saves, and the GPU run has only
classified engine diagnostics. See `closest_shortage_capture.retry_capture`.
Protected GPU014047 now covers production material arrival and explicit retry:
the real controller retains the three-item shortage after two items become available,
then right-click cancellation and reopening Track preserve Closest. A fresh placement
creates five jobs; native readback confirms exact site assignments and reservations.
All five building/job/item identity triples match the independent native013718 oracle.
The owned session ended paused with unchanged source save and only classified engine
diagnostics. See `production_retry_capture`. Endpoints remain programmatic; this
does not establish full-scene map input or broader material histories. Earlier013954
controller assertions passed but the runner failed to retrieve its process exit code
and skipped native verification; only corrected014047 is accepted.
The single-line shortage frame is now visually accepted: protected GPU014701's
entire 448x36 panel at (32,52) matches native013136 with zero differing pixels.
It uses the installed `HOVER_RECTANGLE` texture (8px horizontal/12px vertical
texture margins) and installed `LRED` palette entry12. `data/art/border.png` was
an intermediate incorrect candidate and is not used. The named atlas asset stays
runtime-resolved; no native screenshot or artwork is shipped. The controller
regression covers the original texture and palette role; live cancellation/effects
also pass with only classified engine diagnostics. See `single_line_visual_capture`
and `build/qa/shortage-panel-pixel-comparison.json`. Multiline empty-shortage pixel
parity and full-scene input remain separate gaps.
Empty-shortage multiline pixel parity is now accepted: native014851 and protected
GPU014932 match across the entire 448x60 panel (zero of 26,880 pixels differ).
The Label uses zero extra line spacing, preserving native twelve-pixel lines.
Controller cancellation and native no-effect readback pass, with known engine
diagnostics only and unchanged paused source saves. `multiline_visual_capture`
records the comparison. Native015053 additionally establishes required1/provided0
copy: `No access to building material non-economic item`, with no numeral. The
controller now handles that singular form and its offline regression passes;
singular production effects/rendering are not yet live-accepted. See `singular_capture`.
Protected GPU015428 now accepts that singular production case over four existing
pending Track jobs: required1/no candidates, no Place, and right-click return to map.
Native readback preserves all four building/subtype/job/flags/item/reservation
fingerprints and global counters. The entire 448x60 panel matches native with zero
pixel differences after fixing its minimum width to448 (earlier015324 shrank to424).
Controller regression covers that width; both live and offline checks have only
classified engine diagnostics. Owned sessions ended paused with unchanged saves.
See `singular_production_capture`. Endpoints are programmatic; wider-count wrapping
and full-scene shortage input remain unaccepted.
Native015655 establishes that Closest can consume seventeen distinct semantic
material groups in one seventeen-tile Track placement, creating all seventeen jobs.
`seventeen_group_capture` preserves native group identities, exact items and job/site
effects. The owned session ended paused with the source save unchanged. DF3D's current
sixteen-group limit is therefore a parity defect, not a native constraint. It exists
in the presentation draft, engine decoder, request validator and Track bridge
preflight; all must be corrected together, with request-capacity/compatibility audit,
regressions, matching builds and protected production acceptance. This native
capture does not accept the current implementation for seventeen groups.
That limit is now corrected for connected Track across presentation, engine decoder,
wire validation and bridge preflight, up to the existing 16,384-item/path bound.
Management protocol **39** uses `Local\df3d_management_v39` and a 2 MiB command
buffer (previously256 KiB); older peers cannot share the changed region layout.
The bridge reuses heap-backed command scratch rather than allocating2 MiB on the
native update stack. A maximum 16,384-group encoding test proves the request fits.
Other construction families retain their prior limit pending separate native evidence.
Root build/CTest19 checks, Lua preflight, engine shared-channel and controller
regressions pass; matching bridge and extension are built and installed locally.
Protected GPU020705 places all seventeen groups through the real controller and
bridge, matching native item/site/subtype assignments and reservations. The owned
session ended paused with unchanged saves and only classified engine diagnostics.
See `seventeen_group_capture.production_capture` and `build/qa/management39-*`.
Initial020408 exposed a decoder ordering bug and was rejected before mutation;
only corrected020705 is accepted. Maximum-scale live placement, other families and
full-scene endpoint input are not established by this seventeen-group case.
Protected GPU021323 adds live material pagination: an owned paused fixture creates
129 blocks from distinct installed inorganic materials. The bridge returns128 groups
then1, with the same immutable revision. Closest waits without selecting after the
first page, then places seventeen jobs after the final page. Native readback matches
all seventeen reference item/site/subtype assignments and reservations. The owned
session ended with unchanged saves and only classified engine diagnostics. See
`paged_closest_capture`. This accepts row-count pagination through the actual controller;
byte-budget paging, stale later pages, user scrolling and full-scene endpoints remain
separate checks. Native UI group count129 was not independently recorded. Failed
preceding attempts were fixture raw-container/item-object mistakes, not product
failures or evidence that the save lacks material identities.
Native Last captures021543/021744/021836 establish mixed-history behavior: after
five mixed Track jobs, Last remembers the material assigned to the final new job
(highest selected item ID). Reversing manual group selection does not change that
result. With only two matching items available, native preselects both and retains
Last in the picker; with none available it retains Last without substitution.
Track controller logic now follows those rules; zero-required row-click behavior
remains intact. Native-backed regression and the existing controller test pass with
only classified engine diagnostics. See `last_mixed_capture`. All owned captures
preserved paused source saves. Protected GPU022417 now accepts the production
Closest-mixed-history/partial/missing sequence: native readback first confirms five
mixed jobs; after fixture removal, Last selects exactly48127/48128 with no new jobs.
After those items become forbidden, Last selects none and retains its preference.
Both strategy buttons are clicked through the viewport; final native readback confirms
no unintended jobs, reservations or counter changes. The owned session ended paused
with unchanged saves and only classified diagnostics. See `production_capture` under
`last_mixed_capture`. Map endpoints remain programmatic; later captures below cover
viewport cancellation and reversed manual group selection. Full-scene input and
other families remain outstanding.
Native022547 also confirms partial/missing Last cancellation returns to Default
while retaining Last. The connected Track controller now closes construction in
those states rather than returning to placement. Protected GPU022643 exercises
viewport right-click cancellation in both states, verifies map input is released
and retains Last; native readback confirms no extra jobs, reservations or counter
changes. Both controller regressions pass with only classified diagnostics, and
owned saves remain unchanged and paused. See `last_mixed_capture.cancel_capture`.
Manual picker cancellation is also accepted for zero and two selected items:
existing native picker captures return to Default, and protected GPU022925 exercises
viewport row-All selection and right-click cancellation through the real controller.
The panel closes, releases map input and clears its draft while retaining the manual
preference. Native readback confirms unchanged counters and no item reservations;
the owned session ended paused with unchanged saves. Both controller regressions
pass with only classified diagnostics. See `manual_cancel_capture`.
Protected GPU023603 additionally selects the first three manual groups in reverse
order using viewport All buttons. Native readback confirms the five exact assigned
items (1155,39186,39187,48127,48128), matching the independent native manual oracle.
Last then preselects only the two matching wood items, or none after both are
forbidden; both pickers cancel through viewport right-click without further effects.
This verifies mixed history follows the final assigned item rather than the final
clicked group. See `last_mixed_capture.manual_production_capture`. The owned session
ended paused with unchanged saves and only classified diagnostics. Two preceding
attempts used the incorrect Closest oracle and are not accepted.
Map endpoints remain programmatic in these captures; full-scene Closest input,
other construction families, stale later pages and byte-budget pagination remain
separate acceptance scopes. The pagination, insufficient-supply, seventeen-group
and zero-material cases described above supersede their earlier acceptance gaps.



Track stays disabled while these and the native route-history discrepancy remain.
Core19/19 passes in `build/qa/connected-track-contract-test.log`, including endpoint
order and thirteen request-validation cases. The MSVC bridge build passes in
`connected-track-contract-bridge-build.log` with existing warnings; it was built
with SkipInstall. The root rebuild also reports pre-existing fixture/test warnings.
Those initial build-only checks have since been superseded by the protocol39
extension/bridge builds, local installation and protected production captures above.
Keep this breaking migration isolated when commits are authorized.

The bridge now provides an internal `route_track` callback on connected Track
requests. It compiles the same stateless `worldmodel/src/track_path.cpp` rules
used by native fixture regressions; it does not link WorldModel, mirror clients
or presentation state. The callback accepts a semantic reader, ordered endpoints
and actual map bounds, preserving Unknown facts and protecting Lua reader errors.
Brook shapes remain unclassified rather than normalized into wall/floor rules.
The construction adapter invokes it for connected Track Preview; eight flat paths
now pass protected live protocol acceptance (details below). The bridge builds without installation in
`build/qa/connected-track-route-callback-build.log`.
Build the isolated Lua-boundary test with
`cmake --build external/dfhack/build/VC2022 --config Release --target df3d_track_callback_test`;
run `external/dfhack/build/VC2022/plugins/external/df3d-plugin/Release/df3d_track_callback_test.exe`.
It verifies ordered paths, exact-once reads, blocked/unknown distinctions,
malformed inputs and recovery after reader errors; the Windows target copies its
Lua runtime beside the test. `connected-track-route-callback-test.log` records
TRACK_CALLBACK_PASS. This test is separate from root CTest and performs no game IO.
Passing `bridge/plugin/construction_track.lua` to the test executable additionally
runs the actual native-data reader against synthetic DF objects through the
compiled callback. Clear/pending Track, blocking Support and unverified transient
construction states pass in `build/qa/track-reader-callback-test.log`. The embedded
reader is supplied at construction-helper creation and shares its reset lifetime;
no separate registry reference survives helper retirement. It is attached only to
internal requests carrying a connected destination. The bridge build passes in
`track-reader-embedding-build.log` without installation, and all32 adapter tests
pass in `track-reader-embedding-adapter-test.log`.
Protocol34 now includes typed ConnectedTrackPreview status and ordered coordinates
on ConstructionState. The Lua Preview handler, bridge parser/serializer and model
decoder are connected. Native no-path, invalid input, frontier limit and unverified
terrain remain distinct. A16384-tile response cap reserves192KiB for path geometry
within the512KiB reply envelope; larger routes return PayloadLimit with no partial
path. The validator rejects repeated, negative, discontinuous or diagonal xy
steps, invalid statuses, wrong action/definition and geometry on non-Found results.
The bridge additionally checks that found endpoints match the request.
Core19/19 passes in `build/qa/track-preview-response-test.log`, including16 response
contract cases; all33 adapter tests pass in `track-preview-response-adapter-test.log`.
The bridge build passes without installation in `track-preview-response-bridge-build.log`.
Build warnings in unrelated existing code remain. Matching protocol34 bridge and
extension are now installed. Protected run `build/connected-track-preview-20260930-184841`
compares eight exact ordered native flat paths through Godot, model and bridge.
It reports passed_with_known_issues (known separate-renderer startup notice only),
with DF paused, owned process ended and source save unchanged. Bounded evidence and
limits are retained in `fixtures/construction/connected_track.json` under
`live_preview_transport`. The manual test is `connected_track_preview_live.gd`;
it requires protected clone/oracle setup, never an attached user game.
The live check caught a helper-envelope defect requiring rectangular metadata on
Track replies; the typed envelope is now validated separately, with seven new
boundary regressions (1187 Lua contract fixtures pass). Broader terrain/dynamic
barrier transport, controller/GPU parity and job effects remain unverified.
The internal `plan_track` callback now copies pending-job identities/connections
and underlying track terrain into the shared pure construction planner. Preview
uses the native recipe and new-job count for `required` and filter quantities;
unknown or incompatible plan facts produce UnverifiedTerrain. Planning does not
reserve items or mutate jobs. Callback regressions cover pending merges, unchanged
jobs, carved/constructed replacements, malformed facts and recovery; 33 adapter
tests pass. Protected run `build/connected-track-preview-20260930-185619` matches
eight new flat paths and their native material-picker amounts through Godot and
the installed bridge, with the same known startup notice and unchanged save.
Evidence is retained under `live_preview_material_requirements` in the Track
fixture. Pending flat and ramp joins have separate live transport acceptance below;
replacement material quantities, material-list ownership and mutation remain unfinished.
Further native material captures contradict the shared adapter's squared-distance
origin sort and numeric tie ordering. Captured Track choices depend on the destination
and navigation topology; upper-floor stairs and a wall alter native distances.
Two native-only flat captures, `193252` and `193355`, reverse fixture creation order
and reverse the tied cherry wood/dolomite groups across seven tied cases each.
The native choice-construction trace preserves candidate encounter order when
distances tie; it does not compare names or numeric material keys. The second
capture's 2200 candidates have strictly increasing item IDs, but this does not
establish all native candidate enumeration rules. Distances are initially sorted
before the separate unselected-candidate distance refresh in the traced routine.
The retained `candidate_population_trace` now identifies collector `0xa29630`:
all four insertion sites call `0x13ce00`, which lower-bounds by signed item ID,
rejects duplicates and inserts in ascending order. Its ordinary source-vector
pass runs backwards, so source traversal order is not the resulting candidate
order. Together with the stable initial grouping trace, tied groups follow their
first eligible ascending-ID candidate. Recipe-vector setup, flag/container
eligibility and selection refresh still require verification. Runtime must
reproduce these semantics from owned facts, never read native candidate vectors.
Protected `211214` adds sixteen controlled candidate observations in
`fixtures/construction/material_candidates.json`: baseline, fourteen individually
toggled primary item flags and restored baseline. For the ground block in this
Track recipe, dump, forbid, on_fire, in_building, construction, in_job, owned,
removed and encased remove it from candidates. Garbage_collect, hostile, rotten,
trader and spider_web alone do not; the existing shared scanner rejects these
and therefore over-filters this case. Every candidate vector remains strictly
ascending by item ID. The recipe has flags1=0 and flags2=10304 (building_material,
non_economic, allow_artifact). The owned save and paused frame remain unchanged.
These controlled flag changes do not prove natural lifecycle behavior, safe use
after garbage collection, secondary flags or container eligibility. The shared
scanner remains unfinished; do not generalize this case to other recipes.
Protected `211457` adds 29 observations for a direct ground bin and individual
primary/secondary flags. Bin ownership and dumping do not exclude its contents;
forbid, on_fire, in_building, construction, in_job, removed and encased do.
Location_reserved excludes either the bin or block, while the other five tested
secondary flags do not. The source save and paused frame remain unchanged.
The former copied Track flag/bin predicate is removed. These captures remain
native behavioral evidence; current runtime admission comes from the owned native
collector described above. Candidate grouping and route enablement stay separate.
Protected `212023` adds twelve controlled site-group/hidden-tile observations.
Recipe candidate membership remains unchanged; enablement matches nonzero raw
site/item group equality, including a site group without any citizen/resident.
Hidden item tiles do not exclude this block. Actual post-query labels are retained
because the first native operation can rebuild walkability. DFHack's
`Maps::getWalkableGroup` returns uint16: the controlled raw group1000047 becomes
17007 through that helper, while native candidate level_map retains1000047.
Read the full semantic map_block.walkable value for this work. The separate
`construction_material_candidate_enabled.lua` predicate compares complete supplied
site groups without narrowing; the registered candidate check replays all twelve
cases and verifies unknown inputs and label collisions. Mixed-group path/site
group collection and production integration remain unfinished. Earlier211839 and
211931 captures are diagnostic only; all three owned saves remained unchanged.
Protected `212419` verifies Track site-group collection with 36 controlled
mixed-group cases: eighteen marked coordinates, each in both route directions.
For these flat five-tile routes, native enablement follows the four horizontal
cardinal neighbors of each endpoint plus the second endpoint itself. First-endpoint
self, interior, diagonal and vertical markers do not independently enable the
candidate. The native trace deduplicates neighbor groups, then appends the nonzero
destination group even when already present. `construction_track_material_groups.lua`
implements that collection over an independently validated route and injected raw
group reader; missing facts return unknown. The registered candidate test replays
all 36 cases through collection and enablement. Natural connectivity and
production integration remain unverified. The owned save
and paused frame are unchanged. Initial212312 evidence tested only eight neighbors;
two destination-self mismatches led to the additional verified sample.
Protected `212728` adds 36 cases over a two-level stone-ramp route in both
directions. The same endpoint-neighbor samples, each at its endpoint's own z,
plus destination self explain all candidate enablement results. The registered
test now replays 72 flat/elevated collection cases. The owned save and paused
frame remain unchanged. Two attempts to enter a one-tile picker (`212825`,
`212903`) failed the oracle's one-entry-path assumption: same-point native clicks
leave an empty path and stage PLACING. The latter state is retained as diagnostic
evidence, not material-picker acceptance; both saves are unchanged. The collector
rejects routes shorter than two entries. Native same-point preview/controller
behavior remains a separate integration check.
Protected `213447` verifies 42 Track recipe probes: fourteen ground items over
thirteen fixture types plus blocks made from the same stone as a boulder, with
economic-stone restriction off/on/restored. Native membership matches isBuildMat
and applies that restriction only to the raw inorganic boulder; matching blocks
remain allowed. The former copied recipe predicate is removed in favor of the
owned native recipe and collector. Captures `213738` and `213836` establish the
IN_PLAY source vector and melt exclusion; `214209` adds twelve BAR probes,
including accepted metals and rejected fuel/ash/soap, for 54 retained recipe
probes. All items are controlled fixture creations; natural manufacturing and
hauling are not established. The paused frame and owned save are unchanged.
Artifact behavior and remaining containment/production integration stay open.
Protected `214419` adds eight containment states: ground, direct bin, bucket,
nested bin, bucket inside a bin, unit inventory, bin carried by a unit and restored
ground. Only ground/direct ground bin/restored are candidates. The candidate gate
now excludes resolved non-bin/unit containment; missing containment facts remain
unknown. A containing bin in inventory is excluded, consistent with the retained
native c93380 trace. Do not recursively find an outer ground container and infer
eligibility. The registered candidate tests replay all eight states. Source save
and paused frame remain unchanged; natural hauling-job behavior is not established.
`construction_track_material_candidates.lua` composes the verified Track recipe,
flag/containment and site-group helpers into a safe-point semantic snapshot. It
enumerates IN_PLAY, copies item positions/material identities and raw walkable
groups, rejects assigned-stockpile items and returns ascending unique candidate
IDs with enabled state. Read failures/unknown facts and candidate-cap exhaustion
return no partial list. The caller supplies an independently validated route.
Protected `214751` compares complete snapshots with native: baseline2200,
forbidden-block2199 and restored2200 candidates, matching every ID, order, raw
group and enabled bit. Input/source hashes and ordered-vector digests are retained
in `material_candidates.json` composed_scan_capture. The test oracle supplied its
captured native route, so this proves the scanner, not independent route generation
or production dispatch. The registered candidate check also tests ordering,
stockpile/forbidden exclusion, resource exhaustion and read failure. The owned save
and paused frame are unchanged. All five candidate helpers are now embedded in the
cached construction closure. The safe-point diagnostic
`df3d track-material-candidates-read sx sy sz tx ty tz candidate-limit` independently
routes from explicit endpoints, then scans semantic candidates. Protected `215252`
matches all three native paths and all6599 candidate rows across baseline2200,
forbidden2199 and restored2200 snapshots. Native search generation, paused frame
and owned source save remain unchanged. Retained `installed_scan_capture` includes
source and matching built/installed DLL hashes. Protected `215335` also rechecks
all48 material-distance queries through the shared helper initialization. The33
construction-adapter tests,11 candidate tests and14 catalog tests pass. Material
grouping, distance order, native group copy, selection and placement remain unfinished.
Protected `215943` adds complete initial group-membership evidence:33 native groups
per state containing2200/2199/2200 candidates. Controlled copied walkable groups
enable all candidates; this is not natural reachability evidence. The standalone
`construction_material_partition.lua` groups semantic identities and preserves
ascending candidate membership and first-encounter group order before distance
sorting. All6599 memberships replay against native; the registered candidate check
now has14 passing tests. Protected `220500` verifies the embedded partition through
the installed candidate diagnostic: all33 groups per state and6599 memberships/
material identities match native. The scanner copies the semantic artifact-or-
improved predicate and returns `initial_groups` before distance sorting. The cached
scanner factory now receives five helper closures; built/installed DLL hashes match
and33 construction-adapter tests pass. Native generation, paused frame and owned
save remain unchanged. `installed_group_capture` retains provenance. The native
trace keeps artifacts/improved items individual, but none occurred in this capture;
that branch still needs live evidence. Captured group descriptions remain oracle
data only. Most items are outside the isolated movement patch, so native stale
distance values in this capture are not independent-distance acceptance targets.
Native group copy now has a separate acceptance record. Protected `220818` compares
33 identities in ordinary, singleton, seven-item singleton-stack and restored
states. Native item generic-description mode1 for a singleton and mode2 for a
group match all132 native labels; mode0 wrongly includes a stack suffix. Embedded
`construction_material_group_name.lua` checks representative identity, uses those
native description modes without decoration and converts through `df2utf`. Only
ordinary BAR/BLOCKS/BOULDER/WOOD are verified; individual rows and unknown families
return no name. Protected `221040` verifies all132 names and complete memberships
through the installed scanner. The save, paused frame and native generation remain
unchanged. `group_copy_capture` and `installed_group_copy_capture` retain provenance;
the candidate suite has15 passing tests. Non-ASCII raw names were not specifically
sampled. Selection/expansion labels and distance ordering remain unfinished.
The independent initial ordering pipeline is now composed in
`construction_material_order.lua`. It searches from the explicit Track destination
to enabled semantic candidate positions, takes each group's minimum distance and
preserves initial partition order on ties. Unknown/capped searches or unreachable
enabled candidates publish no ordered groups; native stale costs are not emulated.
The cached construction closure receives this fourth helper. Read-only
`df3d track-material-order-read sx sy sz tx ty tz tile-limit` exposes the composition
with separate `status` (candidate snapshot) and `order_status` fields. It does not
dispatch production Materials or reserve items. Protected `221504` compares99
native group rows from60 controlled items in33 material groups: forward, reversed
endpoints and redistributed items, all on a connected5x5 floor. Distances, names
and complete ordered memberships match. Save, paused frame and native search
generation remain unchanged. `installed_order_capture` retains replay evidence;
16 candidate tests and33 adapter tests pass, built/installed DLL hashes match.
Integration across obstacles/elevation, selection and placement remain unfinished.
Protected `221729` extends composed ordering to wall detours and materials on a
second floor connected by stairs, each with reversed Track endpoints. All132
native group distances/names/ordered memberships match;60 controlled candidates
per case. `installed_terrain_order_capture` retains the evidence. Protected `221908`
separately invokes native generic-group select/deselect methods in an oracle:
558 transitions across99 groups establish nearest-unselected selection and
farthest-selected deselection, both breaking ties toward highest candidate ID.
Remaining group distance, selected counts and exhausted/no-op states are recorded.
The native select/deselect captures establish the selection ordering now
exercised by the Godot exact-selection tests. The former standalone Lua selection
kernel and its comparison-only tests were removed; they are not an alternate
runtime implementation. Those direct-method captures alone did not establish
button behavior, stack consumption or placement; subsequent evidence follows.
Protected `222535` adds actual native picker mouse interactions, retained in
`picker_interaction_capture`. Row clicks select one item; None clears the group.
Partial selection changes the nearest-remaining distance without reordering the
list; full selection removes the visible distance. The row shows selected/total
requirement and truncates its label to fit. Escape after partial selection leaves
no buildings or item reservations. With four of five materials selected, All on a
two-item group selects only one more, automatically leaves the picker and creates
five pending Track jobs with five reserved items. Eighteen candidate tests include
kernel replay against these actual-click selections and final reserved IDs. The
owned save and paused frame remain unchanged. This is native workflow evidence,
not DF3D controller/Place acceptance; expansion, search/scrolling, variable counts,
job completion and hauling remain unverified.
Protected `223022` exercises actual native expansion for three ordinary groups.
Individual rows appear immediately below their parent, ordered by distance;
the Iron example puts nearer item3226 before farther3225. Clicking the farther
row selects that exact item, collapse/reopen preserves it and another click is
a no-op. Cancellation creates/reserves nothing. `individual_picker_capture`
retains native frames; equal-distance child ordering and nonordinary/stack copy
remain unverified. The pure selection helper now accepts an optional exact item
ID for this behavior. The order helper returns owned per-candidate ID/distance
pairs, with no partial output on incomplete ordering. Protected `223238` checks
all240 individual costs plus132 ordered groups through the installed diagnostic
across wall/stair/reversed cases. Built/installed hashes match;19 candidate tests
pass. Native generation, paused frame and source save remain unchanged. Production
Material transport still lacks individual IDs and is not accepted by these runs.
Protected `223406` resolves ordinary expanded-child ties: equal-distance Silver
bars41071/41075 display in ascending ID order, unlike highest-ID group selection.
The order helper now retains ascending membership `ids` separately from
`expanded_ids`, sorted by individual distance then ID. Protected `223613` compares
the installed result to actual native expansion for four groups, including that
tie; all eight children match. `expanded_order_capture` and
`installed_expanded_order_capture` retain provenance. Twenty candidate tests pass;
built/installed hashes match and saves/frame/native generation remain unchanged.
Artifact/improved copy and production transport/controller integration
remain unfinished.
Protected `224111` verifies ten ordinary expanded-item labels with seven-item
stacks across BLOCKS/BAR/BOULDER/WOOD. Native generic-description mode0 without
decoration matches those labels, including the native stack suffix; group labels
retain modes1/2. The name helper now accepts an optional individual ID and checks
the same semantic identity and supported family. Scanner candidate records carry
the resulting individual name separately from group names. Artifact/improved copy
remains absent. `installed_individual_copy_capture` retains input hashes and native
comparisons. Built/installed hashes match;20 candidate tests pass. Source saves,
paused frame and native generation remain unchanged. Selecting one seven-item
stack provides one candidate in this picker; actual stack consumption on placement
has not been measured. Production transport/controller integration remains open.
Do not infer a general post-selection sorting rule from these initial captures.
These early captures predate native distance integration. Current behavior and
remaining candidate/route limitations are described above; the retained
`native_material_order_audit` fixture does not imply a second runtime flood.

Material-navigation runtime now uses `construction_material_native.cpp` with
owned requests and restored scratch. The former Lua terrain/opening/facts helpers,
the independent model flood and their comparison-only tests have been removed.
Do not restore them or follow old scratch scripts that import them. Candidate
admission and recipe seed selection remain separate from native distance search.

Retained native provenance in `material_destination.json`,
`material_environment.json` and `material_movement.json` covers the supported
build's tile identities, liquid/temperature boundaries, stair/ramp transitions,
building states and Track endpoint seeds. These captures are historical oracle
evidence; they are not proof that a retired model helper still exists or that
all current candidate/placement flows are accepted. In particular, negative
costs observed for unreachable controlled targets remain diagnostic values,
not valid material distances. Current runtime reports reachability relative to
its own native search generation and restores the prior search scratch.

The `material-distances-read` diagnostic remains available through protected
DFHack lane helpers, but now calls the native implementation. Its retained
legacy tile-limit argument is not a work bound on the native search. Current
ownership and frontier-capacity checks are in that implementation.

The Track site reader in `construction_track.lua` classifies native movement ramps and ramp
support from raw tile identity. All 697 pinned identities are compared with the
supported binary's predicates: four live/dead root/trunk slopes are excluded from
the ramp class; trunk walls, SemiMoltenRock and GlowingBarrier are excluded from
support. These distinctions are not representable by shape alone. The Track site
reader now supplies corrected support and an explicit `movement_ramp` fact; the
callback and world model use that fact for elevation edges and linked ramp/top
marking. A missing ramp fact on relevant nominal ramp terrain is unverified.
Reader comparisons cover all 697 identities, and core/callback tests distinguish
true, false, missing and malformed facts. Prior native room fixtures still pass
but do not establish live tree/hazard behavior. The corrected bridge was rebuilt
and installed with matching binary hashes. Protected Preview regressions on
2026-09-30 (`201205` flat pending Track, `201237` pending ramp Track) each matched
four native ordered paths and material quantities, preserved existing jobs and
reservations, and left the paused clone unchanged. Both runs are
`passed_with_known_issues` for the pinned renderer startup notice only. Protected `201750` additionally matches 20 native Preview cases: ordinary ramp
and fortification controls, four excluded tree slopes, live/dead trunk support,
SemiMoltenRock and GlowingBarrier, each in both directions. Native first and
recomputed paths agree. It is `passed_with_known_issues` for the same startup
notice; the paused clone stayed unchanged. These isolated patches explicitly
share a walkability group. Earlier captures inherited stale walkability after
changing tile types and failed one uphill route regardless of support identity.
This evidence does not justify a directional fortification rule. Follow-up
protected `202443` verifies 24 native walkability cases against the corrected
installed bridge. Non-start sources of elevation edges require nonzero native
walkability; same-level edges and route starting tiles skip this check, and
different nonzero groups are allowed. The reader supplies a strict boolean fact;
missing or malformed facts remain unverified when needed. Core and callback
regressions cover the start exception and false versus unknown behavior. The
follow-up is `passed_with_known_issues` for the pinned startup notice, with the
paused clone unchanged. Natural tree/hazard integration and the remaining native
source eligibility conditions still need acceptance. The former standalone material shape helper has been removed; production uses
the native material flood described above.

The wall capture also exposes a known Preview defect: the first eastward route
detours north in native DF and south in DF3D, despite equal length. Protected runs
`190145` and `190244` failed; earlier flat passes do not cover this case. The retained
`fixtures/construction/track_obstacle_snapshot.json.gz` contains semantic terrain
and eight native cases; the callback replay reproduces one mismatch offline.
`df3d_track_callback_test` accepts an optional third argument naming a Lua replay
script. Resolve the discrepancy before accepting obstacle-route parity. No root
routing algorithm has been changed to fit the counterexample.
Follow-up captures refine this diagnosis: native DF itself chooses north on the
first preview and south on later previews of the same endpoints. In protected
run `build/connected-track-preview-20260930-191253`, all 2205 captured semantic
tile records are identical between the first and ninth previews. DF3D's south
route matches the later native previews. Revealing the surrounding walls does
not remove the first-preview discrepancy. The cause remains unresolved; the
reader could omit relevant facts, and shared native pathfinding scratch is not
established as the cause. Retained evidence is in
`fixtures/construction/track_route_history_snapshot.json.gz` and
`obstacle_route_history` in the Track fixture. The strict live check still fails;
neither an algorithm patch nor acceptance of arbitrary equal-length alternatives
is justified by these observations. Runtime native UI/search-state reads remain
prohibited.
Diagnostic follow-ups retain the discrepancy without ever entering the material
picker, so that interaction is not required. Oracle-only resets of native
pathfinder initialization flags also fail to remove the first-preview mismatch;
these interventions are not acceptance runs. Their bounded cases/traces are in
`fixtures/construction/track_route_initialization_probes.json.gz`. Render-cache
recomputation and ownership of the captured shared search scratch remain open.
The route change also occurs after moving the pointer away/back within the same
Track draft (`192023`), without menu closure or material selection. This narrows
the interaction history required to reproduce it, but does not establish a cause.
Additional protected probes005255/005340/005420 isolate a trace limitation. The
bounded region's2205 path costs are zero before entering Track. Resetting them
immediately before the first destination render changes155 cells, but the render
retains the north route while all46 captured costs remain zero. That post-render
scratch therefore cannot be assumed to describe the producing search. Moving the
pointer off-map before camera reveal still leaves first-north/later-south behavior.
These are diagnostic-only interventions, not parity acceptance or runtime inputs.
See `render_cache_cost_probes` in the initialization-probe fixture. All sessions
remained paused at frame0, source manifests matched and owned DF processes ended.
The producing input/render operation and root cause remain unresolved.
The subsequent005537 transition probe locates the first north route at the render
immediately after camera reveal, before the final target-pointer render. Later
routes also appear at this stage. `input_render_transitions` retains paths, cached
endpoints and per-path costs at changes. This narrows the producing operation;
generation-field ownership and the root cause remain unresolved. The protected
session ended paused at frame0 with unchanged source save. No parity acceptance
or product algorithm change follows from this diagnostic capture.
Protected005730 and005836 verify the generation-field offsets against the native
instructions and the live world object against the callsite argument. The7168-byte
executing pathfinder body matches the installed executable exactly; raw bytes stay
ignored. These checks exclude those field/object mismatches and a patched body,
but do not resolve the first-search discrepancy. Before/after flags and bounded
transition records are retained in `generation_ownership_probes`. Both sessions
ended paused with unchanged source saves. Other callees and intermediate search
state remain unverified; these diagnostic runs do not establish parity.
The010147/010241 probes now establish a causal dependency on native level-map
reindexing in this fixture. Clearing the initially true `reindex_pathfinding` flag
before Track input changes the first obstacle route to south, matching later
previews. Reasserting the flag before case9 reproduces north; cases10/11 return
south. See `levelmap_reindex_probes`. Both protected sessions ended paused at frame0
with unchanged saves. These interventions are diagnostic-only: they do not permit
product suppression of reindexing, native search-state reads, or acceptance of the
cold-reindex mismatch. Ordinary settling behavior and the mechanism by which the
rebuild affects routing still need verification before a runtime correction.
Further tracing identifies lazy group reader RVA0x10afe0 and rebuild0x103e8d0;
the latter resets pathstart to1, sets pathclear and updates shared tile costs and
next_levelmap. The dynamic capture below confirms the surface-reader call chain
executes inside the discrepant route; the subsequent cost capture proves a
causal overwrite in this fixture. `rebuild_mechanism_probe` records
protected230508: replacing the fixture stair pair with floors does not remove the
first/reindexed north route or warm south route. This rejects stair-pair necessity.
Protected230256 queried the installed native material flood three times with
reindex true: distance8 each time, flag unchanged, sampled costs and generation
scratch restored. That probe alone does not explain native negative distances; the projected-validation evidence below narrows that separate issue. Both runs stayed
paused, preserved source saves and closed owned sessions. No runtime workaround,
search-state borrowing or route-parity acceptance follows from these probes.
Protected `build/track-history-upper-walls-20261023-000557` changes only the
upper9x9 floor patch to walls, preserving the lower no-stairs fixture. Cases1,9,
10 and11 all choose south, and reindex stays true at every captured transition.
Thus upper terrain affects whether the rebuild/discrepancy occurs even without
a stair pair. This narrows the trigger; it does not identify the executing callee
or justify a runtime workaround. Paused frame0, source unchanged, owned DF closed.
Single-tile probes000715/000815 further isolate this trigger. With upper walls
except a floor at start+(-1,0,1), obstacle routes remain south and reindex first
clears on the later westward route. Moving the sole upper floor to start+(2,0,1),
beside the obstacle route destination, restores north on cases1/9 and south on
cases10/11; reindex clears during both cold obstacle searches. Static routing
code checks candidate surface eligibility before vertical connectivity through
RVA0xdc1a10, using flags0x101000 for changed elevation versus0x901800 for flat
Track edges. The former can reach lazy group lookup0x10afe0. The dynamic capture
below confirms that chain executes; the terrain intervention does not prove
intermediate scratch corruption or authorize replicating it in production.
Both protected sessions preserved source saves and ended at paused frame0.

Protected `build/track-rebuild-stack-20261023-131317` confirms the executing
call chain during the first producing reveal render. A one-shot debugger stopped
at fingerprinted rebuild entry0x103e8d0 after fixture preparation. The stack is
Track search return0x26a7d9 -> connectivity0xdc1af8 -> surface0x14ae6b4 -> lazy
group reader0x10b011 -> rebuild0x103e8d0. The original instruction and RIP were
restored before continuation, and the debugger detached. Native case1 routes
north; identical cases9-11 route south. No reindex flags were written. All11
native cases completed paused at frame0; source stayed unchanged and owned DF
closed. `rebuild_mechanism_probe.dynamic_call_chain` retains the stack, paths,
transitions and hashes. The earlier131240 capture obtained the same stack but
failed afterward in an obsolete terrain-export helper; it is not a passing run.
That stack capture establishes rebuild execution inside an active search. The
subsequent paired capture below isolates its cost overwrite; neither establishes
a safe runtime wrapper or acceptance of the cold-route mismatch.

Protected `build/track-rebuild-cost-20261023-131617` captures1323 tiles'
cost/tag/walkable fields immediately before rebuild and at return0x10b011.
The rebuild changes155 sampled costs and162 walkable groups. The two already
tagged search tiles change cost1 and257 to302690; all sampled direction tags
stay unchanged. Pathstart stays1, pathclear changes0->1, next_levelmap5417->5420,
and reindex clears. The first native route remains north. In the paired protected
`build/track-rebuild-cost-restore-20261023-131733`, the debugger restores only
those1323 sampled costs after rebuild; rebuilt groups and all scalar changes
remain. The first route becomes south and exactly matches later identical native
previews. Both runs complete11 cases paused at frame0, preserve source saves,
remove diagnostic breakpoints, detach, and close owned DF. See
`rebuild_mechanism_probe.active_cost_overwrite` for full sampled values, paths,
stacks and hashes. This establishes the overwrite as causal for this fixture.
It does not authorize runtime debugger hooks, global native search-state borrowing,
or other departures. The maintainer separately approved keeping the stable
first-preview Track route on2026-10-23 ("Yes, keep the stable route"). Product
routing remains unchanged; no global cost restoration, suppressed reindexing,
or debugger instrumentation is introduced. Eligibility and the remaining native
routing/terrain coverage requirements remain. The material-ordering exception
is independent.

Protected010407 establishes ordinary settling without flag writes: a four-cell
native Track preview and cancellation clears pending reindexing, changing the
level-map counter5417->5420. All11 subsequent ordered native paths match production
bridge/Godot Preview under the unchanged strict comparator. See
`ordinary_native_settling`; known renderer notice only, paused frame0, unchanged
save and owned process ended. This accepts those settled-state paths, not the
first search with reindex pending. Product warmup/suppression is not authorized
by this test; the cold-search mismatch remains open.

The interior-ramp negative material-distance case is narrowed by protected
`build/track-negative-distance-native-20261023-084550`, retained in
`fixtures/construction/track_negative_distance_probe.json.gz`. Native caller
RVA0x3bcb50 validates destination x/y at `selection_pos.z` before calling the
material flood, then validates again at window z. Here the visible destination
(62,46,171) is a floor, but its projection (62,46,170) is SoilWall. Native
validation at that projection returns tile6, `Blocked at this location`, whereas
the restored visible request contains tile0. Track's footprint is one tile and
flood0x8d4f20 admits only mask0/1: the temporary blocked mask leaves no seed while
the generation advances. Group distance code0x8d69a9 subtracts the generation
without checking reachability. Event snapshots show generation1250001 with
sampled old costs0,1,513 after the click; six enabled candidates report-1250001.
Both independently owned actual-destination and projected-coordinate queries
return reachable distance99, with sampled costs/generation restored. Thus merely
changing seed elevation misses the temporary validation mask. Static call order
and the native projected evaluation support this mechanism; no instruction-level
trace of the flood call was captured. The run preserved the source and closed its
owned session. This diagnostic did not change runtime behavior. The maintainer
decision below removes reproduction of stale ordering as a requirement; cold
routing initialization remains unresolved.

The history probe `build/track-material-history-native-20261023-084910`
confirms an observable dependence on unrelated native menu activity. Repeating
Track preserves the all2105-candidate tie, but opening and cancelling a Floor
picker before the identical Track selection produces53 distinct distances and
changes material group order and preferred items. For example, the first dolomite
group selects5024/4981/4917 initially versus5024/4863/4254 after Floor. No intervening
construction was placed. Both Floor origin and destination variants show this
change. Retained `history_probe` records the rows; source unchanged and owned
session closed. Exact ordering here cannot be inferred from current stock and
Track intent alone. On 2026-10-23 the maintainer authorized fresh DF-calculated
distances instead of reproducing this apparent stale-distance bug. The existing
Track ordering path already calls the owned native distance query at the actual
destination and rejects unreachable or invalid distances. This decision covers
material ordering only, not placement, eligibility or cold-route initialization.
It adds no new runtime implementation or live acceptance evidence. Broader
construction work and verification remain active.

Protected `build/track-fresh-history-native-20261023-113644` verifies this policy
through the installed production ordering diagnostic. Repeating Track, opening
and cancelling Floor at the origin, and doing the same at the destination return
identical 2157 candidate records, 2105 fresh distances and 32 ordered groups.
Native menu costs change from one distinct distance to 53 across those histories.
Each query preserves full-map path/walkability and item-state digests, plus the
observed menu, counters, cursor and navigation state. The source manifest remains
unchanged and the owned session closed without saving. The fixture's
`fresh_order_verification` retains full records and hashes; the candidate-gate
suite replays the fresh distances through ordering and passes all 29 tests.
This is ordering/query-restoration evidence, not viewer or construction effects,
and does not establish the separate Track candidate eligibility pipeline's parity.
The first harness attempt failed on a missing diagnostic local; it is not counted.

Independent pending-job Preview acceptance now covers flat and ramp joins:
`build/connected-track-pending-preview-20260930-192241` and
`build/connected-track-pending-ramp-preview-20260930-192346` each match four native
ordered paths and material-picker quantities through Godot/protocol34. Three-tile
joins require two new materials; five-tile crossings require four, in both directions.
Native initial jobs are created through the Track menu, and the ramp run confirms
a TrackRampEW job. Final DF readback shows unchanged building IDs, subtypes, stages,
job IDs and item reservation flags. Both runs report passed_with_known_issues
(known startup notice only), paused/frame0 and unchanged saves. Evidence is under
`live_pending_preview_requirements` in the Track fixture. These are read-only
DF3D previews; placement, material selection, zero-new-job overlap, completed/carved
replacement and elevation-changing requirement transport remain unfinished.
Material queries/placement, stale-target mutation checks and controller integration
are unfinished. Typed outcomes introduce no visible substitute copy.

Management protocol32 appended required Track Stop options to its construction
Preview/Place requests: friction10/50/500/10000/50000 and dump direction0 none,
1 north,2 east,3 south,4 west. Other buildings/actions reject this payload.
The channel is `Local\df3d_management_v32`; older peers cannot connect and all
bridge, model and extension binaries must be rebuilt together. Track Stop controls
and all25 native placement profiles pass targeted acceptance. Keep this breaking change isolated when
commits are authorized.

Protocol31 introduced explicit Roller speed, retained in32. Zero preserves the native
default; explicit values10000..50000 in10000 steps are valid only for Rollers.
The draft defaults to50000 and uses the five native icon buttons; changing speed
invalidates geometry/material readiness. Native constructor fields receive the
selected value. Root18/18, adapter22cases and `roller-speed-godot-fixed` pass.
Speed-specific acceptance now passes: native capture `roller-native-20260930-133828`
clicks all five original buttons and records10000..50000 with50000 default; protected
`construction-acceptance-20260930-133402` reads every requested speed from native
buildings and verifies unchanged source files. `roller-speed-gpu` exercises actual
viewport clicks on all five controller buttons and captures each selection; only
known engine diagnostics occur. Missing8px button gaps were corrected and checked
by `roller-native-spacing`. Evidence is in `fixtures/construction/roller_speed.json`,
retained to prevent default-speed and button-order regressions. The Godot origin
remains2px right of native and hint wrapping differs; this is not whole-panel
pixel-identical acceptance. The live run's old D6 summary sentence incorrectly
claimed no speed field; its native assertions and five markers establish the effect.
The follow-up report now uses measured readbacks and passed in the Track Stop run.
Construction remains hidden pending other parity work. Keep this
breaking contract change isolated when commits are authorized; no commit/push is
authorized here.
Track Stop native controls are now captured in `fixtures/construction/track_stop.json`
to provide the implementation oracle for this path. Protected
capture `track-stop-native-20260930-134626` verifies all25 direction/friction combinations,
five return-to-None cases, repeat selections and cancel/reopen defaults, with unchanged
source files. Friction values are10/50/500/10000/50000; no dumping clears both offsets.
Reopening resets to no dumping and50000. Protected `construction-acceptance-20260930-140006`
verifies all25 profiles on actual native buildings, same-process reload/cache reset,
and unchanged source saves. `track-stop-godot-fixed` passes draft/controller checks
and all25 GPU pointer pairs. Live/GPU runs have only known engine diagnostics.
The fixture retains profile readbacks and evidence hashes. Relative icon placement
matches native; Godot's origin is2px right. Whole-panel parity and an end-to-end live
pointer-to-placement sequence remain unverified. Pressure Plate and connected Track
are still unfinished; this does not expose the Construction screen.

Construction's diagnostic and material-status labels are hidden: their internal
transport/recovery strings have no native copy or layout provenance. Receipts,
partial-placement evidence, invalidation and no-replay guards remain intact.
`construction-diagnostic-copy-20260930` passes controller/material tests and GPU
pointer captures with only known engine diagnostics. This prevents diagnostic
prose from leaking into the UI; it does not complete native error presentation or
the inspection sheet. Do not restore those labels without native evidence.

Management protocol33 appends an explicit PressurePlateOptions profile to the
construction request. Rebuild bridge, model clients and extension together; the
channel is `Local\df3d_management_v33` and version32 peers cannot connect.
Preview/Place for `Trap:PressurePlate` requires the profile; other requests reject
it. Validation retains disabled ranges, finite cart weights and native creature
band endpoints. This breaking change should remain a separate migration commit
when committing is authorized. No recording migration invents these options.
Semantic placement and creature-example transport have protected live acceptance;
rendered controls have GPU/pointer acceptance. Live pointer-to-placement, full
Construction lifecycle and simulation trigger effects remain pending.

`fixtures/construction/pressure_plate.json` retains a partial native oracle from
`pressure-plate-native-20260930-140915`, with unchanged source saves. The native
creature minimum defaults to5000, despite the structure initializer's50000.
Trigger toggles, reset modes, recorded fluid-range clicks, cart-weight steps and
creature size-band clicks are captured. The independent reader in `construction.lua`
now derives examples from aggregate raw size, frequency and flags, plus the game
mode and perspective race. It never reads native widget state. Protected
`pressure-plate-reader-20260930-144401` matches all200 buckets across142 controlled
states (28,400 comparisons), restores the native baseline and preserves source files.
The fixture retains evidence hashes and coverage limits. Adapter25cases, catalog
regression and bridge build/install pass. The first Catalog page now transports its
200 ordered examples through management and the model to Godot. Captured IDs/names remain world-specific
evidence, never runtime constants. Full Pressure Plate workflow and trigger effects are unfinished.
Further protected captures `pressure-plate-controls-20260930-144803` and
`pressure-plate-scroll-20260930-150005` retain all72 fluid ranges,252 cart endpoint
actions and trigger-toggle persistence. Crossing a cart endpoint moves the other;
disabling a trigger preserves its range and the recorded citizen setting.
Scrollbar arrows reach offset185 (15 visible rows out of200). Unnamed example rows
display parenthesized decimal thresholds, such as `(19000)`, rather than blank text.
Selecting the final row sets200000..200999: do not confuse that trigger range with
the independent example-search ceiling200000999. The Range summary also uses native
numeric fallback: `Range: (186000) to dragon` and `Range: (186000) to (186000)`.
Wheel/page/drag behavior is established by the later scroll-input capture below. Both owned sessions ended with source
files unchanged; these captures do not establish placement or Godot acceptance.
Separately, `construction-acceptance-20260930-150929` verifies twelve semantic
profiles on actual native buildings, checking all six flags and eight range fields.
It passes with only the known Godot separate-renderer startup notice, preserves684
source files and passes same-process reload/cache reset. Its old D5 summary sentence
incorrectly says the catalog refuses the options; per-profile native assertions
are the placement evidence, and the report generator is corrected for future runs.
The fixture retains this distinction. Adapter27tests (394 profile constructions),
catalog, core18/18, bridge/extension builds and the two construction Godot tests pass.
This does not prove pressure-control pointer input or linked-building trigger effects.
`construction-acceptance-20260930-152306` separately verifies all200 transported
rows against current native raw facts and the retained native UI baseline. It also
repeats the twelve profile placements and same-process reload, preserving684 source
files, with only the known Godot startup notice. ConstructionState metadata is part
of the same uncommitted management33 migration. Empty metadata is permitted on later
pages; a present list must have200 ordered thresholds and valid identities/names.
The controller owns its copied catalog examples and clears them on close or world
replacement. Draft methods preserve native defaults, range and crossing rules,
toggle persistence and final creature bands; placement requests own their profile.
The clean `pressure-examples-godot-fixed` gate replays72 recorded fluid ranges and252
cart actions plus creature choices, tests metadata lifetime, and rejects stale
draft readiness. Adapter28tests, catalog and core18/18 pass.
The `construction_pressure.gd` component now renders installed native reset/trigger,
fluid, cart and scrollbar artwork on the captured8x12 cell grid, with native labels,
CP437 character226 for cart weight, and parenthesized thresholds for unnamed rows.
Protected `pressure-plate-scroll-sync-20260930-153854` establishes row and shifted
wheel steps1/15 over rows and bar, and drag offsets85/156/185/0; the companion
`pressure-plate-scroll-inputs-20260930-153708` establishes the page/arrow click sequence.
Synchronous injected input was necessary because yielding lets native polling clear
the injected pointer; older no-op trials were an instrumentation limitation.
`pressure-controls-gpu-final` passes controller/draft and rendered pointer checks
with only documented Godot diagnostics. Native-sized row hit areas prevent overlap;
wheel input over rows reaches the native scrollbar, and requests lock the controls.
The fixture retains four visually inspected screenshots under that immutable run.
Native lifecycle capture `pressure-plate-lifecycle-20260930-155421` establishes that
Escape/right-click cancellation from materials and successful placement return to
the map with the captured preference; reopening resets all options. The earlier
claim that Pressure Plate lacks a generic placement/Keep-building pane was a
capture defect, corrected by `native_placement_hover_correction` in the fixture.
Native mouse hover/tracking exposes both panes, now restored in the controller.
`keep_options_reference` now proves that checked placement stays open and resets
the Pressure Plate trigger options; the controller's forced-close exception is
removed. Pressure Plate Closest/exact materials remain pending. Regression checks pass in
`pressure-lifecycle-controller-fixed`; the preceding GPU capture passes with known
Godot diagnostics. The native evidence is retained in the fixture's lifecycle
section. Protected `construction-acceptance-20260930-160216` also passes actual
viewport launcher/menu/profile/map/material input, Escape/right-click cancellation,
reopening defaults and native placement readback of all selected flags/ranges.
Both option/material screenshots were inspected. The run is
`passed_with_known_issues` for the documented Godot thread notice; the owned DF
process stopped without saving and its source files were unchanged. Whole
outer-panel pixel comparison and actual trigger effects remain open; the Build
editor stays hidden.

Session protocol v9 replaces implicit SaveReturn selection with a request-scoped
destination catalog and explicit ExistingDestination, NewFolder or NewTimeline
intent. The channel is `Local\df3d_session_v9`; rebuild bridge, model clients and
Godot extension together. v8 peers cannot connect. Map recordings and management
protocols are unchanged. Preserve this breaking session change as a separate
commit when preparing commits; no history change is authorized by this note.
The legacy boolean `sendSave(true)` now rejects without sending. Call
`sendReadSaveDestinations(epoch)` first and use its private receipt and opaque
destination IDs with `sendSaveReturn`. Missing catalogs are unavailable, not empty.
The CLI supports read-only `destinations`, or explicit `save-return existing
<folder>`, `save-return new-folder`, and `save-return new-timeline <name>`; each
write obtains a fresh catalog on the same client. Timeline input is metadata bytes,
separate from checkpoint filenames. Native revalidation never substitutes another
destination. Originating request epochs survive fortress unload in receipts.
The in-progress v9 contract also distinguishes `UnknownOutcome` (status4) from a
pre-write rejection. Once native save submission has occurred, inability to verify
completion must not claim that nothing was written. The owner retains the draft
and records an unknown result without closing or replaying; the CLI returns5 for
unknown outcomes and3 for rejection. Native overwrite confirmation still proves
that its writer has not started and can be rejected/cleaned up. This distinction
is under offline and protected failure-path acceptance; do not treat the earlier
successful-save evidence as proof of write-failure handling.
The world model also preserves an unknown save outcome when its transport proves
the producer process or generation has ended. It retains the submitted sequence,
action and originating epoch before releasing the channel, so Options can settle
that request even if the replacement producer remains at title. Missing snapshots
alone do not trigger this transition. A pre-receipt public refresh now preserves
the local request epoch as well. `save-producer-loss-ctest.log` passes all18 root
checks, including real shared-memory transport tests before acknowledgment and
after a pending receipt/generation replacement. `native-save-producer-loss-20260930`
passes the Godot owner check without diagnostics. Protected real-game run
`producer-loss-20260930122416` finishes `passed_with_known_issues` (known threading
notice only), including all-root and every owned-save preservation. With native
execution held, Godot queues an explicit existing-destination save; the bridge
is disabled before consuming it. Options settles unknown with the original
sequence/epoch, keeps its dialog and reconnects to a replacement DF process at
title without replay. Native evidence proves no writer started and paused frame0
was retained. `native_save_effect.json.producer_loss_before_consumption` retains
the compact outcomes and proof hashes. This establishes producer loss before
consumption, not interruption or unverifiable completion after a writer starts.
Destination-catalog reads use a pre-result rejection on verified producer loss,
retaining their sequence/action/origin epoch but supplying no catalog. This
releases the Options request owner without inventing an empty successful list.
`catalog-producer-loss-ctest.log` passes all18 root checks, including shared-memory
producer replacement during an outstanding read. The Godot owner check in
`native-catalog-producer-loss-20260930` also passes cleanly, including replacement
title without replay or opening a chooser. The protected save-loss run
predates this read-loss follow-up and does not establish its live acceptance.
Existing-destination completion now checks the exact selected path and requires
its nonempty `world.sav` size or modification time to change after native
submission. An unchanged pre-existing file cannot establish success; uncertain
completion uses UnknownOutcome. `session_save_file.h` covers missing/empty files
and regular-file metadata. The full110-case bridge policy suite passes, including
real temporary-file tests for unchanged, changed-time, changed-size, empty and
non-file destinations. These are supplementary completion evidence, not a
replacement for native progress/identity checks or protected overwrite/reload.
Protected Godot overwrite `godot-existing-20260930114520` loads owned region17
and selects owned region18 after separately backing it up. The selected world
file changes, no new save folder appears, and a test-only fortress-name marker
reloads from region18 with the same world/timeline identity. The run finished
`passed_with_known_issues` (only the known Godot threading notice), including
final all-root/prior-save preservation. Hashed evidence is retained in
`native_save_effect.json.godot_existing_destination`. This proves the successful
explicit overwrite path. Protected `destination-guards-20260930120029` also finishes
`passed_with_known_issues` (known threading notice), including all-root and every
owned-test-save preservation. Two independent clients establish that a newer
catalog invalidates the older client's write authority; changing only loaded
timeline metadata then establishes rejection when native eligibility changes.
Both return Rejected without a saved identity, native writer or fallback. Native
menus close, paused frame0 is retained and the metadata fixture is restored.
`native_save_effect.json.destination_guards` retains compact receipts and hashed
native/protection evidence. These checks do not establish interrupted-writer
UnknownOutcome, producer death, replacement fortress or deleted-folder behavior.
Implementation is under acceptance. The single-destination native query and CLI
new-timeline save/reload pass, including prior/all-root save preservation. Effect
`explicit-timeline-20260930111642` creates ACTIVE region17 with the requested40-byte
timeline, preserving world IDs and reloading paused frame0. Its hashed proof is in
`native_save_effect.json.explicit_new_timeline`. Other effects and full Godot
workflow checks are not yet complete, and Options remains hidden.
The new `tests/native_options_return_live.gd` writer exercises the actual Options
pointer path, current catalog, cancelled timeline draft and explicit same-timeline
new-folder request. It requires a protected runner with the verified all-root
backup, owned source manifest, native effect/reload verification and final
preservation. Protected `godot-return-20260930112842` passes with only the known
rendering-thread notice, including all-root/prior-test preservation. It creates
ACTIVE region18 on region17's timeline, retains the originating epoch after
unload, closes Options on the matching receipt and reloads exact identity at
paused frame0. `native_save_effect.json.godot_same_timeline_folder` retains the
receipt, screenshot/native/reload evidence and hashes. This uses viewport events
in the standalone Options scene; main-scene and physical OS input remain open.
Protected `godot-timeline-20260930121052` also finishes `passed_with_known_issues`
(known threading notice only), including all-root and prior-test preservation.
The actual Options input path selects NewTimeline, enters the requested40-byte
metadata, suppresses repeated Enter while pending and closes on the matching
receipt after unload. Native creates ACTIVE region19 and reloads the exact
timeline/world identity at paused frame0. `native_save_effect.json.godot_new_timeline`
retains the evidence and hashes, including the naming screenshot. Empty and
non-ASCII timeline save effects, interrupted native writers and full Options
integration are not established by this ASCII metadata case.
Native `native-quit-effect-20260930-124331` passes the QuitWithoutSaving effect:
the exact captured confirmation target returns the same owned process to title,
the bridge reports Menu with fortress epoch0, and reloading region19 discards an
in-memory fortress-name change. Exact source/world/timeline/map identity reloads
paused at frame0, and every source-save file remains unchanged. The native effect
and proof hashes are retained in `native_save_effect.json.native_quit_without_saving`.
This is native behavior evidence for00-E17. The ongoing v9 implementation adds
QuitWithoutSaving action9 and Unloading phase7 across bridge/model/extension and
the confirmed Options owner. It requires the originating fortress epoch, accepts
no save destination, suppresses duplicate confirmation and preserves an unknown
outcome on producer loss. Menu/epoch0 establishes completion only after native
unload. Root CTest18/18 and `native-quit-owner-stable-20260930` pass offline.
Protected `godot-quit-effect-20260930-130615` passes with only the known Godot
threading notice. Cancel dispatches nothing, Escape retains confirmation, repeated
confirmation sends once, and matching success closes Options at native title.
Reload discards the in-memory change and restores exact world/timeline/map identity
paused at frame0; all source files remain unchanged. Evidence is retained in
`native_save_effect.json.godot_quit_without_saving`. The initial run125934 failed
to unload because the confirmation flag preceded rendering; requiring the rendered
native prompt before selecting Quit fixes that stale-screen target. The protected
rerun covers this regression. No save destination was selected in this lane.
Main-scene/global physical input and protected Quit producer-loss remain open.
`Restart-Df3dFortress -Route inprocess` uses this semantic Quit to retain the
owned DF process and bridge DLL across reload. It requires verified title/epoch0
before loading, then the same PID, a different nonzero epoch, exact save identity
and paused state. A rejected, unknown or timed-out unload does not retry or fall
back to process restart. The default `restart` route is unchanged. Both routes
retain the lane mutex, save verification and ownership guards. The helper's
offline regression covers both routes, including uncertain unload/no subsequent
load and invalid title/reload identities (`inprocess-reload-full-test.log`).
The protected `reload_lane_test.ps1` can reuse an existing disposable owned save
with `-OwnedSave` and `-OwnedSaveManifest`; it validates the per-file SHA256 list
before launch and limits preservation checks to that source for this no-save
lane. Omitting these arguments retains the original clone/all-root checks.
This does not reduce preservation requirements for any write-capable save test.
Protected `reload-lane-20260930-131207` passes both same-process rounds with only
the known Godot threading notice. Each changes the epoch while retaining PID43924,
discards unit988's unsaved nickname marker and leaves all686 source files unchanged.
Godot settles each old request as unknown without replay. Compact evidence is in
`native_save_effect.json.same_process_reload`. Domain-specific retained-DLL reset
assertions for work orders, construction and reports still need separate acceptance.
Work-order run `work-orders-acceptance-20260930-131817` now passes the complete
existing driver with known Godot diagnostics only, including same-process reload:
all4 retired native objects remain retained, materials restart at0/total, the
catalog matches the exact region5 oracle, and source files remain unchanged.
The source clone was verified file-for-file against region5; the preceding region19
run passed reset checks but was incomplete for catalog provenance. Retained evidence
is `native_save_effect.json.work_orders_same_process_reload`. Exact World changed
receipt observation and the original first-pending-build trigger remain live gaps.
This is reset/driver acceptance, not approval of inherited work-order departures
or editable-screen exposure. Construction/report follow-ups remain open.
Construction run `construction-acceptance-20260930-132220` also passes the existing
driver with the known threading notice: same PID/new epoch, materials restart at
0/total, unchanged source files, final pause and restored preferences. Evidence is
`native_save_effect.json.construction_same_process_reload`. Its summary still
records real native mismatches: unsupported PressurePlate/TrackStop options and
Rollers constructor-default speed, alongside incomplete comparisons. Those are
product defects, not accepted exceptions; reset coverage does not authorize screen
exposure. Exact reset receipt, first-pending-build trigger and mid-Place reload
remain live gaps. Reports08-B implementation and acceptance are separate open work.
Reports dispatch audit (2026-10-01): the approved spec's zoom-NONE exclusion is
contradicted by native evidence. Protected capture042155 confirms both migrant
and guild reports with stored coordinates recenter for NONE and Generic zoom.
Negative x=-1 is a valid stored off-map target; native recenters at the map edge.
All -30000 coordinates have no button and clicking there leaves Reports open.
The clicked row and camera reset are verified; screenshots inspected; owned
DF1544 ended at frame zero with an unchanged clone and clean captured logs.
See `fixtures/reports/recenter.json`. Earlier e11's guild-button discrepancy
remains a context/refresh question, not an established type restriction. The
first041944 capture clicked old rows and is explicitly inconclusive. Production
Reports protocol/UI work and broader coordinate/refresh acceptance remain open.
Historical "history truncated" and progress copy prescriptions are withdrawn
unless native-sourced. Protocol versions must advance from current peers, not
stale spec values. Notifications adapter mocks now enforce native vector bounds
and Item=1/Unit=2; its pass is regression evidence, not Reports UI acceptance.
Management v40 now corrects Reports coordinate transport: `reports.lua` preserves
stored targets regardless of zoom kind or map reveal state; native x=-30000 is
absent. Signed 16-bit wire validation accepts negative/off-map coordinates and
keeps explicit presence flags distinct from wire -1 defaults. The legacy
`position_visible` names mean recenter-target presence, not revealed terrain.
Migration: region/defaults 39 -> 40 on both peers; no report fields added, no old
recordings rewritten. Older peers must rebuild because their validators reject
native negative coordinates. Session remains v9. Core19CTest, focused adapter,
contract generator check, extension build/import and bridge build/install pass.
Protected043107 verifies all seven native fixture rows through Godot ReportInspect
and ReportList after the standard Catalog handshake, with exact target equality.
It is passed_with_known_issues (only the documented startup/finalize/leak notices),
frame zero and unchanged clone. Failed042956 omitted the harness handshake and
is not acceptance evidence. Reports UI/tabs and broader live cases remain open.
Native Reports membership captures043401/043619 reject the spec's old All-source
assumption. Four migrant rows remain visible independently of announcements-vector
membership and announcement flags. A controlled sweep of all356 non-sentinel
announcement types finds233 shown/123 omitted from All. Alert categories are not
sufficient: GENERAL is mixed; FOOD_WARNING appears despite its DEATH category,
while four other DEATH types do not. fixtures/reports/tab_membership.json records
the per-type evidence. Native Tab views must remain distinct from the existing
raw Flat announcements_only contract. Named-tab and unit-log membership remain
open. Both protected sessions ended at frame zero with unchanged clone manifests
and clean captured logs; native text was checked for all thirty sweep batches,
with representative screenshots visually inspected as qualified in the fixture.
Protected044138 captures native Tabs widget membership for all356 injected types.
The native All list agrees exactly with the earlier rendered sweep; every one
of its233 types belongs to one named tab. Research breakthroughs are World,
correcting the spec's General mapping. `bridge/plugin/report_tabs.lua` contains
this semantic classification; `tools/test_report_tabs.py` checks every type
against the independently captured tab rows and is registered in the core QA
manifest. Management v41 integrates the classifier and fresh-snapshot tab paging
through bridge, wire validators, world model and Godot dictionaries. Flat keeps its
legacy stream semantics; Tab uses native membership, ascending ID order, forward/
backward cursors,64-row/128-KiB text pages,25 counts and trimming metadata. Rows
preserve native colors, brightness, zoom kinds, hidden-position flags and speaker
IDs. Unknown types fail explicitly; no native UI state or retained pointers are
runtime inputs. UnitList, UnitLog and Entries selectors remain rejected.

Protected `reports-tabs-live-20261001-050651` compares compiled public replies with
native widget children for all22 announcement tabs in both directions (44 walks;
All233 rows/four pages each way), raw row metadata,25 counts and Flat newest-first
regression. Details and limits are in fixtures/reports/tab_membership.json.
DF8796 closed at frame zero, owned clone unchanged. Diagnostics classify as
passed_with_known_issues (separate-thread notice, device-finalize, shutdown-object
pair), with none unclassified. Attempt050553 is not acceptance: its harness
compared JSON float arrays with bridge integer arrays before normalization.
Core19CTest, four targeted contract/adapter checks, generator validation, matching
peer builds and clean editor import pass. Session remains v9; management v40 peers
must rebuild for v41. Added fields use unknown/absent defaults; old recordings do
not acquire inferred metadata. Reports UI, unit-log views, alert-button references,
named-tab visual/navigation parity and broader live refresh cases remain open.

Native unit-row capture `reports-units-native-20261001-051105` adds108 exact
Combat/Sparring labels in fixtures/reports/unit_rows.json. The standalone
report_unit_profession.lua helper matches those rows, preserving caste-specific
animal names and native capitalization, and mapping Diagnoser to Diagnostician
as well as Swordsmaster to Swordmaster. This corrects the spec's species-only
animal rule. All97 Combat rows survive with expired references;11 Sparring rows
retain5765 references. The helper is not embedded or exposed by UnitList yet;
custom/agitated/full-enum cases and unit-log UI acceptance remain open. All three
owned captures ended paused/frame0/unchanged clone; successful051105 logs clean.

`report_unit_page.lua` adds fresh safe-point UnitList paging with native order,
nonempty-log membership,64 rows and revision-checked cursors. The core manifest
check covers recorded membership, paging, stale list changes and input/size
limits. Protected051358 matches all108 native unit rows over those pages with
clean diagnostics, frame zero and unchanged owned clone. This remains helper-only
acceptance; compiled UnitList transport and its consumers remain pending.

`report_unit_log.lua` reads native unit references at each safe point and skips
expired IDs, preserving chronological order with bidirectional ID cursors and
bounded pages. The core helper check covers10000 references, expiry, growth,
trimming and payload limits. Protected051639 verifies216 directional walks across
108 real unit logs (384 pages,5765 retained references) against independent raw
log IDs; unchanged clone/frame zero,clean diagnostics. This is data-helper
acceptance only; UnitLog protocol integration and native log-view UI acceptance
remain pending. See unit_rows.json.log_helper_capture for scope and provenance.

Management v42 integrates UnitList and UnitLog through compiled bridge, model and
Godot dictionaries. Requests add unit/category selectors, list cursors and exact
positive revisions; replies add bounded native unit rows. UnitList preserves
expired-reference/dead membership and rejects stale revisions. UnitLog pages
retained IDs in native order. Both compose25 tab counts; Entries stays rejected.
All peers must rebuild for v42; old recordings retain absent unit fields and do
not acquire inferred facts. Session remains v9. Core19CTest, targeted codec/Lua/
adapter checks,generator and both peer builds pass; editor import is clean.
Protected `reports-unit-wire-live-20261001-052646` matches108 native unit rows and
216 log walks/384 pages/5765 references through public requests. DF21284 closed
at frame zero with unchanged clone; passed_with_known_issues, only documented
Godot thread/finalize/shutdown signatures. Attempt052504 exposed missing helper
message; fixed with empty protocol message and an integrated adapter regression.
See fixtures/reports/unit_rows.json.compiled_transport_capture. Helper-only
limitations above are superseded for transport; native UI, Entries/session alert
references and broader stale/refresh/profession acceptance remain incomplete.

Entries preparation adds an unembedded report_entries.lua factory and a bounded
readAlertButton snapshot helper. Offline checks cover source ordering, expiry,
duplicates,limits and UTF-8 truncation metadata; all19 core tests pass. Recorded
e11 mixed-popup row order is retained in fixtures/reports/alert_entries.json and
checked independently. These helpers are not public transport acceptance: current
management42/session9 still lack Entries and ALERT-button references. Stale-unit
popup behavior and complete long-text presentation require further native checks.

Protected `reports-entries-native-20261001-053415` corrects Entries semantics:
native popups skip missing report/unit references and preserve duplicate references
of both kinds in source order. The standalone Entries helper and fixture tests now
match those native rows; spec uniqueness/refusal requirements are superseded.
See alert_entries.json.expiry_duplicate_capture. Owned DF34892 closed at frame0,
clone unchanged,clean logs. Public Entries integration remains pending; existing
non-Entries wire uniqueness checks are not changed by this preparation.

Session v10 exposes ALERT-button report IDs,count and completeness from the native
reference vector through model and Godot poll_session. It preserves duplicates
and source order, bounds the delivered vector at256, updates publications when
references change and resets on fortress loss. Management stays v42. All peers
must rebuild for session10; old recordings default to empty references rather
than inferred alert contents. Core19CTest,peer builds and clean editor import pass.
Protected `reports-alert-session-live-20261001-054048` verifies one persistent
consumer across initial,duplicate,257-reference partial and clear states, with
successive revisions6-9. Owned DF4976 closed/frame0/clone unchanged; only known
Godot thread/finalize/shutdown diagnostics. The first053949 harness parse failure
is excluded. Fixture alert_entries.json.alert_session_capture records evidence.
Public Entries management transport,unload-specific live acceptance and complete
alert/Reports presentation remain open.

Management v43 exposes Entries for explicit report IDs and unit/category refs,
including repeated refs and missing report IDs. All codecs and validators preserve
native source order; missing units are omitted. Other views keep their uniqueness
checks. The Godot required-id rule applies only to Flat inspection. Session stays
v10. Rebuild management peers; old recordings default to absent entry references.
Core19CTest,targeted codec/Lua/adapter checks,peer builds and clean import pass.
Protected `reports-entries-wire-live-20261001-054906` matches the controlled native
popup's five rows,including both duplicate kinds and missing refs,through public
requests. Five malformed requests are rejected locally. Owned DF47552 closed at
frame zero,clone unchanged; only documented Godot diagnostics. The first054732
attempt exposed and corrected the extension's legacy id requirement. Evidence and
limits are in alert_entries.json.compiled_entries_capture. This completes neither
Reports presentation nor long-text/stale-popup acceptance; all five views now have
public data paths,with additional native parity work still outstanding.

Reports presentation preparation adds reports_state.gd for panel-owned tab rows,
selection,unit-log navigation and paging. Labels are copied from native tab
capture; native e7 establishes bottom-row swaps,dim-tab no-op and remembered
selection. Generation/epoch guards discard stale replies. The registered core
Godot navigation test passes with the extension prerequisite verified. This is
state-layer work only: no complete Reports screen or public launcher is accepted.

The Reports frame prototype loads `data/art/border.png` and `tabs.png` directly
from the supported installation. Native Reports does not use the similarly shaped
`HOVER_RECTANGLE`/`SHORT_TAB` vanilla atlas sprites. In the 1200x800 e7 All and
Combat reference captures, header rectangle (32,52)-(976,136), left border and
bottom border match exactly after selecting the standalone sheets and native
(70,44,0) label color. GPU capture also exercises actual viewport pointer dispatch
for disabled General and enabled Combat tabs. Evidence is under ignored
`build/qa/reports-frame-native-art-verified`; diagnostics are
passed_with_known_issues with no unclassified messages. The body, scrollbar,
unit-log rendering and owner/service integration remain unfinished; right-edge
pixel differences are still present. This is component evidence, not acceptance
of the complete Reports screen. Assets remain installation-owned and unshipped.

The Combat unit-list prototype additionally reproduces the first fifteen e7 r09
rows, including original `STOCKS_VIEW_ITEM` magnifiers, native orange (255,113,17),
36-pixel row pitch and sourced unit-row wording. The entire row rectangle
(48,142)-(944,688) has zero differing pixels using semantic names/professions from
`fixtures/reports/unit_rows.json`. `build/qa/reports-unit-render-verified` records
the comparison and GPU pointer test: the first magnifier requests its unit's log
with `from_end`. Diagnostics are passed_with_known_issues only. Native wheel steps are separately measured below; scrollbar dragging, pagination anchor,
resize behavior and service integration are not accepted. This component remains
hidden along with the unfinished complete Reports screen.

`native-return-grid-20260930` corrects a six-pixel single-destination placement
error by rounding the panel origin to native character rows. The earlier comparison
checked local component pixels; it now also requires the captured absolute origin.
Empty/single chooser, composed input and all previous Options fixtures pass with
only documented Godot diagnostics.
`native-return-multiple-20260930` additionally compares the captured visible strip
of the502-destination native chooser and checks each visible row's opaque identity.
It passes with known diagnostics; `native_save_return_multiple.json` retains the
glyph/tile oracle. Native itself clips this oversized menu to the viewport; this
case does not establish resize or new scrolling behavior.
Read-only `native-existing-chooser-20260930-115555` captures the two-destination
native layout and independently reads the same ordered semantic catalog
(region17, region18), leaving the owned save unchanged. Its retained oracle is
`native_save_return_two.json`. `native-return-two-fixed-20260930` passes the
complete panel/footer pixel and action-target comparisons for zero, one and two
destinations, plus the large-list case and earlier Options checks, with only
documented Godot diagnostics. The small-menu comparison includes absolute native
screen placement, not just local component pixels.

Save-effect acceptance uses `tools/smoke/SaveIsolation.psm1` to copy and hash all
save roots before invoking any native writer; disposable clones alone do not
isolate shared save slots. Its manifest accumulator now uses a growable list,
avoiding repeated full-array copying when many disposable saves exist. The
existing `save_isolation_test.ps1` regression passes, including detection of
unexpected non-test changes and additions. Preparing a backup is not evidence
that a save effect or its final preservation checks have passed.

Protected overwrite captures080758/080920 type each owned disposable clone's
existing name and press Enter. Native shows “There is a folder with this name
already.” / “Would you like to overwrite it?” with Save/Cancel. Physical Escape
and right-click do not dismiss it. Cancel returns to the naming prompt with text
preserved. No Save confirmation was clicked, no writer started and both save
manifests remained unchanged. `native_options_confirmation.gd` now includes this
fourth prompt; evidence is appended to `native_options_confirmations.json`.
GPU `build/qa/native-save-overwrite-20260930` passes its complete pixel region,
button signals and Back-input isolation alongside prior checks, with known Godot
diagnostics only; the render was visually inspected. Actual overwrite is still
disconnected. The existing backend's unconditional duplicate-name rejection is
a parity gap: implementing native confirmation requires explicit target ownership
and freshness checks, not removing that guard without a replacement workflow.

Native save-name capture075152 records eight physical text/key states: empty
initial field, append-only ASCII entry, ignored Left/Home, final-character
Backspace and a 40-character ASCII limit. No Enter/save submission was invoked;
native Cancel closed the prompt and both saves remained unchanged. The source
oracle is `fixtures/areas/native_save_name.json`. `native_save_name_view.gd` now
renders these eight states, verbatim prompt text, native Cancel and the installed
LCYAN field color. GPU `build/qa/native-save-name-color-20260930` passes all eight
504x144 comparisons plus Cancel and non-dismissing Back input, with known Godot
diagnostics only; the maximum-length render was visually inspected. This is an
unexposed rendering component: its editing model, non-ASCII/filename restrictions,
cursor timing, submit/overwrite and session ownership remain unfinished. The
existing prefilled 80-character checkpoint form differs from the native workflow
and must not stand in for this dialog.

The save-name component now handles append-only text, a 40-byte bound,
byte-wise Backspace and native filename-character exclusions. Protected075737
uses Unicode Windows text messages and records UTF-8 byte storage with CP437
display for accented, heart and Chinese characters; native Backspace can leave
partial UTF-8 sequences. The earlier075632 harness used ANSI PostMessage and is
not evidence for characters above255. Both captures preserve both saves. The
fixture now contains16states; GPU
`build/qa/native-save-name-editing-viewport-20260930` replays input through the
viewport and compares stored bytes and every rendered prompt pixel, passing with
known diagnostics only. Cursor phase is pinned to each capture, not acceptance of
blink timing. Submission/overwrite, clipboard/repeat and multibyte boundary
truncation remain unverified. Existing session checkpoint validation rejects
several native-accepted characters; native submission/path behavior must be
established before changing that contract.

Protected save-name capture080355 establishes multibyte truncation at40bytes:
with39ASCII bytes present, accented, heart and Chinese input each retain only
their first UTF-8 byte; Backspace returns to39. It also records150cursor samples
over1.485seconds, all matching `tick % 1000 < 500`. Both saves remain unchanged,
with no submission. The component now uses that cursor phase and an injected
clock for replay. GPU `build/qa/native-save-name-boundary-20260930` passes24native
byte/pixel states and all150clock samples, retaining prior Options/confirmation
checks, with only known Godot diagnostics. These supersede the earlier omissions
for blink timing and multibyte boundary truncation; submission and integration
remain unfinished.

`native_options_confirmation.gd` adds unexposed retire, abandon and quit prompts
with verbatim native text, captured line breaks and button widths. Protected
capture074236 preserves both saves and confirms the nine button texture cells
match installed `HORIZONTAL_OPTION_REMOVE` art byte for byte. The capture oracle
is `fixtures/areas/native_options_confirmations.json`; no captured art is shipped
or consumed at runtime. Expanded `native_options_view_capture` in
`build/qa/native-options-confirmations-20260930` passes all three 504x120 regions
plus local confirm/cancel routing, input blocking and unknown-prompt retirement,
with only known Godot thread/device/shutdown diagnostics. The retire render was
visually inspected. No destructive action is connected or live-confirmed. Protected
physical input captures074713/074822 establish that Escape and right-click leave
all three confirmations and the manual save-name prompt unchanged. Both runs
preserve both saves, pause and simulation frame0. The confirmation component
consumes these events without cancelling/confirming; expanded GPU run
`build/qa/native-options-physical-20260930` verifies they cannot reach an underlying
unhandled-input owner and that hidden prompts do not intercept them. It passes
with only the known Godot diagnostics. Evidence is appended to the confirmation
fixture; manual-name rendering is still absent. These remain
unfinished components until session ownership, native input and main-scene paths
are implemented and accepted.

Protected native save-effect capture `build/native-save-effects-20260930-081415`
passes with a verified 358,425-file backup, unchanged non-test saves and unchanged
source/clone manifests. Native SaveContinue plus Windows text/Enter creates the
new `df3d.manual-0930081415` destination and a 23,758,259-byte world file. World
identity and paused frame0 remain unchanged. Completion closes Options but retains
the entering/manual-save flags, with timer0 and stage/substage51. The hashed oracle
is `fixtures/areas/native_save_effect.json`. This establishes actual acceptance of
an internal period in this destination. Follow-up `reload-20260930-093223` passes
loadability, exact world/path identity, paused frame0 and a 192x192x193 map, with
unchanged destination and non-test save hashes; its proof is included in the same
fixture. Semantic CLI acceptance `semantic-20260930095617` also passes: a 40-byte
ASCII name with an internal period saves and reloads the same world at paused
frame0; a 41-byte name is rejected without a native save effect. Non-test and
prior test saves remain unchanged. Its hashed receipts and reloaded state are in
the same fixture. Godot `godot-20260930100731` also passes the standalone Options
scene's pointer/name/Enter save and exact destination reload with unchanged non-test
and prior test saves. Its receipt, native state, source hashes and preservation are
retained in the fixture; only the documented rendering-thread notice occurred.
Other filename/path cases, overwrite and save-return remain unverified.
The shared checkpoint validator now enforces the captured 40-byte bound and
accepts internal periods, retaining path/device-name guards including suffixes.
Seven focused C++ session cases (203 assertions) and `session_controls_test` in
`build/qa/session-native-name-20260930` pass. The legacy form also uses length40;
its prefilled workflow/copy is still unfinished. Remaining native character/path
parity is not established by these tests.

`native_options.gd` composes the menu, naming prompt and confirmations under one
local input owner. Native Cancel returns to the menu; overwrite Cancel returns to
the retained naming draft. A newly opened naming entry starts empty. Children deny
menu input, and a full-viewport mouse surface prevents clicks outside a child from
reaching the map. `build/qa/native-options-owner-20260930` passes the existing pixel
and byte fixtures plus composed pointer/Back, cancelled-action suppression, retained
draft and denied-owner checks, with only known Godot diagnostics. This owner remains
unexposed. Naming Enter now emits a copy of the native field bytes. The separate
`native_options_session.gd` owner sends them through `save_fortress_bytes`, retains
pending ownership across disconnects and matches sequence, action and request
fortress epoch before settling. A successful receipt closes only the originating
fortress's dialog; rejected/not-sent requests retain the draft. The byte binding
preserves incomplete UTF-8 through the existing validator; it does not relax the
validator's remaining restrictions. `build/qa/native-options-session-20260930`
passes its lifecycle tests cleanly and the expanded pixel/input check with only
known Godot diagnostics. Global composition, overwrite,
Settings, timeline selection and main-scene Escape integration remain unfinished.
Other route/confirmation signals do not execute actions or establish completion.
The current bridge SaveReturn path implicitly chooses the current folder or a new
folder on the same timeline. Native MAIN_DWARF_SAVE_AND_EXIT_CHOICES instead offers
explicit destination rows, as retained in `native_options_input.json`. Treat the
implicit selection as a parity defect: it does not establish native chooser
completion and must not be connected as the new Options Save-and-return action.
Protected read-only capture `native-return-catalog-20260930-101838` records the
complete option catalog for this cloned timeline:502 existing folders, new folder
with new timeline, new folder with same timeline, Return. It cancelled without a
save, preserved paused frame0 and verified the owned clone unchanged. Its fixture
is `fixtures/areas/native_save_return_catalog.json`; native option indices are
provenance only and must not become runtime command identities. Other timeline
configurations, new-timeline prompt and choice effects remain unverified.
`native-return-timeline-20260930-102244` varies only the loaded clone's in-memory
timeline name, then restores it without saving. Native then offers exactly Save
to new timeline, Save to new folder (same timeline), Return to game; the clone's
hashes and paused frame0 remain unchanged. `native_save_return_empty.json` records
this fixture and its tile/glyph oracle. Unexposed `native_save_return_view.gd`
matches the captured 1200x800 three-row state: GPU QA
`native-save-return-empty-20260930` passes its120,960-pixel comparison and
three pointer action mappings alongside the existing Options checks, with only
known diagnostics. Subsequent single-destination acceptance is described below;
the chooser does not yet submit save actions.
Protected timeline-name captures102803/102935 use the same reversible in-memory
fixture and retain original timeline name, paused frame0 and unchanged clone
hashes. The prompt starts empty; Cancel returns to the chooser, while physical
Escape/right-click leave it open. Unlike manual filenames, timeline names retain
punctuation including slashes, quotes and angle brackets. Recorded inputs show a
40-byte bound, CP437 display of UTF-8 bytes, byte Backspace and append-only Home.
`native_timeline_name.json` retains seven states and provenance. Unexposed
`native_timeline_name_view.gd` reuses the manual field rendering with separate native
copy and filtering; `build/qa/native-timeline-name-20260930` passes all recorded
pixels/inputs and previous Options checks with only known diagnostics. Full Unicode
boundary/cursor timing and main-scene integration remain unverified.
The Options owner now composes the destination chooser and timeline
prompt: timeline Cancel restores the chooser, inactive views cannot consume input,
and timeline bytes use a separate intent from manual filenames. The empty chooser
entry point requires a current catalog; an empty array means zero existing
destinations and must not represent an unavailable catalog. QA `native-timeline-owner-20260930` passes
session lifecycle tests cleanly and GPU/input checks with known diagnostics.
Explicit SaveReturn choice dispatch is implemented under session v9; acceptance
is ongoing. The owner does not call the legacy automatic SaveReturn operation.
Protected native timeline creation `timeline-20260930103712` creates a new ACTIVE
save in the previously absent owned `region16` destination, preserving world IDs
and returning to title. Its original reload failed because the loader selected a
title group using only world IDs, which multiple timelines share. The loader now
also matches exact timeline-name bytes; 109 bridge policy cases pass. Read-only
`native-timeline-reload-20260930-104747` passes with the corrected installed bridge:
exact path, world and timeline identity, paused frame0, 192x192x193 map and unchanged
destination manifest. The original effect's non-test and prior-test preservation
checks also passed. `native_save_effect.json` retains both the initial failure and
corrected reload evidence; this is native creation acceptance, not Godot submission.
That reload captures the single-destination chooser in
`native_save_return_single.json`. GPU `native-return-owner-20260930` passes empty
and single-destination pixels, pointer routing and composed ownership checks with
only known diagnostics. Selected destination IDs survive caller-array changes and
timeline Cancel; pending/inactive children cannot dispatch them. Malformed catalogs
cannot replace the menu, and later empty catalogs clear old choices. Multi-destination
rendering has native-copy evidence but lacks full GPU/interaction acceptance.
Session v9 adds explicit transport and destination revalidation; save-effect
acceptance and main-scene exposure remain unfinished.
Read-only `native-return-eligibility-20260930-110022` passes twelve native chooser
cases on that owned save, with paused frame0, restored header fields and unchanged
save manifest. Changing either loaded world ID or the case-sensitive timeline name
removes the destination; changing the manual name or loaded save type does not.
Restoring the empty timeline exposes the same502 existing destinations. The cases
and hashes are retained in `native_save_return_catalog.json`. This tests changes
to the loaded header only; candidate on-disk save-type eligibility and cross-root
filename collisions remain unverified. No destination was selected or saved.
An authoritative replacement fortress releases a pending old request as unknown,
retaining its sequence/epoch/outcome without replay. A late old receipt cannot
settle a new request with a reused sequence. The focused lifecycle regression in
`build/qa/native-options-session-epoch-20260930` passes cleanly. Disconnection alone
still retains ownership; absence of a receipt does not establish save completion.

`native_options_view.gd` now reproduces the captured initial MAIN_DWARF Options
menu as an unexposed rendering component. The seven labels/header are verbatim
native text; the two frames use installed `HOVER_RECTANGLE` art and buttons use
`BUTTON_CATEGORY_RECTANGLE`. `native_options_view_capture` reconstructs its
offline oracle from `fixtures/areas/native_options_frame.json` (recorded native
tile runs/glyphs) and installed assets, comparing all 193,536 component pixels.
`build/qa/native-options-frame-keyed-20260930` passed with only known Godot
thread/device/shutdown diagnostics. A separate direct comparison to native070526's
PNG found zero differing pixels in the entire 504x384 menu, and both images were
visually inspected. This establishes only initial rendering at 1200x800, not
hover, resize, session actions or Escape integration. The component emits local
option/dismissal signals and must not be exposed as a working menu until its
session effects and child workflows are ready.

Protected native Options input capture073531 passes eight cases with unchanged
source/clone manifests and simulation frame0. Return and right-click close the
top-level menu. Settings opens VIDEO over Options; injected Back returns to Options.
The save-name, retire, abandon and quit prompts ignore injected Back; native Cancel
returns to Options. The save-return chooser closes on injected Back. Opening these
prompts never started a save and no confirm action was invoked. Evidence and exact
prompt copy are in `fixtures/areas/native_options_input.json`; this does not prove
physical Escape/right-click cancellation inside child prompts. GPU
`build/qa/native-options-input-20260930` passes initial pixels plus all seven local
pointer signals, blank-area clicks, top-level dismissal, hidden-state and child-owner
input gates, with known Godot thread/device/shutdown diagnostics only. Main-scene
routing, child views and actual session effects remain unfinished.

Confirmed staff edits now refresh the parent zone through a semantic inspection,
including the owner's profession. Protected main-scene run
`build/areas-acceptance-20260930-071702` passed all ten ordinary staff lists through
chooser Details, checking assignment/removal against native data and comparing
the refreshed parent fields and caption. Both save manifests remained unchanged;
the only diagnostic was the known Godot separate-thread notice. This does not
establish staff mutation acceptance through the assigned-zone Details origin.
`areas_test` in `build/qa/staff-parent-epoch-20260930` passes ownership regressions:
queued cancellation, preserving the refresh when only Details closes, ignoring
late replies after selecting another zone, coalescing changes into one follow-up
read, and retiring outstanding/deferred reads on epoch replacement. These offline
checks do not substitute for live disconnect or epoch-transition acceptance.

Physical Escape is now isolated in protected native captures070133/070401/070526.
It closes the staff selector, Details, chooser and zone panel and opens Options;
the next Escape closes Options, and Escape from Default reopens it. This holds with
and without filter focus, at70ms and30ms key-down intervals. Both saves remain
unchanged in every run. The source fixture `fixtures/areas/native_escape_dispatch.json`
records transitions, exact Options labels, enum identities and captured layout.
The1200x800 native Options image was visually inspected. These are native reference
captures, not runtime acceptance. Injected LEAVESCREEN (even with OPTIONS) bypasses
outer dispatch and only closes one layer in the earlier captures. Do not describe
those injected-command checks as physical Escape acceptance.
Current `areas.gd`/`ui_host.gd` conflate Escape with Back, and the HUD's custom Game
menu does not reproduce native Options. These are recorded parity defects; routing
Escape to that custom menu would preserve a different product behavior. The native
Options menu and its actions remain an implementation dependency, including their
own save/retire/abandon/quit/Settings acceptance. No such actions were invoked here.

Details now blocks pointer actions on the visible parent zone panel and map,
matching native capture065309:16 clicks across both entry contexts leave observed
UI and zone fields unchanged. A transparent shield covers the zone panel; the
Areas map handler ignores pointer events while Details owns the view. Details
controls and right-click Back retain their own input paths. Protected main-scene
run065537 passes15 available parent/map controls across both routes with no queued
request, unchanged native guard facts and normal Back restoration. The difference
in count is the absent assigned-location Details icon on the unassigned chooser
parent. The existing full location scene also passes, both saves remain unchanged,
and only the known Godot thread notice appears. Offline `areas_test` passes.
Evidence and exclusions are in `fixtures/areas/native_location_details_parent_input.json`.
This does not establish global HUD, overlay, keyboard focus/shortcut, wheel/drag or
physical Escape runtime behavior; those interactions still need their own acceptance.

Both Details entry routes are connected inside the still-hidden Areas editor.
The chooser's Details icon opens the observed site/location without assigning the
zone; right-click returns to the retained chooser. The assigned-zone icon opens
its observed location and returns to the zone panel. Details state and any staff
selector retire when the parent closes or changes. The view initializes on first
entry; selector global input respects the Areas owner's overlay/input gate.
Native route capture063720 establishes these parent relationships. Protected main
fortress run064429 passes6 chooser and14 assigned-zone entries through viewport
clicks, plus the existing location creation/removal/reassignment, access and staff
candidate checks. Final cleanup and both unchanged save manifests are verified;
only the known Godot thread notice appears. Route screenshots and hashes are
recorded in `fixtures/areas/native_location_details_routes.json`; the hospital
composition was visually inspected. Offline Areas/menu tests and chooser/Details
GPU checks pass (the GPU checks retain documented engine diagnostics).
This establishes entry and right-click Back, not a completed screen. Physical
Escape/Options, parent keyboard focus/shortcuts, full-route staff editing and
lifecycle interruptions still need acceptance; supplies/copies, name,
religious/specialization and recognition controls remain unfinished. Native combined
LEAVESCREEN+OPTIONS simulation closes one Details layer; the isolated Windows
Escape reference above now establishes the distinct outer dispatch. Runtime
Options routing remains unfinished.

Ordinary staff pointer actions now run through `location_staff_workflow.gd` inside
the composed Details view. Empty slots open their semantic candidate list; only
complete observed rows can be chosen. Removal first obtains a current candidate
receipt. Both remain bound to the opening Details identity/revision; a change
cancels the local selection. Details owns submitted mutations, so late reads cannot
revive closed selectors and uncertain edits cannot replay. Confirmed assignment
and removal close/reset the selector and reset the staff list to its native top.
The workflow introduces no visible copy. Religious and specialization actions,
Escape/Options routing and the remaining Details controls remain unfinished.

The selector now follows native Enter and right-click behavior. Enter while editing
ends textbox focus without assignment; a subsequent unfocused Enter chooses the
selected observed worker. Key echoes cannot activate it. Right-click cancels even
with the filter focused and retires its rows/read ownership. Native capture063207
records the outer Windows input distinction: simulated SELECT bypasses textbox
handling. Escape closes additional native parent screens and also binds Options;
its full owner routing remains unfinished, rather than being treated as right-click.
The native keys fixture records observations and exclusions. GPU replay passes in
`build/qa/staff-keys-corrected-20260930` with known engine diagnostics. Protected
StaffScene run063323 verifies10 keyboard assignments,10 right-click cancellations,
5 focused Enter no-mutation controls and pointer removals with native readbacks.
Semantic/Unknown controls also pass; cleanup and both unchanged saves are verified.
Only the known thread notice appears. These remain production components mounted
in a test scaffold, not complete fortress-route acceptance.

`areas_acceptance.ps1 -StaffScene` adds real-renderer viewport clicks to the protected
staff lane. Run061722 passes all10 ordinary lists/20 pointer-driven edits through
production components in a test scaffold, with independent native holder/link,
refill and removal-labor readback. It also repeats the semantic and partial-effect
Unknown controls. Both saves are unchanged; only the known Godot thread notice
appears. This is not main fortress-route or full-screen pixel acceptance. Initial
staff scroll is fixture setup; physical scrollbar behavior has separate evidence.
The registered `location_staff_workflow_test` passes stale/cancel/late/repeated-choice
ownership cases. Existing composed Details and candidate row GPU checks pass with
known engine diagnostics in `build/qa/staff-workflow-20260930`.


The protected staff lane also covers a partial mutation. Run060333 exhausts the
occupation ID allocator after leaving one empty role: assignment publishes native
holder/unit effects, refill fails, and op25 returns Unknown without Details. The
service retains that outcome, the controller refuses further submission/refresh,
and a replayed old receipt is stale with unchanged native facts. Recovery explicitly
reobserves the holder before removal. Fixture-only allocator/vector changes are
restored both on recovery and teardown. The normal10-list matrix also passes; live
diagnostics are clean and both saves remain unchanged. This proves the explicit
partial-effect path, not disconnect/epoch/late-reply behavior in a real session.

`location_staff_view.gd` now draws the installed remove-worker artwork on occupied
rows. Native232551 places its four cells at x116..119 without a scrollbar and
x114..117 with one. The expanded GPU capture checks204 native tile cells across17
regions, including religious holders and scrolled hospitals;28 total staff cases
pass with only the documented Godot thread/device/shutdown diagnostics. Religious
holder identities in the former cropped-art fixture are sourced from the existing
native naming capture. Artwork alone does not establish editing support; the ordinary staff workflow
and viewport mutation evidence are described above. Religious edits remain unfinished.


Management protocol v30 uses `Local\df3d_management_v30`; rebuild/install the bridge
and viewer together. It adds `AreaOperation.LocationStaffEdit` (25, AreaUpdate)
with current site/location/occupation IDs, the Details `expected_revision` and the
candidate `expected_list_revision`. `unit_id >= 0` assigns; `-1` removes. The Godot
adapter requires an explicit `unit_id`. Session/map recording versions are unchanged;
v29 processes cannot share the v30 channel. No absent recording facts are synthesized.
The bridge reobserves both receipts at the mutation safe point and invalidates the
candidate receipt after applied or uncertain edits. Replies carry
`LocationEditOutcome` and refreshed Details only on confirmed completion. The
Details controller retains confirmed facts while pending and never retries a stale
or unknown edit; close cancels unsent work and detaches sent work.
Core, adapter and Details state checks pass in `build/qa/staff-edit-state-20260930`.
Protected `areas_acceptance.ps1 -StaffOnly` run055905 passes all10 ordinary
location-role lists through the state/service/bridge:20 edits,50 invalid-worker,
stale-receipt and consumed-receipt refusals, with independent native holder/link,
empty-role refill and removal-labor readback. Diagnostics are clean; final pause,
preferences and both unchanged save manifests are verified. Primitive native-button
comparisons remain separately recorded in the staff assignment fixture. This semantic-only run does
not establish GUI assignment/removal or live unknown/disconnect/late outcomes;
subsequent viewport and partial-effect evidence is described above. Remaining gaps include
occupied-target/multiple-link behavior or religious-position editing. Details routes
remain hidden and unfinished. No visible copy is introduced by this operation.


`df3d location-access-set <site id> <location id> <mode 0..3> <revision>` is a
protected acceptance diagnostic for native permission changes (Visitors,
Residents, Citizens, Members). Obtain the exact decimal-string `revision` from
`location-details-read`; do not round it through floating-point JSON numbers.
The helper rejects stale Details receipts and unavailable modes before writes;
Members is offered only for temples/guildhalls. It changes only the three access
flags, without refreshing caches or creating staff slots. The diagnostic requires
a loaded paused fortress with no save in progress; use the protected lane helpers.
Protected195808 matches all168 independently captured native160005 transitions
and verifies69 no-write refusals, restoration and unchanged source/clone saves.
The MSVC build and18 core CTests pass. Management op23 (`LocationAccess`,
`AreaUpdate`) now carries the current site/location, nonzero Details receipt and
`value`0..3. It returns a validated Details snapshot only on confirmed completion;
`location_edit_outcome` distinguishes Completed, Rejected, Stale and Unknown.
The appended outcome field and operation are additive to v26; rebuild bridge and
viewer together (older peers reject op23). Details state owns the pending action,
retains confirmed facts until the reply and never replays stale/unknown edits.
Protected201007 verifies21 available modes across6 locations through the actual
state/service/bridge,6 stale refusals, unchanged unrelated facts, restoration and
both unchanged saves. Existing location workflows also pass; the run has only the
known Godot thread notice. `location_access_view.gd` now implements the permission
bar with installed ON/OFF art and verbatim labels, including native precedence for
noncanonical flags, the absent Members button and guild qualifier. Native201709
captures48 distinct flag/kind cases and21 hover contexts. The registered
`location_access_view_test` and GPU `location_access_view_capture` check wording,
positions, colors, sprite pixels, input and pending-edit suppression; the GPU gate
has only the documented shutdown diagnostics. Protected202600 exercises21 viewport
clicks through the production bar to native state,6 stale refusals and settled icon
pixel checks, with unchanged saves and only the known thread notice. It mounts the
bar in a test scaffold, not a complete Details screen. Native hover captures203713,
204012 and204218 establish the four verbatim explanations, 500ms initial delay,
shared delay across neighboring controls, immediate warm changes/clicks, immediate
departure hiding and a roughly one-second warm return interval. The production
`native_hover_state.gd` and `native_hover_view.gd` now preserve these behaviors and
replace the minimap/elevation panel with the captured frame and text. Runtime uses
presentation-owned input and time, never native UI state. Registered state tests
replay575 native samples; GPU checks compare all four panels against captured cells
and installed artwork/font at1200x800. Protected205441 passes physical viewport
handoffs across all6 locations,21 access edits,6 stale invalidations and minimap
restoration. All21 captured help panels exactly match the native-cell verified GPU
renders; saves are unchanged and only the known thread notice remains. Godot's old
button exit is deferred within the input dispatch so entering a neighboring button
preserves the initial delay. Other viewport/scaling behavior and the complete Details
layout/actions remain unverified. Neither Details route is exposed by this component.

`df3d location-staff-read <site id> <location id>` observes ordered semantic
staffing identities and missing empty roles. `location-staff-prepare` creates those
missing empty occupation records for protected acceptance. It stages allocations
and registry changes before publication and reuses existing empty slots. These
helpers use world records, never native UI vectors. Reader182954 matches 203 native
cases, including religious positions, holder sentinels, duplicates and allocation
IDs; refusal183200 verifies 12 failures without registry changes. Both saves stay
unchanged and core checks pass. Ordered snapshots now travel through Details op21,
v26, the model and Godot, including all staff fields in the receipt. Absent legacy
staff data remains unknown; duplicate rows are preserved. Protected scene184852
verifies native staff data, holder/group changes and restoration through Godot,
with unchanged saves and only the known thread notice. Explicit `LocationOpen`
(op22, AreaUpdate) requires current site/location IDs and a Details receipt. It
refreshes native caches and prepares empty staffing slots once; op21 remains
observational. Entry outcomes distinguish Completed, Rejected, Stale and Unknown;
partial effects stay Unknown and the action service never replays them. Older
peers reject the appended operation. Protected scene190313 verifies stale refusal,
forced allocation refusal after cache refresh, entry/reentry, observational polling
and exact fixture restoration; saves unchanged, known thread notice only. Native
actor/title mapping, the complete view, assignment candidates and editing remain
unfinished; both Details routes remain disabled. Native capture190932 adds40 staff
label/holder cases, including scrolled hospital roles. The formatter maps all eight
occupation labels verbatim;72 recorded labels pass. A resolvable unit takes priority
over the historical figure, with a profession suffix; the historical-figure fallback
has name only. Tested religious titles use the neutral position name. Holder names/resolved identities now travel through Details snapshots and receipts.
Native191420/compiled192252 cover94 naming cases, including nicknames/custom
professions and religious HF-to-unit resolution;936 fully visible strings and604
clipped prefixes match. Full scene192406 verifies name transport and entry behavior,
with unchanged saves and only the known thread notice. Clipping geometry, colors,
portraits and the complete view remain unfinished; synthetic names are fixture-only.
Native staff capture221147 adds170 cases and2,946 visible rows, including controlled
name lengths and profession changes. All44,312 sampled nonblank role/holder glyphs
are white, irrespective of observed profession colors. The formatter now verifies
exact-fit and three-dot truncation against every recorded holder name. The fixture
records12-cell fields with a scrollbar and14 when the list fits. Controlled capture
221753 confirms this across50 row-count cases: visible capacity is10 for taverns,
9 for temples/libraries and5 for hospitals. `staff_layout` derives these facts from
semantic kind/count; the formatter gate checks every captured case. This does not
establish pointer scrolling or portrait parity. `location_staff_view.gd` now renders
role icons, native row backgrounds and text within the composed Details owner.
GPU checks20 native baseline/scrolled cases; protected full scene222419 verifies
17 staff-bearing images against the native-verified rendered bands. Both saves
remain unchanged; only the known thread notice occurs live. Portraits, assignment
controls remain unfinished; entry routes stay disabled. Staff scrollbar capture223022
adds1,903 input observations and375 artwork states. The staff view now reuses the
native scrollbar, retains local scroll across refresh and clears it on identity
change. Viewport/GPU checks cover the recorded inputs and pixels; protected scene
223440 clicks through hospital roles without mutation and retains scroll on refresh.
Both saves remain unchanged; only the known thread notice occurs live. Wheel over
rows and held-arrow repeat timing still need capture and acceptance.
Native holder-image capture224159 adds94 cases/1,540 visible slots and ten cached
32x32 images retained only in ignored capture output. These are full-body unit
sprites, not head portraits: do not reuse `creature_portrait()` for staff rows.
They sit at+2,+2 inside a40x36 picture frame. Historical-figure fallback without a
resolved unit renders no image/frame. `selection_icon(1, holder_id)` is a candidate
source. Sprite/frame rendering now uses it. Native comparison exposed and corrected
three shared appearance defects: unit random-part selection now uses the native
appearance seed and SplitMix64 calculation; inventory graphics matching scans in
reverse native order so shoes supply their own palette instead of a sock's; composite
textures preserve low-alpha shadow colors without Godot edge recoloring.
Protected full-scene231752 passes exact canonical native RGBA hashes for all ten
captured holders, plus existing Details/access/scroll scenarios, with only the known
thread notice and unchanged source/clone saves. The hash gate compares base pixels
without generated mip levels. This establishes those ten sprite cases, not complete
staff interaction or every creature appearance; corpse random-part selection remains
unverified. Earlier row/scroll-only tests do not establish sprite pixel correctness.
Native action capture232551 covers64 row observations and ten empty-slot selector
open/cancel cases. Empty ordinary slots now draw the original assignment icon,
verified against180 captured tile cells in eight additional GPU cases. Assignment
clicks, the selector, removal and specialization controls remain unfinished; this
artwork test does not establish their behavior. Native cancellation deactivates the
selector widget but retains its context field, so context alone is not open state.
The read-only diagnostic `df3d location-staff-candidates <site> <location> <occupation>`
now observes ordinary occupation candidates from semantic unit/occupation records.
Protected234933 compares ten native lists (1,152 identities/order/skill scores) and
47 controlled cases (5,426 identity/order entries) against the compiled reader.
`native_location_staff_selector.json` retains provenance and expected results.
Default order is stable descending weighted raw skill ratings; changing experience
alone does not change the tested ranking. Eligibility uses fortress membership,
active/adult state and native control flags, preserving tame exceptions and cached
creature-flag behavior. Existing assignments are checked through the unit's own
occupation links by site/location/role. Generic sane-citizen filtering is incorrect.
Core QA passes; protected saves remain unchanged. Selector UI,
alternate sorts/search, religious-position candidates and assign/remove mutations
remain unfinished; this diagnostic does not establish the complete staff workflow.
Optional `cursor revision` arguments use128-row pages with receipts bound to epoch,
site, location, occupation, role and complete candidate contents. Protected235658
verifies ten native first pages,60 invalid-target refusals, invalid cursor handling
and stale receipts after an unavailable observation. Core regressions cover260-row
traversal and identity/metadata changes; live multi-page populations remain untested.
Management v29 now carries these pages through read-only
`AreaOperation.LocationStaffCandidates` (24), using `location_site_id`,
`location_id` and a dedicated `occupation_id`. Following pages require the issued
`expected_list_revision`; cursors are multiples of128. Replies preserve native
names, unit/historical identities, raw skill ratings/experience/weights and scores.
Typed validators enforce field ownership, page accounting, unique units/skills,
descending scores, score consistency and a224-KiB aggregate payload budget.
The bridge refuses oversized facts rather than truncating names or inventing text.
Rebuild/install bridge and viewer together: v29 uses `Local\df3d_management_v29`,
isolating incompatible v28 peers. Session v8 and map recording formats are unchanged;
legacy absence of candidate data remains unknown, never an inferred empty list.

Version29 adds `source_index`, `profession_order`, `status_order` and two unsigned
CP437 byte vectors, `name_sort_key` and `profession_sort_key`. Native name sorting
includes the profession suffix; profession sorting excludes custom profession
text. Presentation owns the active header/direction and compares these semantic
facts locally. Equal keys use the original eligible-unit order, independent of
unit ID and current visual order. Source indexes must be unique and within the
full receipt total; key vectors are bounded at2,048 bytes and count toward the
same aggregate payload budget. All five fields participate in receipt revisions.
Bridge and viewer require a coordinated v29 rebuild; old management payloads
lack ordering evidence and must be rejected, not populated from display captions.
Map recordings and session protocol are unchanged.

Version28 adds separate `base_name`, `profession_name`, `profession_color` (0..15)
and an all-skills `legendary` fact, while preserving the full readable name.
These semantic fields participate in complete-list revision checks and payload
validation; each name field is limited to2,048 bytes. Old recordings cannot supply
these facts through invented defaults. Protected20260930-015420 verifies all1,152
rows across ten lists against retained native metadata, including controller
refresh/close. Core18CTest and both Godot contract/lifecycle checks pass. The live
scene passes with only the known thread notice, restored pause/preferences and
both save manifests unchanged. This establishes transport, not rendered-row parity.

Protected20260930-001612 passes all ten candidate lists through the actual Godot
scene (1,152 native identities/order/scores), repeated stable reads,20 invalid
targets and10 stale receipts after invalidation. Both saves are unchanged, final
pause/preferences restored; only the known separate-render-thread notice remains.
Offline core18CTest and the Godot management contract pass, including128-offset
page decoding and64-bit receipt precision. Live multi-page populations, selector
interaction, alternate sorting/search and assignment/removal remain unfinished.

`location_staff_candidates_state.gd` now owns read-only selector lifecycle through
the semantic action service. It assembles complete revision-bound lists before
publishing selectable rows, rejects cross-page identity/role/revision/total/order
changes, and retires queued or late replies on close, reopen and session changes.
Refresh keeps confirmed data while waiting; a failed read clears it without replay.
Offline lifecycle tests cover260-row assembly, cancellation races and timeouts.
Protected20260930-003400 verifies all ten actual lists, stable refresh and closure
through this controller; the full location scene passes with unchanged saves and
only the known separate-render-thread notice. The rendered selector is unfinished.

`native_location_staff_selector_ui.json` retains native metadata from protected
20260930-002742: ten default lists, eight header toggles and five controlled skill
ratings. Native viewport capacity is16 rows. Skills are displayed only for positive
ratings, sorted by descending **rating times role weight**, then ascending skill ID.
Text uses the raw rank capped at15: ratings15,20,21 and25 all show `Legendary`, with
no `+N` suffix. `location_staff_candidates_format.gd` maps the pinned enum captions
and31 skill nouns verbatim; its fixture test matches2,275 captions across1,157 rows.
Unknown mappings return unknown instead of authored replacement text. Do not reuse
the labor formatter's different rank cap. Header widget names are not automatically
visible labels: the native `Skills` widget has no rendered text in this capture.
Filter probes did not enter text even after native textbox focus was observed;
those empty results are not search acceptance. Scroll timing/boundaries, original
row rendering, alternate sorting behavior and filtering still need work.

`location_staff_candidates_frame.gd` provides the selector frame, header artwork
and native labels, empty filter artwork and shared scrollbar. Protected capture
20260930-005254 verifies the rendered frame spans cells46..119,4..62, extending
beyond the widget's reported right edge117. The list scrollbar spans cells117..118,
7..56 and has16 visible rows. Each header retains its own direction when another
header is selected; active text is black and inactive text uses native dark gray.
The skill column has an arrow and no authored label. The registered GPU check
`location_staff_candidates_frame_capture` compares18 native states and1,593,426
opaque pixels using installed artwork and glyphs. It passes with only deferred
Godot diagnostics. Fixture `native_location_staff_selector_frame.json` retains
metadata, provenance hashes and explicit omissions, without game pixels. This
component is not mounted yet: initial row text/background acceptance is described
below; portrait rendering, text input, sorting effects, scroll interactions and
assignment actions remain unaccepted; routes stay
hidden. The native UI is capture evidence only, never a runtime input.

Candidate-name evidence in `native_location_staff_candidate_names.json` records
195 rendered row states from protected20260930-010516: ten default lists and35
controlled name/profession cases. The selector fits name and profession together
in30 cells; otherwise it drops the comma and puts the profession on the next line.
Long fields remove ASCII vowels from right to left, preserving the first character
after each space, then clip if still too long; they do not add ellipses. This also
applies to a single long word. Y and accented vowels remain. Protected013629 and
013931 add107 abbreviation/capitalization controls, retained in
`native_location_staff_name_abbreviation.json`. The formatter matches these plus
the earlier195 rows:302 native name/profession pairs. It applies native CP437
word capitalization outside brackets, with native single/double-quote behavior,
while preserving profession casing. Unicode uppercasing is not equivalent.
Empty profession remains unknown until supported by evidence. Synthetic controlled
names are fixture data only; runtime text comes from semantic name/profession facts.

DFHack `getReadableName`/`getProfessionName` enum captions are not exact native
selector copy. The staff reader corrects two fallback captions: profession70 is
`Diagnostician` rather than the helper's `Diagnoser`, and profession86 is
`Swordmaster` rather than `Swordsmaster`. Custom professions, noble titles,
creature/caste raw overrides and undead names are preserved. Protected011033
surveyed all135 profession values on an adult dwarf:122 appeared in the native
selector; only those two fallback captions differed. Final protected011906 verifies
the rebuilt semantic reader against all122 visible names plus six controls that
preserve custom, creature and caste overrides, with unchanged saves. Metadata and
hashes are in `native_location_staff_professions.json`.

That survey also exposed eleven extra professions in the semantic candidate list.
The reader now excludes professions that cannot receive labors, plus merchants,
trained hunters/war animals and thieves/master thieves. Final011906 matches native
presence for all135 profession states (122 included,13 excluded), along with all
ten baseline lists. Both builds and18 core CTests pass. These checks do not prove
complete rendered rows or all other race/title variants. Do not promote rows or
preserve conflicting helper/spec behavior as an authorized departure.

The color differences are accounted for by legendary-name animation, rather than
a replacement profession-color table. Protected012915 captures1,024 observations
over3.2 seconds with16 base colors and skill ratings14/15; the name-color formatter
keeps ordinary colors stable, maps black to dark gray, and alternates legendary
brightness. Dark gray alternates with light gray. A333ms alternate phase per1,000ms
matches every captured interval within one16ms Windows timer quantum; exact
sub-frame boundaries are not established. Both phases were observed for every
base color. The same mapping accounts for every color in the earlier195-row name
capture, including unselected rows and real profession/noble colors. Retained
`native_location_staff_name_colors.json` supplies provenance and timing bounds;
the registered candidate formatter check passes both color fixtures and the
existing skill-caption cases. All controlled raw colors and skills were restored,
final pause verified, and both saves remained unchanged. The v28 candidate response
now provides profession color and an **all-skills** legendary fact: occupation-only
skills cannot determine this effect. Runtime animation-clock synchronization and
full rendered-row acceptance remain open.

`location_staff_candidates_view.gd` composes the verified frame with candidate
backgrounds, name/profession lines, palette colors and role skills. Protected
005254 cell evidence establishes three-cell row height and sequential character
overwrite: later rows erase earlier overflow inside their backgrounds; shorter
skill captions replace characters but leave trailing characters beyond their ends.
The last visible row can overflow onto the filter and bottom border. The empty
filter clears its text cells independently of its icon. Do not silently replace
these observed behaviors with a cleaner layout under a spec's authority.
`native_location_staff_candidate_rows.json` retains ten initial lists and35,840
native cells, provenance and omissions, without pixels. The registered GPU check
`location_staff_candidates_rows_capture` verifies backgrounds and opaque glyph
pixels against installed art/font/palette; its final run passes with only deferred
Godot diagnostics. Capture-phase ticks are supplied explicitly for this comparison.
Scrolled rows, input and runtime animation-clock synchronization remain unverified;
the component is not mounted into the hidden selector workflow.

Protected020926 records160 candidate portrait placements covering62 unique units:
32x32 native images at offset2,2 inside40x36 frames. Hashes and provenance, without
pixels, are retained in `native_location_staff_candidate_portraits.json`.
`native_unit_picture_frame.gd` corrects a native asset mismatch shared by candidate
and existing staff rows: unselected frames use the original nine `BUTTON_PICTURE_BOX`
variants, not the later `BUTTON_PICTURE_BOX_DARK` replacement. All18 selected/normal
frame cells match native pixel hashes; candidate/staff GPU regression checks pass
with the documented diagnostics. Candidate rows now request resident unit icons
and retire unavailable/closed-row images, but portrait acceptance is **failing**.
The age-color defect found in human4338 is corrected: `tissueColors` now considers
later effective modifiers. Native controls022107/022304/022657 establish a truncated
integer replacement percentage greater than50 for the observed ranges, rather than
a midpoint switch. `appearance_color.h` retains that arithmetic; core regressions
use captured birth dates at the boundaries. Fingerprints include selected colors
and modifier applicability, so age transitions invalidate cached appearance without
rebuilding on every tick. `native_location_staff_candidate_aging.json` retains74
controls and three restorations with hashes/provenance, without pixels. Arbitrary
overlapping/malformed schedules and corpse aging remain unverified.

The remaining six pixels in human4338 were a steel earring: ordinary item conditions
store procedural-kind-1 even though the named enum `NONE` is1. The reader now treats
the negative field sentinel as unset. Protected023329 retains the actual condition
and inventory evidence. Rebuilt live024005 verifies this unit exactly, plus32 others,
including all ten previously verified staff portraits. Its complete62-unit audit
reported28 differing images and one unavailable icon (unit7344). Differences
include equipment colors and smaller details; do not claim full portrait parity.
`areas_location_scene_live.gd` now records all mismatches and unavailable identities
in `candidate-portrait-audit.json` before failing. Core18CTest passes; the full live
lane remains failed on these explicit assertions. All capture and failed live runs
verified final pause/preferences and both unchanged save manifests. Resolve the
remaining appearance and availability defects, then rerun full live acceptance.
Protected025247 improves that audit to43 exact,18 differing and one unavailable.
Native list icons exclude wieldable overflow: ten previously oversized composites
match exactly when using their logical body cell. `selection_icon(kind,id,body_cell)`
now accepts an optional body-cell request, derived from the compositor's recorded
origin and body dimensions; the default retains the full sprite. Staff and candidate
views request this region. The extension build and both staff GPU checks pass with
known diagnostics only. Full live acceptance still fails the remaining portrait
assertion; final pause/preferences and both unchanged saves are verified. Unit2346
still produces an8x12 fallback glyph;7344 remains unavailable. Neither is accepted
as native parity. The earlier differing-pixel counts for unequal image dimensions
were invalid comparisons; compare equal body-cell images when investigating colors.
Protected dye control025925 records16 native units with fortress clothing dyes
on/off/restored (48 observations in native_location_staff_candidate_dyes.json).
The installed setting is enabled. Profession-conditional clothing layers must
be skipped in dye mode so the ordinary item-palette alternative wins. The bridge
now respects this fortress setting and includes it in the unit appearance
fingerprint. Native off-mode exactly reproduced the earlier wrong colors for
units6969 and7268; restoring on-mode restored all16 original native icons.
Protected030132 verifies49 exact icons after this change. Runtime preference
transition, adventure mode and corpse dye behavior remain unverified.
`unit_tile()` now evaluates the actor's current model position independently of
the rendered depth window, retaining the known/non-hidden terrain requirement.
This resolves unit7344 above the current slice: protected030442 has50 exact icons,
12 differing and none unavailable. Unit2346 still has no model layer stack and
renders an8x12 glyph; eleven other cases differ by2..36 pixels. The failure audit
now retains semantic position/species and model composite diagnostics. Core18CTest,
extension build and both staff GPU checks pass (GPU known diagnostics only).
Full live acceptance remains failed on the portrait assertion, with verified
cleanup/pause/preferences and unchanged source/clone saves. Routes stay hidden.
Native hair controls031006 establish that `SHUT_OFF_IF_ITEM_PRESENT` clauses are
alternatives: a cloak alone suppresses long ponytail hair, without headgear.
The prior conjunction was incorrect. Five native controlled/restored hashes are
retained in native_location_staff_candidate_hair.json; the reader now rejects a
layer on any matching forbidden-item clause. Rebuilt protected031149 verifies60
of62 icons exactly, with no unavailable icons or regressions. Only2346 (fallback)
and5575 (three pixels) remain different. Core18CTest passes; live fails only the
remaining portrait assertion plus the known thread notice. Saves/pause/preferences
are verified unchanged/restored.
Startup capture030702 explains2346: its ANIMAL_PEOPLE template set initially has
zero parsed layers, then237 after native selector use; the resolver yields0 then10
layers while its unit fingerprint stays1773184274. Evidence is retained in
native_location_staff_candidate_template.json. Runtime must initialize/resolve
this template independently of native viewscreens; opening a native screen or
accepting the fallback is not a fix. Template initialization and cache invalidation
were unfinished at that point. The following changes complete the captured portrait
cases; complete selector interaction acceptance still remains.
`appearance_template_native.h` now guards the supported native raw-template
expander723720 and raw parser1146550 with PE identity and full-routine hashes.
It takes the layer set/template/creature/caste, expands raw definitions and consumes
the template token as native callers do. Runtime reads no native widgets or cached
unit textures. Unit fingerprints include raw layer counts/template state to detect
materialization while paused. Protected031824 verifies2346 exactly, reaching61/62.
Controls031957 establish that5575's final three pixels depend on its axe's artifact
flag; turning it off reproduces the model, while refresh/restoration preserves
native. Quality-ceiling controls032158 rule out the quality-range hypothesis.
The reader now applies a layer's material restriction to forbidden items, as native
71f8ef..71f90e does: an artifact axe does not suppress the NOT_ARTIFACT gauntlet layer.
Hash-only controls are in native_location_staff_candidate_artifact.json.
Protected032458 passes the full location scene with only the known Godot thread
notice: all62 native sprite hashes, ten composed selector lists/160 visible rows,
close cleanup and existing location/Details/access scenarios. Core18CTest passes.
Final pause/preferences and both unchanged save manifests are verified. This is
initial-list portrait acceptance; filtering, sorting, scroll/held-input behavior,
assignment/removal and production selector integration remain unfinished. No route
is newly exposed. Arbitrary templates/corpses and unsupported builds are not covered
by these captured cases; the native call refuses mismatched executable/routine bytes.

Protected033735 adds discrete candidate input acceptance through viewport events
in the full live scene: selection arrows/page keys, row wheel/Shift-wheel and
scrollbar updates match native033235. The shared replay lives in
`tests/location_staff_candidates_input_helpers.gd`; offline GPU rows also passed
before its extraction. Final pause/preferences, cleanup and both save manifests
are verified; only the known separate-thread notice remains. This does not accept
held-repeat timing, dragging, scrollbar wheel behavior, sorting/filtering,
assignment or production integration. Numeric key aliases follow the supported
default native bindings; remapped bindings are not yet verified.

All four candidate headers now follow native ordering and input behavior. Selecting
another header retains its direction, clicking the active header reverses it, and
both reset selection and scrolling. Equal keys preserve eligible-unit source order.
The bridge obtains normalized name/profession byte keys and category/status ranks
from guarded stateless native semantic readers; no native widget state is a runtime
input. Name keys include profession suffixes; profession keys exclude custom titles.
`native_location_staff_candidate_order.json` records ten lists and120 header
transitions, checking13,824 ordered rows against protected040940. Displayed widget
traversal is the capture oracle; native `entry_list` preserves backing order.
Offline staff-order-v29-20260930 passes core18CTest, the management contract and
controller checks; GPU rows pass with known engine diagnostics. Protected042055
passes all ten header replays against actual v29 payloads, all62 portrait hashes
and ten initial composed lists. Only the known Godot thread notice remains. Final
pause, cleanup, preferences and both unchanged save manifests were verified.
The focused staff-order-boundary-20260930 controller check also cleanly passes,
including rejection of reversed equal-score source indexes across page boundaries.
Sorted-list pixel comparison, filtering, assignment/removal, held/drag input and
production mounting remain unfinished; this does not expose a completed route.
Protected043340 resolves the earlier failed filter-input probes: DFHack simulated
viewscreen input bypasses the native outer loop's textbox editing and callback.
After graphics-frame progression, actual character events sent to the owned game
window entered `miner`, selecting four of116 candidates. The hash-provenance
fixture `native_location_staff_candidate_filter.json` now includes fourteen controls
from protected043601. Uppercase display is preserved while matching is normalized;
queries match contiguous substrings of existing native name-sort keys, including
ASCII queries matching accented names. Punctuation is preserved, input stops at33
characters, and backspacing to empty restores the original116-row order. Final
pause/preferences and both unchanged save manifests were verified. Non-ASCII
query entry, intermediate editing, clear/escape/focus behavior, cross-header/role
controls and filtered pixels remain unaccepted.
The matching component now accepts normalized native byte keys, filters the full
retained candidate population by contiguous name-key substring and applies the
current header order. Closing clears both population and query. Shared replay
checks all fourteen native queries offline and against actual bridge payloads.
Offline staff-filter-keys-20260930 passes with deferred Godot diagnostics;
protected044046 passes the complete location scene with only the known thread
notice. Cleanup, final pause/preferences and both save manifests were verified.
The component now handles textbox click focus, append/backspace, the33-byte limit,
native byte normalization, case-preserving CP437 text and the native underscore
cursor (visible for the first500ms of each second while focused). Header changes
retain focus. Fourteen captured ASCII queries are replayed through actual viewport
input with full ordered results and opaque filter-glyph pixel checks. Offline
staff-filter-cursor-20260930 and protected045512 pass with only known diagnostics;
the live run also verifies cleanup, final pause/preferences and unchanged saves.
This does not establish complete focus/escape behavior or non-ASCII input parity. Protected044739 separately verifies
filtering from cursor32/scroll17 resets both to zero; discrete Backspace removes
the final character, and Left/Home followed by typing append at the end. Clicking
the right-hand filter icon leaves the query unchanged. These controls are retained
in the filter fixture. The strengthened offline staff-filter-reset-20260930 check
passes with known engine diagnostics. Non-ASCII event representation and Escape
transitions remain unresolved; an exploratory run failed its transition assumption
and is not acceptance evidence for those behaviors.
Protected050023 adds focused navigation and blank-panel click evidence: Down and
PageDown do not move selection while typing, numeric keys append text, and clicking
blank panel space removes focus so further text is ignored until refocus. The
component now follows that dispatch. Shared viewport replay checks seven states
offline and against actual live payloads. Offline staff-filter-navigation-spaced-
20260930 and protected050311 pass with only documented engine diagnostics; final
cleanup/pause/preferences and both unchanged saves were verified. Other control
clicks, outside-panel focus, Escape and Enter/assignment are not accepted by this
coverage. Screenshot tests leave a render frame between query readbacks to avoid
synchronizing the renderer every frame; diagnostics remain strictly classified.

Native staff assignment/removal effects are recorded in
`native_location_staff_assignment.json` from protected051233. Selecting an empty
tavern-keeper slot updates holder IDs and unit occupation links, changes the unit
profession and adds a CHANGE_HF_JOB history event. Native removal clears the link,
restores profession and adds another event; refresh flags and history remain, so
removal is not an in-memory rollback. Base historical-figure profession stays
unchanged in this case, while the first event's old job differs from it and the
unit profession. Protected051647 extends the fixture to ten ordinary candidate
lists and confirms the event source is `hf.info.skills.profession`, which changes
with the native profession update. Hospital assignments also change medical labors;
native removal retains those labor changes. Some tested workers keep their unit
profession and produce no event. Assignment returns reset Details staff scrolling
to zero. Captures are sequential and retain native side effects between cases.
They do not implement or accept a semantic mutation, occupied-worker reassignment,
religious positions, exhaustive profession precedence or empty-slot allocation
policy beyond the captured controls. Protected052158 adds before/after-render
snapshots: assignment creates an empty role slot before rendering if none remains,
reuses any existing empty slot, and removal preserves the extra empty records.
This agrees with the existing staff preparation helper. Protected052343 transfers
a scholar from a library to tavern keeper: native clears the prior slot, replaces
the unit link and updates profession/history. Removing the new assignment leaves
the prior slot empty and derives a new profession; it does not restore the old job.
Both captures verified final pause/preferences and unchanged saves. Multiple prior
links and occupied-target replacement remain unaccepted. Native widget callbacks
remain capture evidence only, never runtime inputs.
Candidate receipts now additionally bind private semantic occupation dependencies:
target holder and eligible workers' existing links, including other locations.
Those facts are not added to the wire payload. Changing a binding invalidates the
receipt even when visible names, ranks and skills are identical; restoring it does
not revive the earlier receipt. Core regressions pass, and protected052845 verifies
a binding change/restoration with identical visible payload and stale replies,
restored preferences/final pause and unchanged saves. This closes a freshness gap;
it does not alone complete mutation validation.
`df3d location-staff-set <site> <location> <occupation> <unit|-1> <revision>` now
provides protected semantic assignment/removal. Obtain a current paged candidate
receipt from the diagnostic; the command requires a paused loaded fortress and no
save in progress. Outcomes are0 unavailable,1 rejected,2 applied,3 unknown. Applied
and unknown outcomes retire the receipt; never replay an unknown result. Guarded
native unit routines update profession/history and, for assignment, labors; removal
preserves native labor side effects. Existing occupation links and empty-slot refill
are handled without runtime widget input. Core tests and protected053520/053744
pass for ten lists plus one transfer, invalid-worker refusal and replay refusal.
All33 immediate semantic snapshots match native captures; native UI caches/scroll
remain presentation-owned. One post-render texture-refresh flag differs despite
matching immediate flags and remains tracked. Final pause/preferences and saves
were verified. Management transport, controller and complete GUI integration remain
unfinished, as do occupied-target, multiple-link and broader lifecycle controls.

`location_details_state.gd` owns the Areas Details lifecycle through the semantic
action service: one observational receipt followed by explicit entry, read-only
refreshes, generation-bound replies and cancellation on close/session replacement.
Stale and unknown entry outcomes never auto-replay. Its deterministic lifecycle
check and protected scene193352 verify the real service path and Areas close,
with unchanged saves and only the known thread notice. This does not enable either
unfinished Details route or establish visual/action parity for the complete screen.
The shared `location_details_body.gd` component maps29 captured body rows to native
cell positions with verified quantity formatting. Its layout now includes the native
4px vertical letterbox at1200x800. GPU checks compare opaque glyph pixels against
29 recorded native rows at their physical coordinates and native colors, replacing
the earlier presence-of-ink check. Protected210250 records363 controlled native
dance-floor presentation cases: absent floor uses light red, either positive
dimension below5 uses yellow, and dimensions at least5x5 use white. The body now
uses those rules;303 valid semantic pairs pass and60 mixed-zero pairs remain
omitted by semantic validation. The native capture restores its presentation fields,
ends paused and leaves both save manifests unchanged. Offline logic and GPU checks
pass with only documented thread/device/shutdown notices. Background/button art,
heading, staff controls, editors and complete-screen/action parity remain unfinished
and unexposed; these text-component checks do not establish them.

The shared `location_details_heading.gd` renders the native name/type rows from
existing semantic name, kind, tier and profession fields. Protected210852 records48
native heading/tier/recognition/dedication cases with all six baseline/restored
cell grids identical, final pause and unchanged saves. Registered heading logic
and GPU checks pass for those48 cases; GPU checks compare installed glyph pixels
at native coordinates/colors at1200x800, with documented engine diagnostics only.
Protected214045 adds108 cases including zero/single members and controlled long
names. Combined with69 guild profession cases from212149, the heading component
now renders dedication, guild members/workers and worshippers with native copy,
colors and positions. Location names use the captured60-cell ellipsis; affiliation
names continue to the screen edge. No dedication and zero worshippers use gray,
deity dedication cyan, established religion/guild yellow and absent-guild worker
text magenta. The177 added cases and original48 pass logic/GPU glyph checks.
Protected214728 mounts the heading and body beside the permission bar in the full
scene scaffold: all21 access-mode images pass native heading/affiliation glyph
checks, prior workflows pass, saves are unchanged, and only the known thread
notice remains. This is not the complete Details view: rename/editors, staff and other actions
remain unfinished; the frame/value integration is described below. Other viewport/scaling
behavior also remains unverified. Do not derive recognition prompt/action
availability from `recognized` alone: toggling it in native leaves the religion's
current priest/high-priest prompt unchanged. Religious-position state and native
action eligibility require further evidence.

The read-only protected diagnostic `df3d location-affiliation-read <site id>
<location id>` now observes Details affiliation independently of the creation
catalog. Semantic `kind`1 is no dedication,2 deity,3 religion,4 guild; `id`,
translated `name` and eligible `count` describe the affiliation. A missing guild
has id-1, empty name and zero members; guild `workers` separately supplies the
native fallback worker count. Workers is-1 for non-guild affiliations. Units must
be active and FortControlled, with the appropriate deity/member link for counts;
guild workers use the native profession-family ranges. Protected212149 compares129
native Details cases including69 professions and controlled eligibility changes,
with13 invalid identity/lifecycle refusals, exact baseline restoration, final pause
and unchanged saves. The MSVC build/install passes. Native text distinguishes
`no members`, numeric plural members, and `No established guild` followed by
zero/singular/plural workers; do not replace those facts with an invented fallback.
Native214045 verifies the single-member wording. Optional
`LocationAffiliation` now travels through Details, the neutral model and Godot as
`affiliation` with kind/id/name/count/workers. Absence in older records remains
unknown. Validators enforce the owning location kind, identity, count and worker
sentinels; the Details receipt includes presence and every affiliation field.
This is an additive management-v26 field; older consumers can ignore it. The core
and inspector build, all18 CTests, management contract and Details lifecycle checks
pass. Protected213358 compares decoded facts before/during/after controlled unit
inactivation and verifies complete snapshot restoration, repeated read stability,
entry/access outcomes and the existing location workflows. Final pause, cleanup
and unchanged save manifests pass; only the known Godot thread notice remains.
Affiliation view rows are covered above; complete Details UI/action parity remains unfinished.

`location_value_view.gd` now renders native tier/value/threshold lines using the
verified Appraisal formatter and installed CP437 currency glyph15. Protected215411
records294 tier/appraisal/raw-value cases, including signed extremes and capped
estimates with the question mark after currency. The registered value logic/GPU
checks match all294 lines and glyph cells. `location_details_view.gd` composes the
heading, affiliation, value, body and access bar in the native608x660 frame at
368,52 for1200x800. Its GPU check verifies six native frame borders and text layouts,
pending-state retention and close-state clearing. Protected220112 binds that owner
to the live Details state in the test scaffold:21 viewport access edits, hover and
stale checks, plus previous location workflows pass. All21 frame/value image crops
match the native-verified composed renders exactly; cleanup, final pause and both
save manifests pass. GPU gates have documented shutdown diagnostics; live has only
the known thread notice. This remains a partial view: staff, numeric editors, rename,
recognition/assignment actions and Back/entry routes are unfinished. Other viewport
sizes/scales and overall HUD composition remain separate acceptance gaps.

The protected diagnostic `df3d location-details-refresh <site id> <location id>`
refreshes native location caches at a safe point through the existing guarded
semantic refresh function, then resets update_timer/update_count to100/0. It has
no native UI input and does not open a screen or populate staffing slots. Ordinary
`location-details-read` remains observational. Native181042 and paired reader181414
verify 60 cases: opening/reopening recomputes value, ten stored supply counts and
need flags, while rendering an already-open panel does not. Requested quantities
and recognition are preserved. Invalid identities refuse without cache writes.
Core checks pass and both saves are unchanged. This helper still needs integration
into the complete Details entry workflow; transport reads alone are not native opening.

Details now carries native dance-floor dimensions, with both fields -1 for legacy
unknowns and both zero for no eligible rectangle (native copy: `None`). The bridge
calls the supported game's semantic extent/terrain routine behind a complete-routine
fingerprint and PE compatibility guard; it takes no native UI inputs. Native ranking
prefers the 5/6/7/8-square thresholds before area, retaining the first exact tie.
Protected175724 compares 81 native cases, including 48 rendered dimensions/None values;
scene180450 verifies 7x8->0x0->7x8 and restored receipts through Godot. Guard probe
`tools/qa/location_dance_guard_probe.cpp` passes 2,961 code/metadata/length checks.
Extracted routine bytes remain ignored. Both saves are unchanged; live diagnostics
contain only the known thread notice. Written-object membership now requires room
extents and uses their bounds directly, correcting the earlier building-bounds fallback.
Native Details opening also populates empty occupation slots. Capture181700 verifies
role grouping, empty-slot creation/reuse and assignment order within each role.
Staffing-row eligibility and slot preparation are now verified as described above;
assignment-candidate eligibility and editing, the Details view and its entry lifecycle
still require completion.

Details also carries `written_objects`, with -1 for unobserved legacy data.
Native books count even without writing; tools require writing. Counting uses
resolved item positions and non-Bedroom painted zone footprints, once per item
vector entry across overlapping zones; stack size does not contribute. Protected
reader174422/174509 matches268 native observations, including248 rendered Library
counts. Scene174613 verifies6->5->6 and restored receipts through Godot, with
unchanged saves and only the known thread notice. This supplies data for Details;
the complete Details view, actions and staffing remain unfinished.

Details carries optional `facilities` counts for chests, beds, tables, traction
benches, bookcases, chairs, bedrooms and rented rooms. Absent legacy data stays
unknown. Native counting excludes Bedroom zones from common furniture, preserves
membership multiplicity, and does not filter stage or activity flags. Rented rooms
use the native assignment sentinel, not unit eligibility. Protected172002 checks
1,778 displayed counters; protected172132 verifies changed/restored counts and receipts
through Godot, with unchanged saves. Staffing and the complete Details UI/actions
remain unfinished.

`location_details_format_test` verifies appraisal text and supply conversion against
protected native captures: 1,371 value lines (including broker selection, rating,
rust and signed boundaries) and 152 supply cases. Native location value visibility
uses an assigned broker's effective Appraisal, independently of the HUD bookkeeping
precision. The formatter separates currency artwork from text and preserves absent
observations. The bridge now observes effective Appraisal through reverse TRADE assignment
resolution and carries it through management v26 to Godot, with receipt invalidation.
`appraisal=-2` means unobserved in legacy data, -1 means no resolvable broker, and
0+ is the observed effective skill. Protected170001/170054 compare all1,371 compiled
reads to native cases; protected170155 checks paused broker changes/restoration
through the full transport with unchanged saves. The full Details UI remains
unfinished; raw values alone still do not authorize an exact numeric display.

Location chooser rows expose the owning `site_id`; assigned-zone records expose
`location_site_id` from the zone's stored assignment. Both default to -1 when
unknown (or unassigned), preserving compatibility with older v26 records. Details
requests use these observed identities; never substitute the current site for a
foreign or missing assignment. Protected163529 verifies chooser and assigned-zone
Details reads, creation/reassignment membership, fixture restoration and unchanged
saves. The Details UI and remaining native actions are still unfinished.

Existing-location chooser rows carry additive `guild_profession` and
`location_tier` metadata (unknown defaults -1; management v25 remains compatible).
The presentation maps native profession/rank wording from protected150935's276
rendered controls, rather than displaying a generic Guildhall subtitle. New
first-page requests rebuild an already delivered location snapshot even while
paused; continuations retain that snapshot. Metadata and names participate in
the receipt hash. `area_links_test` checks the complete recorded caption matrix;
`area_menus_capture` exercises installed art. Protected `-LocationScene` also
compares the existing six native rows through bridge/controller before creation
and removal checks. Location management behind Details remains outside04-U scope
and unimplemented; disabled details are not proof of full native parity.

HUD resource formatting uses the achieved `plotinfo.nobles.bookkeeper_precision`,
transported as the additive `FortressSummary.bookkeeper_precision` field. It is
independent of the requested bookkeeper setting. Session v8 remains compatible:
older snapshots omit the field and decode to -1 (unknown); the viewer leaves
resource figures blank instead of manufacturing a precision. Rebuild bridge and
viewer to receive the new field. Epoch/unload clears it with the summary.
Native protected captures 20260929-145258/145456 establish zero as `None`, exact
thresholds and significant-digit rounding, including the pinned int32 overflow
edge. `fixtures/hud/native_resource_counts.json` records 546 rendered Drink
references with source hash; `fortress_hud_test` compares every case and checks
precision-only refresh and missing-field handling. This is count-text evidence,
not acceptance of the whole HUD layout or the five detailed resource columns.
`tools/smoke/hud_resource_acceptance.ps1 -SaveId <new-df3d-areas-name>` compares
native rendered Drink text to actual bridge/model/HUD output on a protected,
paused, never-saved clone; restores counts/precision and verifies save manifests.

Management protocol v25 uses `Local\df3d_management_v25`. Rebuild/install the bridge
and viewer together; v24 peers cannot share this region. `LocationChoices` area
operation20 reads temple (`location_kind=2`) or guild (`location_kind=4`) catalogs.
Use AreaInspect/Zone with no area ID, cursor0 initially, then the returned catalog
revision for continuation. Typed replies preserve practice IDs, names, counts,
deity/sphere order and guild metadata. Snapshot changes or unavailable observations
invalidate page receipts; stale reads return no catalog. The shared validator caps
pages at128rows and nested payloads, rejecting malformed/mixed replies.

Temple/Guildhall selector views consume these catalogs and the captured native
label mappings. Protected run `build/areas-acceptance-20260929-105813` verifies
all54 temple and69 guild hover strings through the actual views against separate
native captures, including native name truncation, Back navigation and temporary
zone cleanup. It exited0 with clean diagnostics and unchanged source/clone saves.
This is headless view acceptance; location creation effects/defaults, physical
input and rendered parity remain unfinished. Older screenshots showing Search
and Hide established include DFHack's `sort.location_selector` overlay; those
controls are not part of the native DF selector reference.

Protected creation comparison `build/areas-acceptance-20260929-111235` exercises
the actual selectors for no deity, a named deity, religion and guild creation.
It identified a location-value defect (native62 versus bridge0) and verified the
Guildhall members-only access correction. Follow-up112717 fixes initial creation
value through the supported game's location calculation; all four cases now match
all captured fields. Both runs exited0 with clean diagnostics and unchanged saves.
The native entry point is guarded by PE machine/timestamp/image size, a full-routine fingerprint
and compile-time structure offsets in `bridge/plugin/location_value_native.h`.
Unknown binaries reject creation before publication. The call takes semantic
contents and location identity; it does not read native UI state. Broader terrain,
furniture, multi-zone and later assignment/update behavior remain unverified.
Expanded protected run113105 covers Tavern, Library and Hospital as well: seven
creation cases across all five kinds match every captured field. Temple/Guildhall
value is62 for the test zone; Tavern/Library/Hospital value is44. These are observed
results of the native calculation, not constants in the implementation. Diagnostics
are clean and both saves unchanged. Reassignment/removal still need value checks.
Protected114125 adds actual-controller removal against native references for all
seven cases. Native removal clears both location and site IDs, removes membership,
and recalculates the former location to0. The bridge now matches those effects,
correcting its previous retained site ID and stale value. Build and protected
acceptance pass with clean diagnostics and unchanged saves. Reassignment between
two locations and locations with remaining zones still need separate acceptance.
Protected114509 verifies selecting the former location from the existing-location
list after removal. All seven cases restore membership, site identity and native
value (62 for Temple/Guildhall;44 for the other kinds), with clean diagnostics and
unchanged saves. Transfer between distinct locations remains unverified.
Protected115127 verifies creating a new Tavern while assigned to each of the seven
original location cases. It identified and fixes stale former-location value in
the creation path: both locations now recalculate after membership moves. Native
and controller values match0 for the former location and44 for the new Tavern.
Build and protected checks pass, with clean diagnostics and unchanged saves.
Choosing a different existing location and multi-zone contributions remain open.
Protected120013 verifies transfer from the replacement Tavern to each original
existing location. All seven cases match native source value0, destination value
62 or44, and exact membership changes; diagnostics are clean and saves unchanged.
Locations with multiple zones and varied terrain/furniture remain separate gaps.
Protected120429 adds a one-tile zone on the next elevation to each existing
location, then removes that assignment while retaining the original nine-cell
zone. Fourteen comparisons match native membership and values: Temple/Guildhall
62->64->62; Tavern/Library/Hospital44->44->44. Diagnostics are clean and saves
unchanged. Overlapping zones and varied terrain/furniture still need coverage.
Protected120857 adds an overlapping one-tile second zone alongside the separate-
elevation case. All28 comparisons match native DF: overlap leaves Temple/Guildhall
at62 and other kinds at44, without double-counting, and removal preserves those
values. Diagnostics are clean and saves unchanged. Varied terrain/furniture remain.

The GPU `area_location_capture` check renders recorded temple/guild catalogs and
compares every displayed row caption against native screen text. Prepare ignored
`build/notes/pm/location-render-source/` with `location-transport-comparison.json`,
`native-location-metadata.json`, `native-location-scroll.json`,
`native-location-scroll-art.json`, `native-location-scroll-states.json`,
`native-list-scroll.json` and
`provenance.txt` identifying the protected source
run. Missing inputs report incomplete; these local captures are not shipped fixtures.
The check writes images to `build/qa/location-render/`. Caption agreement and rendered
captures do not establish physical input or full visual parity. Current corrections
match native 29-cell name truncation and 12-pixel hover line spacing. Temple/guild
selectors use the native shrine/guild art at32x32 with a two-pixel inset,40x36
picture frames, regular rectangle row backgrounds and captured WHITE/LCYAN/YELLOW
colors. The first ten rows and Back buttons match native reference pixels exactly
in both selectors. The location frame now uses native bounds368,52 through696,472
and8x12 content margins; all four frame edges also match captured pixels exactly.
Remaining states and physical input still need comparison; these regional matches
do not establish full screen parity.

Protected140512 records134 native temple/guild scrollbar inputs in
`native-location-scroll.json`:12px arrow regions move one row, track/context paging
moves ten rows, context scrolling moves one, and standard scroll keys are inert.
The capture accounts for the native1200x800 screen's150x66 tile grid and4px
vertical inset. Protected140912 expands this to886 input observations, including
every drag destination pixel90..470 for each catalog, and105 normal thumb states.
Both protected runs have clean diagnostics and unchanged source/clone saves.
The selector now uses a dedicated native scrollbar: wheel moves one row, Shift-wheel
pages ten (matching installed context bindings), arrows/page clicks and tile-based
dragging match recorded inputs. GPU acceptance compares its normal rendered tiles
at all105 positions directly with the installed atlas referenced by native captures;
all604800 pixels match. Catalog replacement explicitly refreshes ScrollContainer
layout so the old catalog height cannot clamp a longer list. Direct control input
checks are supplemented by viewport-routed mouse events for all878 recorded mouse
cases, wheel/Shift-wheel over row buttons, release outside the bar and hide-during-
drag cleanup. After scrolling, a routed click emits exactly one request for the
displayed practice/profession with the current area revision; routed Back emits no
mutation. These standalone view checks do not exercise the full fortress scene or
live mutation effects. Protected142533 adds120 tile states for hover/pressed input
and catalog sizes0,1,9,10,11,12,14,20,40,100,140,280. Native vectors are restored,
diagnostics are clean and both saves unchanged. The native thumb's inclusive visible
span is `1 + floor(track_cells * (page_rows - 1) / total_rows)`, with a two-cell
minimum; shorter lists exposed and corrected the earlier proportional-size formula.
Rows extend through the scrollbar column when ten or fewer choices are present.
All120 states match691200 additional GPU pixels. Held-arrow timing and short-list
name truncation remain open.

`tools/smoke/areas_acceptance.ps1 -LocationScene -SaveId <new-df3d-areas-name>` runs
the focused full fortress-scene GPU lane. It uses viewport clicks/wheel input for
location creation, Back and removal, with independently captured native creation
references and readback. Protected144123 passes all seven cases (unaffiliated,
deity and religion temples, guildhall, tavern, library, hospital), native default
fields/value/membership and removal, plus native-state guards around Back. Source
and clone saves are unchanged. The run has only the known separate-render-thread
notice, so reports passed_with_known_issues. Fixture zone creation/deletion use raw
semantic requests and are not claims of pointer painting acceptance. This lane
found a catalog-arrival race: the thumb could advance before ScrollContainer's
extent updated, causing a click to select the old displayed row. Native row position
now owns scrolling and is reapplied after queued layout; the controller also avoids
replacing the unchanged location frame each tick. The scene lane checks row geometry
before selection as well as actual native effects after it. Remaining Areas and
other approved-screen requirements are not completed by this lane.

Existing-location lists use the same native scrollbar with five visible rows when
assigned and six otherwise. Protected153010 records535 inputs and330 art states
for both layouts; the GPU check routes those inputs and compares visible scrollbar
pixels with the installed atlas. Hidden-bar states check visibility and row width;
disabled Details is excluded. The model fetches every page of the immutable
location receipt before enabling assignment, so the final thumb uses the full list.
Partial rows can appear disabled while paging; loading-state parity is unverified.
Protected153917 extends the full scene lane with wheel, arrow and endpoint drag
checks in both layouts, native-state guards during scrolling, and selecting a
scrolled row after removal. All seven location cases match native reassignment
membership/site/value and subsequent removal. Both save manifests remain unchanged;
only the known rendering-thread notice occurs. Input is routed through the viewport,
not OS mouse automation. Held-arrow timing, large real multi-page lists, Details
and broader Areas promotion evidence remain incomplete.

Protected154554 establishes that selecting an already-assigned location closes
the native chooser while preserving zone selection, membership, site and value.
The presentation now closes through the normal Back path without sending a
mutation. Protected154753 accepts this with viewport clicks in all seven location
cases, alongside creation/scrolling/removal/reassignment. Native guards include
location value; saves remain unchanged and only the known thread notice occurs.
The controller regression also asserts no transport request for current selection.

`fixtures/areas/native_location_details.json` records six native Details screens
and152 controlled supply conversions from protected155506. Stored thread/cloth/
powder/soap counts round up from internal units; desired counts truncate. The
fixture includes the native signed-int32 overflow cases and source provenance.
Details also needs independent access, staffing, furniture, room, value-visibility
and editing semantics; this capture does not implement or expose the screen.
Never use native location_details UI state as a runtime source for those facts.

`df3d location-details-read <site id> <location id>` observes the partial Details
core at a safe point: identity/name/kind, access flags/mode, profession/tier/raw
value, recognition, desired copies, ten raw supply quantities and zone IDs.
It refuses foreign/invalid current-site identities and unsupported/deleted/ruined
locations. Use the protected lane's DFHack invocation helpers. This diagnostic
does not expose a panel or permit edits; raw value is not proof it should be visible.
Protected160428 compares336 observations with native labels and scalar/membership
facts plus four invalid identities; controlled metadata and both saves unchanged.
Native160005's168 access-button transitions are retained in
`fixtures/areas/native_location_access.json`. All types have Visitors/Residents/
Citizens controls; Temple/Guildhall also have Members. Those buttons normalize the
three flags, while labels use members > visitors > residents > citizens precedence.
Transport, staffing/furniture/rooms, value visibility and mutation acceptance remain.

Management v26 introduced read-only `AreaOperation.LocationDetails` (21).
The current channel is v29 as described above; rebuild/install bridge and viewer
together. Session v8 and map recordings are unchanged.
The request carries `location_site_id` and `location_id`, not an area ID. The
response carries the verified Details core through the model and Godot extension,
with a stable receipt over all observed fields. Typed validators reject mixed
payloads, malformed identities/access/supply ordering and oversized payloads.
The224-KiB byte budget refuses oversized membership data without truncating it.
No panel text is fabricated for rejected reads.

Protected161940 verifies36 Details reads across baseline, paused supply/access
changes and restoration, stable repeated receipts, unchanged unrelated locations
and wrong-site refusal without a Details payload. It also reruns all seven actual
scene creation/scrolling/assignment/removal cases. Saves are unchanged; only the
known separate-render-thread notice remains. Stable-source core and management
contract gates pass. UI callers still need observed site identity in chooser/
assigned-zone metadata, and Details remains disabled pending its missing native
facts, controls, view and acceptance. This transport milestone is not screen parity.

The location guard checks all4880 routine bytes using the pinned FNV-1a64 fingerprint;
the supported PE has no base relocations in that range. The offline
`tools/qa/location_guard_probe.cpp` accepts an extracted routine file (ignored build
output only), verifies the pinned bytes, flips one bit at every byte offset, mutates
each machine/timestamp/image-size bit, and rejects all truncated/oversized/null inputs.
Build it with the configured C++ compiler and pass that file as its only argument.
The9843-check probe and protected115642 pass. The latter verifies the fingerprint in
the loaded game and all current location lifecycle comparisons, with clean diagnostics
and unchanged saves. This is a compatibility guard, not an executable authenticity check.

Protected103910 passes54temple and69guild rows through actual model/Godot transport,
stable rereads and stale-receipt refusal, with clean diagnostics and unchanged
saves.297model tests,96policy tests and Areas QA pass. Native multi-page changes,
the actual selector views, creation effects and rendered parity remain unfinished.

Management protocol v24 uses `Local\df3d_management_v24`. It adds the read-only
PaintCounts area operation: local draft spans, an optional preview rectangle,
zone type, elevation and an echoed 64-bit count generation. Replies keep unknown
painted/preview counts as -1. Rebuild the bridge and viewer together; v23 peers
cannot share the v24 region. The command capacity is unchanged: a maximum-size
draft plus the preview rectangle fits one request. Map recordings are unchanged.
The painter uses a separate, coalesced read ticket and rejects replies after local
draft/preview, elevation, tool or session changes. Idle reads refresh native
dependencies even while paused; unknown counts never become zero. Protected
headless protocol/controller acceptance passed on 2026-09-29. Native gesture and
full rendered acceptance remain separate; Areas is not promoted.

Management protocol v23 uses `Local\df3d_management_v23`. It adds semantic
MultiCreate, MultiUndo and MultiFinish area operations, an interaction identity
and opaque Undo token, and explicit room outcomes and native result counts.
Multi selection geometry uses origin/width/height and furniture kind; complete
Undo history belongs to the bridge, independently of the 64-record AreaInfo
reply limit. Empty successful selections have no Undo token. Unknown outcomes
never authorize replay. Native dispatch now owns the scoped receipt and prepares
entity/terrain invalidation around creation and Undo. The controller now routes
Multi rectangle selection and scoped Done/Undo; Bedroom and Dormitory result
counts remain distinct. Focused protected Multi protocol acceptance passed on
2026-09-29; controller input, rendered parity and broader lifecycle
acceptance remain pending, and Areas remains hidden. Rebuild
bridge and viewer together; v22 peers cannot share
this channel. Command/reply capacities and map recordings are unchanged. The
schema migration must remain separate when preparing commits.

Management protocol v22 uses `Local\df3d_management_v22` and adds observed
location type, owner profession and owner sex to area inspection replies.
Rebuild and install bridge and viewer together; v21 peers cannot share this
channel. Unknown values remain type 0, empty profession and sex -1. The command
buffer and single-request paint semantics remain those of v21 below. Map
recordings are unchanged. Protocol v22 passed protected Areas semantic and restart
acceptance on 2026-09-28, including native location-type and owner-metadata checks.
This does not establish completion of the Areas UI.

`tools/smoke/areas_acceptance.ps1 -Controller -SaveId <new-df3d-areas-name>`
exercises the actual Areas controller and action service against a protected,
never-saved clone, with native readbacks for drafts, stockpile edits and zone
navigation/assignment. This headless controller check supplements semantic
acceptance; it does not verify viewport pointer routing or GPU parity.
Use `-ControllerScene` instead for the main-scene GPU lane: toolbar clicks,
stockpile/zone painting, Accept and removal through viewport input, rendered
captures and native readbacks, including visible owner portraits, recentering and
owner assignment/removal. This supplements rather than replaces the broader
headless controller suite. Add `-BoundaryOnly` to `-ControllerScene` for a focused
zone geometry regression: mixed floor/wall, wall-only and fortification creation,
wall addition during repaint, and native exact-extents readback and removal.
This focused driver is not full Areas acceptance and cannot be combined with
`-ControllerRestart`. `-ControllerRestart` checks actual producer replacement,
retirement of the old controller state, request outcome reporting and explicit
reopening against the new epoch; it does not claim an unknown outcome when the
submitted read completes before shutdown. Combine `-ControllerScene -ControllerRestart`
for a GPU main-scene restart with a local pointer draft, retired UI checks and
explicit pointer reopening/editing against the replacement fortress.
`scene_reconnect_gpu` covers recorded scene replacement through an empty interval.
`areas_acceptance.ps1 -MultiOnly -SaveId <new-df3d-areas-name>` is a separate
headless v23 room-creation/Undo protocol lane using the region5 source bed and
independent native footprint/default/identity readbacks. It covers successful
Undo, empty/in-use replacement, changed-target refusal, Done and foreign
interaction refusal, plus Office/Dining Hall/Tomb, two Bedrooms, Dormitory and
mixed in-use/unenclosed results. Native numeric references with capture provenance
are in `tools/smoke/areas-multi-reference.json`. Whole-set Undo checks furniture
links, and a changed second room must prevent deletion of either room.
The protocol lane also covers a single selection producing both a Bedroom and
a Dormitory, comparing native geometry/defaults and undoing the complete mixed
set. This passed on 2026-09-29 with clean diagnostics and unchanged save manifests;
rendered acceptance of the mixed result remains separate.
Native Floored building occupancy overrides the underlying room-boundary shape
for Multi traversal, while deep-water and magma barriers still apply. A missing
override previously split a native45-tile Dormitory into a25-tile discovery.
The classifier correction passed77 bridge-policy tests and protected Multi
acceptance on2026-09-29, including seven native Floored reference cases and
whole-set Undo with clean diagnostics and unchanged save manifests.
It also creates a second real management client: foreign Undo/Finish cannot
consume the original owner's receipt, and an explicitly reconnected management
channel cannot reuse its old token. World-stream detach and management reconnect
are separate operations; the action service handles their session boundary.
Add `-Controller` for the headless Multi controller/action-service reconnect
lane. It verifies automatic generation invalidation, queued-selection retirement
as unsent, cleared local Undo authority, bridge refusal of an old token after
explicit controller reopen, and successful new creation/Undo. This passed on
2026-09-29. It also verifies a mixed Bedroom/Dormitory selection through the
actual controller: one semantic intent at the second corner, exact captured
native result text, whole-set Undo and Done returning to the zone chooser while
retaining both rooms and clearing local authority. This headless coverage passed
with clean diagnostics and unchanged save manifests; it does not establish
rendered or viewport pointer parity. The lane also dispatches a selection whose completed native receipt is
deliberately not observed by the action service before disconnect: the service
reports unknown, retires dispatchable work, and cannot restore old local authority
after reopening. The independent test records native completion separately from
that unknown controller outcome. Add `-ControllerRestart` instead for the
headless Multi producer-replacement lane. It preserves the minimal Multi fixture
across a real DF restart and verifies cleared gesture/catalog/Undo authority,
idle state until explicit reopen, old-token refusal and fresh creation/Undo.
This passed on 2026-09-29 with clean diagnostics and unchanged save hashes;
it establishes lifecycle behavior, not rendered parity.
Add `-ControllerScene` for the focused GPU Multi driver: toolbar and map-corner
input, all four furniture modes, two Bedrooms/Dormitory, rejection results,
Undo/Cancel and Done retaining rooms, captures and native readbacks. That path
passed on 2026-09-29 with the documented separate-thread renderer notice;
broader gestures, overlays, lifecycle and full rendered parity remain open.
Native Multi keeps the first rectangle corner across elevation changes and
completes on the ending level. Escape/right-click cancel only a partial rectangle;
without one they exit the tool. The controller now follows these observations.
The expanded gesture driver passed its assertions and native readbacks, but its
2026-09-29 GPU run failed on unexpected RID/occluder diagnostics. This is not
successful GPU acceptance; the deferred renderer issues remain unchanged.
`-MultiOnly` supports headless `-Controller`, headless `-ControllerRestart`, or
GPU `-ControllerScene`. It cannot combine the GPU mode with restart, and does
not support `-BoundaryOnly`.
The semantic mode alone does not establish controller input or rendered Multi parity. Its fixture uses
the existing native furniture, applies pause/autosave/announcement protection and
skips unrelated general Areas fixture objects. Named reference cases temporarily
change room-use types or a wall tile to reproduce the captured native setup,
then verify restoration. Exact existing-zone snapshots, including collision flags,
and furniture links must survive each scenario's cleanup.
The loader switches from the save chooser to a dedicated loading panel immediately
after a load command is submitted. Its title artwork, font, border and named
`SKILL_PROGRESS_BAR_*` segments resolve from the installed DF assets; no game
art is shipped. Native save loading has no percentage in the session protocol,
so the bar animates indeterminately. During map transfer it displays actual
known/total block counts, then animates during final presentation preparation.
Only the existing readiness gate exposes play; errors return to the chooser.
These are stage indicators, not an estimated overall load percentage.

The loading screen conceals the world with the camera layer mask while keeping
render owners active; hiding the root during replacement triggers uninitialized
RID errors in the supported renderer. The original mask is restored on entry.
This path passed protected main-scene restart acceptance on 2026-09-28, with only
the documented separate-renderer startup notice. Areas promotion remains separate.

The read-only DFHack diagnostic `df3d paint-water-read <x> <y> <z>` reports
water-source and fishing Paint eligibility at a safe point: 0 unknown, 1 ineligible,
2 eligible. It observes the bank, adjacent openings and water immediately below;
salt water qualifies for fishing but not a water source. It returns no hidden
terrain details and does not read native widgets or staged edits. The companion
`df3d paint-base-read <x> <y> <z>` returns ordinary and Pond eligibility with the
same codes. The observers now classify all 19 non-sentinel native shape groups;
sentinel/unrecognized shapes and missing observations remain unknown. Ordinary
Paint deliberately differs from Multi traversal for twigs. Pond counts open space,
ramp tops and endless pits independently of occupancy and liquid depth/type.
The expanded primitives passed 1,478 paired native comparisons on 2026-09-29,
including all 13 ordinary zone types, with unchanged save hashes.
`df3d paint-material-read <x> <y> <z>` reports sand/clay eligibility with the same
codes, using native soil/material facts rather than display names. It passed 604
paired reference comparisons and 48 native soil-fallback controls on 2026-09-29,
with unchanged saves. The v24 count operation supplies these predicates to the
painter. Use the protected lane's DFHack invocation helpers for the diagnostics.

`observeNativePaintCounts` now combines those observers for a supplied local draft
and preview at one safe point. It counts overlapping cells only in the painted
term and preserves the native positive preview term during erase. Invalid geometry
is rejected before terrain reads; an unobserved term remains -1 rather than a
partial total. The reducer passed the eight recorded native add/erase states and
the 88-test bridge-policy suite; the MSVC bridge build passed. Run
`tools/smoke/areas_acceptance.ps1 -PaintCountsOnly -SaveId <new-df3d-areas-name>`
for focused headless protocol/controller acceptance on a protected clone. This
passed on 2026-09-29: eight independent recorded native count cases, exact
controller captions, paused external terrain refresh and elevation changes,
clean diagnostics, restored fixture and unchanged source/clone saves. It does
not establish physical input, freehand or GPU appearance. Follow-up headless
acceptance also covers two-click rectangles, independent rectangle erase and
preservation of a pending corner when toggling erase. Native exit reference
checks distinguish Escape/right-click (keep completed painted cells and exit)
from Cancel (remove the new zone and return to the chooser), with and without
a pending rectangle. The zone controller now applies completed gestures through
an action-service-owned Paint session. Pending edits drain using authoritative
IDs/revisions after the panel closes; unknown outcomes stop without replay.
Focused protected controller acceptance covers immediate rectangle add/erase,
nonempty Escape retention, new-zone Cancel, empty Escape deletion, inert empty
Accept, and repaint Accept with a pending corner. Paint-to-Multi now waits for
deletion of the ordinary zone before enabling room selection. Native and actual
controller checks cover preserving a pending rectangle corner and erase state
across both mode directions. Rapid close/reopen acceptance verifies the old
session's queued erases and empty-zone deletion precede the new interaction.
The service permits one same-domain mutation continuation only inside a
successful sent mutation's observer; rejected/unknown outcomes and read replies
cannot use it. Ordinary requests retain FIFO order. Native input-feed and actual
controller checks also cover sparse brush sampling (no interpolated cells), brush
erase, release/unheld motion, second-press rectangle completion and a preserved
corner across Rectangle/Brush switching and Brush/Multi round trips. The latter
retains the saved Rectangle corner without treating Brush as held on return.
The general headless Areas controller lane also passed after updating its bedroom
gesture to the native two-click sequence. Native references and actual-controller
checks also preserve an empty painter's corner across elevation changes in
Rectangle, Brush and Brush/Multi, completing on the ending level. For painted and
existing repaint zones, the original plane and identity persist; other-plane
clicks are ignored. Rectangle retains its pending corner across the round trip,
while Brush resumes sampled edits on return. Both paths pass protected controller
checks with exact native masks. Physical pointer routing, broader lifecycle and
rendered parity remain open.
The bridge now supports native zone erase-to-empty: it retains the zeroed mask,
bounds and identity for redraw. Empty-zone observation requires every allocated
tile to be loaded/revealed, without claiming any visible occupied cells. Focused
protected acceptance verifies nine cells -> empty -> one cell with the same ID,
hidden-tile refusal without mutation and deletion cleanup. The 89-test policy
suite and MSVC build pass. Native references also show that Escape removes an
empty zone while Accept leaves it in Paint; these transitions now pass through
the actual controller. Stockpile empty-footprint behavior is not established
by these zone tests.

The read-only DFHack diagnostic `df3d room-read <x> <y> <z>` observes a room seed
at a safe point and emits JSON with the 43-by-43 observation window and reached
extent mask. Status values follow `RoomTraversalStatus` in
`bridge/plugin/room_discovery.h`: complete, unenclosed, incomplete observation,
or invalid input. Use the protected lane's DFHack invocation helpers. This query
does not create zones, provide Undo, or establish completion of native Multi.
Non-door dynamic buildings currently remain unobserved pending native evidence.

The read-only `df3d location-religions-read` diagnostic observes ordered temple
choice identities from civilization deities and eligible units' historical links.
It returns `valid` and `choices` with semantic kind1 none,2 deity,3 religion and
per-choice `worshippers` counts;
these differ from native enum values. No native selector state is a runtime input.
Protected092101 compares all identities/order against native DF for the baseline,
25 controlled eligibility cases and restored state, with clean diagnostics and
unchanged saves. Follow-up092956 compares all54 compiled-reader worshipper counts
to native hover text, with clean diagnostics and unchanged saves. The reader is
not yet exposed through management transport or
the location UI; choice metadata/counts and Temple/Guildhall workflow acceptance
remain unfinished. Use the protected lane's invocation helpers.

`df3d location-guilds-read` similarly returns the69 native offered professions
and their worker counts. Native group ranges deliberately include Stonecutter/
Stone Carver in Stoneworkers but exclude Papermaker/Bookbinder from Craftsmen;
secondary profession does not contribute. Protected093835 compares all69 baseline
counts and16 controlled profession cases, including restoration, with clean
diagnostics and unchanged saves. Guild establishment/member/meeting-place metadata
and management/UI integration still require completion.

The religion/guild diagnostics also return `has_temple`/`has_meeting_place` from
current-site locations. Native095120 establishes that deletion and either ruin
flag suppress these indicators, while access flags, owner, recognition and an
invalid zone ID do not. Compiled-reader acceptance095442 passes42 paired native
comparisons across20 controlled cases and restoration, with clean diagnostics and
unchanged saves. These metadata fields are not yet transported to the location UI.

The guild diagnostic also returns `guild_id` and `members`. Current-site capital
entity links identify Guild entities with matching profession-promotion focus;
eligible active/FortControlled unit MEMBER links supply membership counts.
Protected100303 passes35 paired native observations across17 controlled cases
and restoration, with clean diagnostics and unchanged saves. For multiple guilds
of one profession, the first eligible guild in current-site entity-link order
wins. Protected101458 verifies swapped identities and both single-guild controls,
including zero members, with clean diagnostics and unchanged saves. Management
transport and selector integration remain unfinished.

Location diagnostics include native translated names (with CP437 initial
capitalization) and ordered deity/sphere identities. Protected100906 verifies54
compiled names and53 deity records against independent facts and native rendered
labels, with clean diagnostics and unchanged saves. Sphere IDs require native
caption mappings in presentation; these diagnostics do not expose the selectors.

`panels/area_location_labels.json` holds exact native mappings for all130 supported
sphere IDs and69 guild professions, with capture provenance. Protected101825
captures each sphere caption and verifies its compiled identity, then restores the
fixture, with clean diagnostics and unchanged saves. All58 sphere labels observed
in the baseline agree. The mapping still awaits selector integration.

`df3d room-seed <building id>` reads furniture identity, position and room-use
relations at the same safe point. Its JSON `furniture` values follow
`RoomFurniture` in `room_discovery_native.h`; `valid` distinguishes supported
furniture from missing/unsupported targets. `in_use` reflects native room-use
zone types, not every overlapping activity zone. It does not authorize creation
without room traversal, current-state validation and mutation acceptance.
`df3d room-plan <furniture 1..4> <x> <y> <z> <width> <height>` combines those
observations into a read-only selection plan, including exact room extents,
Bedroom/Dormitory classification and native rejection counts. It retains native
building-vector order. This diagnostic does not create rooms or implement Undo;
unknown traversal observations cannot become a complete mutation plan.
`df3d room-create <furniture 1..4> <x> <y> <z> <width> <height> <epoch>` is a
mutating diagnostic for protected native acceptance. It requires the current
fortress epoch, a paused game and no save in progress. It returns creation status,
error, rejection counts and IDs; status values are in `room_mutation_native.h`.
Unknown outcomes must be inspected, never replayed. This command has no Undo
receipt and does not establish completion of the management protocol or Multi UI.

Management protocol v21 uses `Local\df3d_management_v21` and a 256-KiB command
buffer so one paint request can contain a complete supported footprint (up to
32,768 tiles/spans). This replaces v20's 384-tile/128-span paint limit and 4-KiB
command buffer. Rebuild and install the bridge and viewer together; v20 peers
cannot share the v21 channel. Map recordings and their schema are unchanged.
Protocol v21 passed protected Areas semantic and restart acceptance on 2026-09-28;
this does not establish completion of the painting UI.
Paint mode 3 replaces an existing area's footprint in one revision-checked edit;
modes 1/2 retain add/erase semantics, and creation uses mode 1. Replacement allows
one accepted draft to add and erase cells without an intermediate partial edit.

There is no CI; all checks run locally and most need the game installed. The core C++ tests run
with the `ctest` command above. For the broader suite:

```powershell
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tools/qa -p "test_*.py"
python tools/qa/verify.py
```

Results and logs go in `build/qa/`; missing prerequisites are reported as incomplete.
`python tools/qa/verify.py --help` covers GPU and live-game checks; the
[test manifest](tools/qa/checks.json) lists what each group covers. Known Godot engine warnings
are reported as `passed_with_known_issues` (rules in [tools/qa/diagnostics.py](tools/qa/diagnostics.py));
they are recognized only by the Steam build's version string, so the official Godot download
runs the viewer but fails those checks. The separate-renderer shutdown can also leak two plain
engine Objects. Empty projects with no DF3D scripts or extension reproduced this on
D3D12 (2026-09-28) and Vulkan (2026-10-07), using the pinned engine.
The classifier recognizes exactly that pair only with the same pinned process's
D3D12 or Vulkan renderer, startup notice and known finalize callsite; extra objects,
other renderers, changed callsites and isolated leak warnings still fail. Raw traces
are in `build/notes/pm/leak-isolation/` and
`build/notes/vulkan-acceptance/empty-vulkan.log`. This remains a known engine
issue, not a clean pass. One known failure: the GPU combat test reports a
misaligned billboard hit effect.

### Windows rendering backend

Border-drag resizing is disabled in project settings because horizontal drag
jiggling still caused Vulkan device loss with the attempted native resize guard.
That guard and its Windows subclass are removed. Window resolution and display
mode are changed through Settings, with Keep/Revert and timeout rollback.
Explicit Apply/Revert pauses frame submission and drains rendering around the
bounded window change. Separate rendering remains enabled during normal play;
there is no native window hook or per-frame synchronization.

Vulkan is the Windows default; launch with `--rendering-driver d3d12` for the
D3D12 fallback. The pinned Godot D3D12 path allocates separate vertex, attribute
and index resources per material surface. Small resources incur substantial
allocation padding; logical Godot buffer counters do not include that padding.
Vulkan avoids the observed memory amplification without changing terrain encoding.

Acceptance on Godot 4.7.2 Steam / RTX 3080 Ti (2026-10-07) exercised two Warmbeers
fixture loads, each with 20 maximize/restore transitions while terrain assembly
was pending. Both completed, with camera modes, level changes, FPS entry/exit,
post-load resizing and nonempty viewport capture. Interaction, camera mode, walk
camera, cutout picking and terrain occlusion suites passed with known engine
diagnostics. The prior maximize-during-loading swapchain failure did not recur.
Scripts, logs, captures and the scene-reachable surface census are in
`build/notes/vulkan-acceptance/`. This establishes recorded-fixture acceptance on
that GPU/driver; live save loading and other graphics adapters are not covered.

### First-person camera ownership

Walk groups movement, jump/stairs and mouse/mode controls inside the existing
DF HOVER_RECTANGLE frame, using the shared runtime DF font at its native 12px
size and HUD scale. Yellow keys align beside their actions; hold bindings are
explicit. The mouse row switches between Click/Look around and Esc/Release mouse.
F5 is the displayed exit binding. Full instructions remain in Help, including
the alternate F4 exit. Camera-blocking menus hide the hint.

Walk (F5) transfers the actual camera eye and direction into the local gravity
controller, without choosing terrain, moving to a floor, or changing Truescale,
visual style, or creature size. Entry requires loaded terrain. Space above and
beside the map is air; unknown interior tiles remain collision barriers. Cursor
release stops movement input but gravity continues; modal input blocking pauses
movement. Leaving Walk resumes Free controls at the current eye and direction,
retaining the current cutaway. Explicit map/entity focus can then reposition it.
Connected up/down stair tiles support continuous movement at two levels per
second: hold Space to climb and Q to descend. Space remains jump elsewhere.
Climbing stops at the end of the connection without auto-jumping; releasing the
control restores gravity. Stair motion uses the full body collision sweep, so
adjacent ceilings/walls still require clearance. No lateral centering or camera
snap is applied. The controller never sends simulation commands to DF.

### Installation and shipping checks

Setup records `df3d-install.json` in the selected installation. Its format-1
record contains the installed DF3D version. Matching versions launch; a different
version offers Update. The record is trusted: launch does not hash DLLs, check
extra plugins, or verify that users retained installed dependencies. User changes
remain the user's responsibility. The required DF executable build is still checked.

A clean installation has no DFHack files. Existing unmarked DFHack is rejected. Installation receipts do not establish
version or ownership; there is no migration from pre-marker installations.
A malformed marker fails clearly rather than being ignored.

The version record is written last within the installation transaction. Restore
recovers its previous version or removes it for a formerly unmarked installation.
Package integrity hashes, install backups and safe restore checks remain; they
are separate from installed-version detection. `test_lifecycle.py` covers trusted
user modifications, version changes, rejection without a marker, marker rollback,
and installation/restore behavior with isolated synthetic files.

The product has one Godot process and one window. Its entry scene shows setup;
Play asks the hidden C# controller to prepare native DF, then replaces setup with
the main game scene in that same process/window. Setup owns and releases its art,
controls, and close handler during the transition. The game applies its normal
display preferences and save-aware exit confirmation. There is no hidden setup
window or return to a launcher after play.

Steam suggestions are validated once before the chooser opens; selecting a
suggestion uses that result. Checks read the version record, not installed DLL
contents. Manual paths are checked when chosen. Acceptance, installation and
launch revalidate on disk. A validated target supplies DF artwork, acknowledgment
is remembered per installation, and compatible returning players go straight to
startup. Failed startup cleans native DF and leaves setup available for retry.
Install and restore retain their transactional backend. Closing during a file
transaction waits for that transaction; closing during startup ends the session.

The controller joins a kill-on-close Windows job before starting children. That
lifetime job covers the Godot app, native DF, command clients, audio helpers and
all descendants even after abrupt controller termination. Native DF has a nested
job and private desktop. App exit or native DF exit ends the controller and the
whole session; setup does not reappear. The audio guardian gets a bounded chance
to restore its changes during orderly cleanup. A per-run request/response channel
serializes setup operations; Play responds once DF is ready, rather than waiting
for the game to exit. The bundled Godot icon is hash-pinned in the payload audit.

Lifecycle stand-ins cover normal/crash exits in both directions, partial startup,
nested jobs, helper grandchildren, controller exit/crash and unrelated-process
isolation. `tools/release/test_setup_session.ps1 -Payload <payload> -Game <copy>`
checks the real scene handoff, unchanged process/window identity, startup failure,
native DF death, app closure and forced termination against a disposable game
copy under build. It runs inside the protected lane and never loads a save.
Process cleanup cannot recover unsaved game progress after crashes or forced
termination.

Save locations stay on one line with middle elision; hover and Copy path expose
the full location. After targeting, occasional decorative dwarves walk beneath
the panel using the shared actor walk pose, mirrored to face their travel direction.
Setup composes 96 male and female appearances with different skin, hair, clothing and armor
from the selected installation's adult dwarf layer and palette definitions;
these do not represent live units or require starting DF. At most three walkers
are retained. The chooser keeps its Godot icon and no DF artwork is bundled.

The interactive setup mock runs with `tools/release/MockSetup.cmd` (or
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/release/mock_setup.ps1`).
It uses sample installation/save paths and in-memory acceptance/install state;
Browse only selects a path, Copy path explicitly writes the clipboard, and all
install/update/launch actions are simulated. The real supported installation is
read only for UI artwork. Asset cache, logs and test captures stay under
`build/setup-mock`. It never calls the release installer or starts DF.
The scenario picker covers first setup, no suggestions, incompatibility, install
failure, returning players, verified older DF3D updates and foreign DFHack
rejection. Restart resets the scenario; Reopen tests
the remembered in-memory state. Closing the harness discards it. `-Test` exercises
transitions and captures the acknowledgment screen. The mock entry point is excluded
from exports; its shared view also serves the production setup flow.
`tools/release/test_setup_ui.ps1 -Payload <extracted-payload> -Game <build-game-copy>`
checks real UI/backend targeting, acknowledgment, installation and remembered
reopen against a disposable copy under build, then restores its bridge. Its
profile and caches are isolated; it does not start a fortress. The package smoke
check separately verifies the exported viewer and bridge startup.

Discovery and launcher regressions use disposable Steam layouts and stand-in executables:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke/steam_paths_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke/menu_startup_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke/attach_lifecycle_test.ps1
```

With DF closed and the bridge installed, this protected check discovers the real installation,
starts DF at its title screen, verifies the bridge is enabled, and starts the headless viewer
to verify asset loading with a fresh asset cache. It removes developer tools from the child processes' `PATH`, records
binary hashes and logs under `build/install-connection-*`, and restores preferences on exit.
It does not load or save a fortress:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke/install_connection_smoke.ps1
```

The same check is registered as `install_connection_smoke` in the QA gate; selecting it there
requires `--allow-live` and an attested bridge. Direct invocation tests the currently installed
binaries, not whether they were built from the current checkout.

Before shipping a binary package, test the exact extracted package on a separate Windows x64
machine or clean account without build tools. Include a secondary-drive Steam library and paths
containing spaces; verify discovery, missing/unsupported game errors, bridge setup, GPU startup,
fortress selection, loading and saving a disposable fortress, relaunch, and normal/forced-close
cleanup. Record the package hash, Windows/GPU details and pinned DF version with the results.
Local stand-in tests and headless startup do not establish clean-machine or GPU compatibility.
### Build and verify a distributable

After building the root tools, extension and pinned DFHack fork, import the Godot project and run:

```powershell
python tools/release/build_payload.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/release/smoke_package.ps1 `
    -Artifact build/release-0.1.0/DF3D-0.1.0-windows-x64.exe
```

The builder reads `config/version`, discovers the Godot editor, stages DFHack from its build
outputs, includes notices, and writes the launcher, SHA256SUMS.txt, source-input hashes and audit
results under `build/release-<version>`. It requires the matching Godot export templates and
the pinned Microsoft redistributable; it never packages from a Dwarf Fortress installation.
Use `--godot`, `--strip`, `--crt`, `--vs-redist-notice` or `--output` to override build-machine paths.
These are builder settings, not paths embedded as launcher runtime dependencies.

The smoke check extracts the actual executable into a path with spaces, installs its bridge into
a disposable copy of the local game, uses a fresh asset cache and system-only PATH, starts the
exported viewer, and restores the bridge. `-SourceSave <save-directory>` additionally loads a copy
of that fortress and captures the GPU-rendered viewer. Logs remain under `build/package smoke *`.
This is a same-machine portability test, not a substitute for another Windows machine.

The asset audit inspects both loose files and the Godot pack. Unchanged upstream DFHack UI
artwork is explicitly allowed by the maintainer, with notices; extracted DF3D game assets and
caches are excluded. Release artifacts are unsigned. Publish the executable and checksum;
the internal `payload.zip` is not a standalone launcher.

## Development

### Bridge performance guidance (2026-09-28)

Prioritize smooth ordinary gameplay. Routine streaming and automatic refreshes should
be economical; brief simulation slowdowns from opening or using panels are generally
acceptable. Use judgment about caching, batching, incremental processing or synchronous
work, favoring simplicity unless there is evidence of a performance problem. Existing
streaming implementations can stay where useful.

Recurring panel refreshes are automatic work, rather than a new user interaction
on each poll. Choose an economical approach using measured workload costs; a
universal step ceiling is not an acceptance requirement.

Correctness, safe-point execution, ownership, stale-target checks, native effects and
unknown-outcome handling remain separate requirements. Keep the viewer asynchronous.
Memory, payload, geometry and retirement-storage limits retain their independent
justification. When simplifying an implementation, align scheduler accounting, helper
and result validation, and tests together. Documentation changes do not themselves
change existing binaries or contracts. See AGENT_INSTRUCTIONS.md section 2.

### Versioning

DF3D uses [Semantic Versioning 2.0.0](https://semver.org/). The current feature
release is **0.2.0**, following the published0.1.0 experimental preview.
The application version lives in `presentations/godot/project/project.godot`
(`config/version`); release tags use `v` plus that exact version, such as `v0.1.0`.
GitHub Releases is the authoritative published-artifact list; local RC packages
do not establish publication.

The compatibility surface includes documented launcher options and environment variables,
configuration and recording formats, and the public core/consumer interfaces. During `0.x`,
these are experimental: patch releases (`0.1.1`) contain compatible fixes, while feature
releases, breaking changes, or changes to the required DF build increment the minor version
(`0.2.0`). Release notes identify compatibility changes. `1.0.0` will establish a stable
compatibility contract; it does not mean every planned feature is complete.

The first release will be labeled **experimental** and marked as a GitHub prerelease.
That hosting label is separate from SemVer: `0.1.0` is a normal version in the initial
development series. If multiple test packages precede it, use distinct SemVer versions
such as `0.1.0-rc.1` and `0.1.0-rc.2`. Never replace a published version's package with
different contents. DF, DFHack, Godot and wire/schema versions remain independently pinned;
the app version does not imply compatibility with arbitrary versions of those components.

### Architecture

Authoritative game state flows from the bridge to consumers; validated semantic commands
return to DF through a separate command path:

```
DF  ->  bridge (bridge/)  ->  mirror (schema/)  ->  world model (worldmodel/)  ->  viewer (presentations/godot/)
                                   \-> debug consumer (consumers/)
```

- `bridge/`: the DFHack plugin (bridge) and its build glue.
- `schema/`: the FlatBuffers mirror format shared between processes (core).
- `worldmodel/`: the engine-independent game state model (core).
- `presentations/godot/`: the Godot project and native extension (viewer);
  `project/scripts/ui_availability.gd` is the registry of exposed UI surfaces.
- `consumers/`: the inspector, a debug consumer of the mirror kept working as a check.
- `fixtures/`: recorded and synthetic mirror captures used by tests.
- `third_party/`: vendored FlatBuffers and doctest.
- `external/`: the DFHack fork and godot-cpp submodules.
- `tools/`: QA gate, launch scripts and smoke lanes.

Engineering rules, also read by AI coding agents through `CLAUDE.md`:
[AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md) (section 2 is the architecture contract, section 6
covers submodules). The bridge builds against a DFHack fork (github.com/UncertainCat/dfhack, branch
`df3d/53.16`) plus the df-structures and dfhooks forks listed in [PINS.md](PINS.md). `tools/smoke`
holds profiling and debugging lanes; see each script's header.

### Rendering depth and sprite visibility

Floor shadows use the installed `WALL_SHADOW_*` artwork and the mesher's eight
wall-neighbor bits. They are composited into palette-resolved floor tiles,
cached by source tile, palette and neighbor mask, and retired on asset replacement.
`wall_shadows_53_16.txt` records all 256 masks from an owned native comparison;
the compositor tests cover alpha and rotation. This applies to visible floor
tiles, not an invented scene-wide lighting filter. Natural stone engravings use
the native non-palette engraving artwork (DF 53.16's dolomite sample matches its
installed RGBA image byte-for-byte).

Container contents and statue depictions are semantic observations. The additive
`MapItem` contents fields distinguish unknown (`UINT32_MAX`) from observed empty
and describe the first direct contained item in native reference order. Nested
contents are not flattened. The optional color descriptor comes from native
`getColorWhetherDyedOrNot`, so dyed cloth uses its observed dye color instead of
the undyed material palette. Unknown colors retain the material fallback.
The bridge refreshes them on ordinary item visits,
so a stationary container can change appearance. Palette-resolved content layers
are owned by the item sprite resource cache; asset/session replacement retires
them. `container_contents_test` verifies pixel changes on fill/replacement/empty,
stable placement, dye-only recoloring, resource reuse and retirement.

Optional `StatueFacts` describe quality, subject/caste raw identifiers and event
kind. The bridge decodes native semantic art flags, never viewport texture IDs.
Installed statues combine their quality pedestal and installed subject artwork;
loose statues use the wrapped transport image. Northward figure fragments use a
shader-only foreground lift in straight-down views above same-level walls and
below the next floor. Angled views retain the shared physical pedestal band,
without becoming support for moving items/creatures or rebuilding on camera
movement.
Unknown subjects retain the native generic figure. These are additive table
fields with explicit unknown defaults: the mirror schema version remains
compatible and old recordings do not acquire fabricated contents/depiction facts.
The graphics cache format is bumped because statue creature definitions are now
indexed. Rebuild bridge and viewer to observe the new facts in live sessions.

Native acceptance on DF 53.16 used a verified, owned save clone without saving:
400 container counts/first kinds and 10 installed statue quality/subject records
matched independent native observations. Evidence is in ignored
`build/notes/visual-polish/native-20261013-111306`; the 256-shadow oracle is in
`native-20261013-103947`. These comparisons cover the captured scene, not all
possible content, artifact or depiction variants. Bed bedding has separate
integration and acceptance below. Directional bridge evidence follows.

`fixtures/construction/bridge_rendering.json` records protected native capture
`build/bridge-art-native-20261023-164737`: a synthetic completed granite3x3 bridge,
five directions, each lowered and raised, paused at frame0. All lowered states
draw nine cells. Raised retracting draws none; Left/Right/Up/Down draws only the
west/east/north/south hinge edge. Lowered directional art distinguishes hinge,
far end and NS/WE interior. All51 exported
native textures exactly match installed source art after CLEAR recoloring. The
initial comparison incorrectly let the last duplicate palette key win; retaining
the first occurrence, as DF does, resolves every color and alpha difference.
Protected `build/bridge-art-shapes-native-20261023-165140` adds1x1,1x3,3x1,2x2,
2x4 and4x2 footprints across all directions and both states. All73 exported textures
match exactly. The pure asset resolver now accepts direction/raised inputs and
matches all70 captured layouts using `bridge_render_tiles.txt`; core gate
`build/qa/bridge-direction-resolver-verified` passes. Hinge artwork takes precedence
over far-end artwork on one-tile spans. Raised retracting resolves successfully to
zero tiles, which must not trigger classic fallback. Further state transport,
viewer and movement evidence follows below. The synthetic stage/state
changes establish rendering evidence only, not natural construction or lever
effects. Screenshot inspected, source unchanged, owned DF closed without saving.

Optional `Building.bridge` now transports direction and raised/raising/lowering/
collapsing flags directly from `building_bridgest`. Missing tables remain unknown
in old recordings; validators reject non-bridge contexts and invalid directions.
Bridge shadow equality and model revisions include all five values. World and
selection artwork queries use direction/raised state; no native graphics state
crosses the boundary. Schema/model serialization and revision tests, root core and
construction-material checks pass in `build/qa/bridge-state-transport-fixed`.
Bridge build/install passed. Protected `build/bridge-state-native-20261023-170742`
records57 observations covering all10 direction/raised combinations; the inspector
accepts the recording. The fixture uses diagnostic state edits, a one-tick building
scan period and50 simulation ticks per state (500 total), not lever interactions.
An earlier frame0-only capture published only the initial state and is excluded
from transport acceptance. Source unchanged, owned session closed without saving.
GPU viewer replay `build/bridge-viewer-replay-verified` now checks the rendered
cell coordinates for all10 direction/raised states against native observations.
All match, including zero cells for retracted and restoration of the full deck.
The ten captured images were inspected together for directional artwork. Its
source `build/bridge-state-native-20261023-171146` adds300 initial simulation ticks
to finish terrain streaming before the state cycle;67 bridge observations cover
all10 states. The initial viewer harness looked for building nodes outside their
elevation parent and attempted the first render before terrain had arrived; that
failed run is excluded. Final replay diagnostics contain only the three known
engine signatures. This verifies recorded state updates through GPU rendering,
not real lever effects or screenshot-wide pixel equality. Source save unchanged,
owned DF closed. Construction-stage artwork is covered below.
Construction-stage capture `build/bridge-stage-native-20261023-171446` resolves
that artwork gap: native stages0,1,2 use the same directional RGB as completed
bridges, with alpha `(a+1)/2` rounded down. All138,240 pixels across135 cells match
this rule. The viewer uses white tint and cached ceil-half RGBA artwork for
both planned and in-progress bridges. Alpha rounding happens before mipmap
generation, preserving the native byte values instead of multiplying alpha in
the shader. Core/extension/material checks pass in `build/qa/bridge-stage-render`.
Recorded-stage GPU replay `build/bridge-stage-viewer`, sourced from protected
`build/bridge-stage-record-20261023-171915`, verifies all three model stages, cell
footprints and vertex tint. Planned/completed images were inspected; diagnostics
are known engine issues only. Source unchanged and owned session closed.
Synthetic fixtures must set both construction stage and `flags.exists` consistently:
setting the stage alone left the earlier ten-state recording classified as
in-progress. Its cell-layout evidence remains valid, but it does not establish
completed-building opacity.
Native-trigger capture `build/bridge-movement-20261023-172417` exercises a completed
west-facing granite bridge through DF's `setTriggerState`, the same virtual call
used by DFHack's instant lever action. DF advances the timer naturally: raising
runs from0 to100, then changes raised state on tick101; lowering runs from100 to0,
then changes raised state on tick101. All300 per-tick observations match. Eleven
art samples, including movement ticks50 and100, exactly match the settled artwork
for the current raised bit. No intermediate artwork or timer-based animation is
needed for this case. All four raised/raising/lowering combinations appear in38
recorded observations. The fixture needed a warmup resume at frame1 before the
trigger sequence; source remained unchanged and the owned session closed. This
is native movement and transport evidence for one synthetic completed bridge,
not acceptance of player lever jobs or natural bridge construction.

Protected `build/bridge-material-native-20261024-064810` independently varies
building material with a fixed granite component. All408 textures across160
paused states (four materials, four stages, five directions, raised/lowered)
exactly match installed artwork. Bridges use building material class and color,
including GLASS artwork with DARK_GREEN for green glass. The existing
`Building.material_solid_color` publication now includes Bridge, so built-in
materials do not depend on absent raw material definitions. The resolver uses
that native descriptor when present and retains the old-recording fallback.

`bridge_material_gpu` checks80 planned/completed states against captured RGBA
hashes, white vertex tint and reload reset. Core and GPU pass in
`build/qa/bridge-material-pixels`, with only documented Godot diagnostics; the
rendered scene was inspected. Installed bridge capture
`build/bridge-color-native-20261024-065327` verifies six material descriptor
states including all three glass types. Both owned probes closed without saving
and preserved the source clone. These are rendering and publication tests,
not new natural-construction claims.

`fixtures/construction/roller_rendering.json` records native Roller evidence.
Protected `build/roller-art-native-20261023-190300` covers128single-tile cases:
sixteen underlying track masks, four movement directions and planned/completed
stages with no contained items. All16 distinct textures match installed art.
Completed shape follows track connectivity; bare floor uses the crossing.
Planned art instead follows the movement axis (0/2 NS,1/3 WE), always using the
uncolored stone first frame at half alpha rounded down.
`build/roller-phase-native-20261023-190445` adds216 cases with oak logs, oak
blocks and granite blocks, three coordinate residues and three synthetic machine
positions. Every expected RGBA image matches. Completed logs select wood art;
blocks select stone art, recolored by the first item's actual material using
first18 palette keys and first-match duplicate precedence. If p is the linked
machine position modulo3 (0 without a machine), use y for directions0/2 or x
for1/3. Frame1 applies when that coordinate modulo3 equals p for directions1/2
or2-p for0/3; all other cells use frame2. Native draw RVA0x5922a0 supplies these
rules. The simulation-owned field is `machine.visual_phase` in DFHack, original
name `position`; its timer is original `position_counter`. Renderer/menu scratch
must not be read at runtime. Protected
`build/roller-multitile-native-20261023-190746` verifies216 additional cell images
across1x3/3x1 footprints, all four directions, three first-item types, three
machine positions and both stages. Individual cells have N, NE and EW track
shapes; all match the same per-cell rule exactly. The native screenshot was
inspected. All three paused diagnostics closed owned sessions and preserved the
source save. The bridge now publishes native Roller direction and linked machine
position, with unknown defaults -1 and -129 respectively. Position preserves the
native signed byte (-128..127); no linked machine publishes0. First-contained-item
facts also apply to Rollers, preserving snapshot-local material indexing.
`build/roller-state-native-20261023-191706` verifies55 updates across13 states,
including direction changes, signed positions, first-item order/removal and machine
detachment. The inspector accepts the recording, the source remained unchanged,
and the owned process closed. The machine was synthetic and inactive; its position
was assigned diagnostically. Root build and all19 CTest checks pass in
`build/qa/roller-native-state`; the plugin was rebuilt and installed. Natural
powered-machine lifecycle and viewer acceptance remain pending. The asset
resolver now uses per-cell track masks, first-item material, native direction and
the signed machine-position/coordinate rule above. Its regression covers all16
masks, four directions, three positions, three item-kind states, mixed three-cell
footprints and planned/completed stages, plus unknown/signed boundary inputs.
Root build and all19 CTest checks pass in `build/qa/roller-art-resolver`.
The viewer supplies per-cell track dependencies and first-item material. Planned
Rollers use painted half-alpha art along their native movement axis. Completed
meshes retain frame1 geometry; `machine_surface.gdshader` selects the second row
from native position, direction and absolute cell residue. Reusable256-entry float
texture pages are shared by source and batch materials. Position-only events update
these textures and cache versions; structural changes retain normal invalidation.
Entity resets clear pages/slots, and removal releases the ID's slot. Signed remainder
is explicit because shader modulo semantics differed from native C++ for negative
positions in the first GPU regression.
`build/qa/roller-viewer-integration` passes root/extension/core19 and Pump/Track Stop
GPU regressions. Registered `roller_render_gpu`, backed by `make_roller_fixture`,
passes in `build/qa/roller-render-final`:17 snapshots cover three-cell track masks,
exact atlas columns/base rows/tint, stable mesh identities during phase changes,
independent machines, paused/unknown/signed positions, unrelated/owned terrain
edits, planned stages, material changes, removal/readdition and fixture reload.
`build/roller-native-viewer` replays all13 states from the live recording, checking
shader input values, source rows, batch ownership, unchanged meshes and item-order
images. The full log-state image was inspected. Both GPU workflows contain only
the documented engine diagnostics. Native selection capture
`build/roller-icon-native-20261023-193222` selects completed three-cell Rollers in
all four directions. Each header matches all488 opaque pixels of the installed
`BUILDING_ICON_ROLLERS` tile (column2,row10); the first screenshot was inspected.
The paused diagnostic preserved the source and closed its owned process.
`selection_icon` now returns this fixed icon before its multi-tile rejection,
retaining identity and visibility checks. Exact header RGBA comparisons across
planned/completed states and four directions pass with the existing Roller GPU
regression in `build/qa/roller-header-icon-verified`, with known engine diagnostics
only. Natural powered-machine lifecycle, broader resource-page/disconnect coverage
and minecart operation are not established by these rendering checks.
Two additional protected diagnostics, `build/roller-power-native-20261023-193634`
and `build/roller-power-settled-native-20261023-193746`, connect synthetic completed
Windmill/Gear/Rollers through native `machine_handler::add_to_machine` and toggle
the gear with native `setTriggerState`. DF advances normally; no machine position
or power is assigned. Both remain unpowered (windmill output0, position/timer0),
including after5,000 settling ticks in the second run. Each records360 samples
and1,080 exact native cell images;373/372 published position observations match.
Disengaging the gear splits the Roller machine and lowers its required power
from11 to6. Reengaging does not merge it back in these probes, even after1,000
ticks. These are observations of the synthetic setup, not evidence of a product
bug or of powered animation. Whether the setup omitted native completion
initialization remains unresolved. Both owned sessions closed without saving and
preserved the source; the longer recording passes the inspector. Powered lifecycle
acceptance still requires a working power source and verified native initialization.
Follow-up viewer construction checks in `build/windmill-natural-power-20261023-194237`
and `build/windmill-natural-power-settled-20261023-194359` naturally complete the
Windmill with exact selected logs, yet report0power immediately and after2,000
additional ticks. Their indoor source site had prepared outdoor flags.
`build/windmill-outdoor-power-20261023-194935` instead uses existing reachable
outdoor floor at21,26,170. Native construction finishes at frame10,450 with the
four UI-selected logs48168/48170/48171/48173; frame12,450 still reports0produced
power and `is_working=0`. The completion screenshot was inspected. All three
sessions preserve the source and close; diagnostics are known engine issues only.
The outdoor harness was corrected to select native-offered individual logs across
material groups instead of assuming the indoor fixture's first group contains
exactly four logs. Earlier outdoor runs194559/194808 provide no power acceptance.
This confirms a naturally completed Windmill at this site is unsuitable as the
powered reference, without attributing a bug to DF3D or DF. A flowing-water source
supplies the powered rendering reference below.
`build/roller-water-power-native-20261023-195434` places synthetic completed
Water Wheel/Gear/Rollers above existing permanent river flow at25,137,169, prepares
only adjacent upper-level support, and uses native machine attachment. River water,
`gives_power`, machine power and positions are not assigned. Natural simulation
supplies100power against21required and advances positions0..5 with timers0..19.
Disengaging the gear leaves the Roller on a separate unpowered machine at position0.
All1,080 sampled native cell images and379 published position observations match;
the inspector accepts the recording. The owned session closed and source stayed
unchanged. `build/roller-water-viewer` replays the six powered positions and stopped
state: images repeat modulo3, the stopped image matches position0, and every state
retains one mesh identity. The rendered image was inspected; diagnostics are known
engine issues only. Initial harness attempts selected targets out of chronological
order and then aimed at level170 while first-load initialization selected165; the
corrected run uses ordered targets and sets the level after the first snapshot.
This establishes powered/stopped animation from natural DF machine updates, not
natural construction of this machinery or minecart motion. Gear reengagement in
the synthetic setup did not reconnect the separated Roller; no runtime power or
connection logic was changed or inferred from that observation.



Protected `build/furniture-nine-completion-main-20261023-210355` verifies natural
construction of Chair, Box, Cabinet, Slab, Statue, GrateWall, Floodgate,
Weaponrack and Armorstand through actual menu/map/search/expanded exact-item
pointer controls and public Play. Existing reachable floors were unchanged;
only input items were created. All nine finished by frame1425 with no jobs and
retained their exact selected granite items48520..48528. Completed screenshots
were inspected together; exhaustive artwork parity is a separate requirement.
The owned session closed without saving and preserved the source; diagnostics
were the three known Godot issues only. Evidence is retained in
`furniture_material_copy.json.nine_family_natural_completion`.

Protected `build/furniture-tools-completion-main-20261023-210622` applies the
same real pointer/exact-item/public-Play flow to DisplayFurniture, OfferingPlace,
Hive, NestBox, GrateFloor, WindowGlass and TractionBench. Tool subtypes come from
native tool-use definitions; sites are existing reachable floors. All seven
completed by frame725 with no jobs and exact selected items48520..48526. The
window uses green glass; the other inputs use granite. Completed screenshots
were inspected together. Source preservation and owned-session cleanup passed,
with only the three known Godot diagnostics. This establishes installation,
not subsequent furniture operation or exhaustive artwork parity. Evidence is in
`furniture_material_copy.json.tool_opening_natural_completion`.

Protected `build/construction-recipes-completion-main-20261023-211339` verifies
ArcheryTarget, BarsFloor, BarsVertical, Chain, GearAssembly, Support, CageTrap,
Lever and StoneFallTrap through actual menu/map/expanded exact-item pointer
controls and public Play. All nine naturally completed by frame4000, with no
jobs and their exact permanent inputs48520..48528. Bars and chain use iron;
other inputs use granite. Completed screenshots were inspected together.
The first210834 run is excluded: DF suspended CageTrap construction on the
fixture citizen/input tile, while eight others completed. Swapping that site
with the archery-target site let the full batch finish; no job stages or
suspensions were forced. Both owned sessions closed and preserved the source.
Successful-run diagnostics contain only the three known Godot issues. Evidence
is in `material_candidates.json.remaining_single_recipe_completion`; this is
installation evidence, not powered operation, trap triggering or lever linking.

Protected `build/large-recipes-completion-main-20261023-212006` verifies actual
menu/map/expanded exact-item selection and public Play for TradeDepot, Ballista
and Catapult. All three naturally reached stage3/3 with no jobs by frame5400,
retaining exactly three selected granite boulders or cherry siege parts each.
Sites are existing reachable floors outside the fixture citizen/input area.
Completed screenshots were inspected together; only the three known Godot
diagnostics occurred. The first211656 run is excluded: DF suspended Ballista
construction over the source-item tile, while Depot and Catapult completed.
The observer ended that run as failed after confirming the native suspension.
Both sessions closed without saving and preserved the source. Evidence in
`material_candidates.json.large_recipe_natural_completion` proves construction,
not siege firing, caravan access or trade operations.

Protected `build/construction-ramp-completion-20261023-212337` and
`build/construction-fortification-completion-20261023-212532` verify plain Ramp
and Fortification through actual launcher/category/leaf, map corner clicks and
individual material selection. Native jobs reserved the selected granite block
48520; each completed naturally at frame3100 as ConstructedRamp or
ConstructedFortification with no remaining job. The existing natural floor was
unchanged by setup. Fortification paused at frame1 with an unsuspended job; the
diagnostic resumed that same owned session without modifying construction state.
Completed views were inspected. Both sessions closed without saving and preserved
the source; only the three known Godot diagnostics occurred. Evidence is in
`area_refusals.json.native_terrain_service.ramp_fortification_completion`.
These are single-tile construction effects, not exhaustive rectangle coverage.

Protected `build/well-natural-completion-main-20261023-222931` verifies Well
through actual menu/map and all four expanded individual material stages. It
naturally completed at frame2250, stage1/1 with no jobs, retaining exactly the
selected granite block/mechanism and iron bucket/chain48520..48523. Setup opens
one dry floor tile with adjacent floors unchanged; this is installation evidence,
not water availability or hauling.
`build/waterwheel-natural-completion-main-20261023-223326` verifies the native NS
default, actual WE orientation button, map target and three exact log selections.
The wheel naturally completed at frame1325, stage1/1 with no jobs, retaining
cherry logs48520..48522. Setup prepares a dry three-cell opening and a planned
native gear; neither machinery nor construction stages are force-completed.
The first223112 attempt left NS orientation against a WE opening and is excluded.
Both accepted completed views were inspected. Owned sessions closed, source saves
were preserved and diagnostics were only the three known Godot issues. This does
not claim flowing-water power. Evidence is retained in
`material_candidates.json.well_waterwheel_natural_completion`.

Protected `build/waterwheel-animation-native-20261023-224208` establishes the
WaterWheel animation rule: native completed NS wheels select frame1/2 by
even/odd machine visual phase.
Across360 natural tick observations, all1080 cell images match installed artwork
exactly (six exported textures). The phase spans0..5;343 observations produce
100 power and17 produce zero, with both output states retaining phase-selected
art. Output alone is therefore not the frame selector. The fixture uses synthetic
completed machinery over unchanged flowing river water, not natural construction.
The screenshot was inspected; source preservation and owned cleanup passed.
`machinery_directions.json.waterwheel_animation_native` retains the evidence.
Protected `build/waterwheel-states-native-20261023-224729` extends this to312
paused controlled states: both orientations, signed phases-128,-3..6,127 and
absent machine, planned/complete, output flag on/off, and no item/oak/iron first
item. All1560 footprint and signpost-top-row cells match70 installed textures
exactly. Completed frame2 requires signed remainder `phase % 2 == 1`; negative
odd values use frame1. Absent machine uses frame1. Planned art always uses painted
frame1 at half opacity; completed art uses the contained item's actual material
palette or painted artwork when empty. Output flags do not change this rule.
The first224546 capture omitted the signpost layer; its42 footprint textures
matched, but only the224729 run establishes the entire wheel. Both sessions
closed at frame0 and preserved the source; the final screenshot was inspected.
The bridge exports `waterwheel_machine_position` (signed byte, absent machine0,
unknown-129) and the first construction item material. The shared machinery
phase texture updates wheel and roller shaders without rebuilding resident
geometry. Wheels retain frame1 base geometry, painted planned/empty artwork,
and the first item palette when completed. `waterwheel_render_gpu` covers both
orientations, top-row geometry, signed phases, planned stability, material
changes, removal, independent machines and reload; the existing roller/page
regressions also pass. `build/qa/waterwheel-rendering` passed core19 and these
three GPU checks (only documented Godot diagnostics). Visual inspection exposed
an inherited roller shader defect: pixel cell dimensions were used as UV offsets.
`machine_surface.gdshader` now normalizes them by texture dimensions for both
families. `build/qa/machinery-frame-native-cells` passes wheel, roller and page
GPU checks, including pixel comparisons against static meshes selecting native
atlas cells; both wheel frame captures were inspected. Only known Godot
diagnostics remain. Protected `build/waterwheel-transport-native-20261023-230326`
compares64 observations across15 phase/item states with DF, including signed
limits, absent machinery, reordered first items and removal. All match; the source
was preserved and owned DF closed. Multiple-item artwork precedence is not
independently covered by these single-item diagnostic cases.

Placed-slab rendering consumes the first contained item's engraving and material.
Protected `build/slab-states-native-20261024-002133` verifies 168 paused diagnostic
states (all engraving values -1..26, planned/complete, empty/granite/iron first
item). All 48 native textures match installed artwork. Empty slabs and unused
intents 1..5 use raw blank art; planned slabs use raw blank art with half alpha
rounded upward before filtering. Semantic captures and matches are retained in
`slab_rendering.json.gz`. The material picker publishes engraving in candidate
appearance and revision identity. Individual icons use that engraving; generic
group icons use raw memorial art, as established by protected native picker
`build/slab-picker-native-20261024-003914`.

`slab_render_gpu` checks all engraving artwork, material changes, planned alpha,
UVs, removal and reload. Core, adapter, material and icon checks passed in
`build/qa/slab-picker-rendering`; GPU diagnostics were the known three signatures.
Protected transport `build/slab-transport-native-20261024-005222` matched 151
observations across 33 engraving/first-item states. Protected viewer workflow
`build/slab-picker-completion-main-20261024-005607` selected exact blank, memorial
and secret slab items through the material picker and observed natural completion
with those same items and engravings. Picker and completed screenshots were
inspected. Both sessions preserved their source and closed owned DF; the viewer
had only the known engine diagnostics. These checks do not establish every other
construction family's visual or lifecycle acceptance.

Well rendering uses the additive `well_chain_is_metal` fact (-1 unknown,
0 no metal chain,1 metal chain present), derived from contained CHAIN items and
native material flags. Any metal chain selects the chain artwork regardless of
component order. Model identity includes the fact so insertion/removal updates
appearance. Planned Wells use raw `BLD_WELL` with rounded-up half alpha before
mipmaps; completed Wells use raw `BLD_WELL_WITH_ROPE` or `BLD_WELL_WITH_CHAIN`.
Unknown old recordings retain `BLD_WELL`. No graphics/menu state is read at runtime.
`bars_rendering.json.well` records the reference and acceptance. Core/schema/model
checks passed in `build/qa/well-rendering`; GPU checks in `build/qa/well-native-art`
match native planned/complete textures, rope/chain changes, removal and reload.
The completed screenshot was inspected. Protected live run
`build/well-transport-native-20261024-025257` matches25 observations across six
component states and matches native artwork in all six, including rope before
metal. Source stayed unchanged and the owned session closed. An earlier probe
incorrectly placed the Well on solid floor; a second exposed the first-chain
assumption, which was corrected to any metal chain. These checks cover idle
Wells; they do not establish lowering-bucket animation or new natural-build effects.

Gem windows retain the building material palette and installed `ITEM_WINDOW_GEM`
artwork for valid gem materials. Planned alpha is truncated to half before mipmaps.
`bars_rendering.json.gem_window` records protected natural completion in
`build/gem-window-natural-art-20261024-021733` (three exact rubies, frame1550,
stage1/1, no jobs), native comparisons of24 shape choices over planned/complete
states in `build/gem-window-ruby-shapes-native-20261024-022336`, and empty/single/
three/mixed/reordered-color components in `build/valid-component-art-native-20261024-022441`.
All use the same building material palette. Earlier synthetic granite-material
windows are not valid gem-window recipes and do not establish normal rendering.
`build/qa/gem-window-rendering` passes exact native planned/completed texture
comparisons with known Godot diagnostics only; the planned screenshot was inspected.
No cut-shape field or first-item color override is needed for this building.

Planned Door, Hatch, GrateWall, GrateFloor and Floodgate artwork uses native raw
palette and rounded-up half alpha before filtering. Door/floodgate choose their
material class; native Hatch uses the abstract glass hatch, and grates use the
abstract metal wall/floor art. This replaces the generic40% preview tint for
these families. `bars_rendering.json.planned_openings` records protected
`build/opening-natural-art-20261024-042329`: six exact registered components
naturally completed in1350 frames, including a green-glass window. The capture
uses diagnostic job submission rather than public UI actions. Source remained
unchanged and owned DF closed. Five granite planned-art hashes pass in
`build/qa/opening-planned-pixels` with known engine diagnostics; core checks pass
in `build/qa/opening-planned-art`. The first GPU attempt used the wrong shader
texture parameter in its test and is excluded. Planned screenshot inspected.
Natural GrateWall completion matches wall art; the earlier unregistered-item
synthetic result showing floor art is not a runtime rule.

Completed Door/Hatch artwork publishes the first contained item's identity,
actual material and native solid-color token through optional
`construction_item_id` and `construction_item_solid_color` fields plus the
existing item material facts. Identity/color changes invalidate model artwork;
absent older facts retain the previous base-art fallback. The renderer selects
the installed variant using the first SplitMix64(item ID) upper32 bits masked
with3, recolors base and overlay separately, then uses the engine-independent
integer alpha compositor before filtering. Closed Hatch base1 is independent
of tested item qualities0..6; no quality field is introduced. Built-in glass
material tokens resolve to the glass art class.
`bars_rendering.json.completed_opening_native_reference` records68 exact native
comparisons from `build/opening-variants-native-20261024-043112` and
`build/opening-quality-native-20261024-043220`. Protected transport capture
`build/opening-transport-native-20261024-044433` adds362 matching observations
across64 component replacements in granite, iron, green glass and oak. All63
closed native frames match the compositor; three naturally opened doors are
excluded from the closed-art comparison. This does not verify open-door or
wear/damage rendering. Source manifests were unchanged and owned sessions closed.
Core/schema/model checks pass in `build/qa/completed-opening-variants`;
`build/qa/completed-opening-materials` passes99 native pixel hashes, repeated
component changes and reload reset, with documented Godot diagnostics only.
The completed scene was inspected. These diagnostic component replacements
supplement the earlier natural completion reference; they do not claim public
UI placement for every variant.

Chair, Table, Box and Cabinet use the same owned first-component identity,
actual material and solid-color facts. Native captures
`build/furniture-variants-native-20261024-045021` and
`build/furniture-planned-native-20261024-045228` establish132 completed comparisons
and16 planned material states over granite, iron, green glass and oak. The four
original buildings completed naturally at1700 frames; subsequent registered
component replacements are diagnostic. For the supported install, chairs and
tables use the first leg overlay, boxes use the ID-selected four-way overlay,
and cabinet variant tiles are empty. Tested quality values0..6 keep the same
base. These checks do not establish generated-artifact or improvement rendering.
Planned art uses the generic family sprite, uncolored with rounded-up half alpha,
independent of the selected material. Completed layers use the integer compositor.
Protected `build/furniture-transport-native-20261024-050535` verifies725 published
observations across128 replacements and132 exact native texture comparisons;
the source stayed unchanged and owned DF closed. Core checks pass in
`build/qa/furniture-native-variants`; its first GPU attempt used the wrong planned
shader parameter and is excluded. Corrected `build/qa/furniture-native-pixels`
passes all132 furniture references alongside99 opening references, planned art
and reload cleanup, with documented Godot diagnostics only. Scene inspected.
`bars_rendering.json` retains the native hashes and verification scope.

Coffin, Cage, Chain and AnimalTrap planned artwork uses the installed raw palette
with rounded-up half alpha before filtering. Coffins select the material-class
sprite; restraints select metal or rope; cages and animal traps use the fixed
metal sprite even for wooden components. Protected native capture
`build/ordinary-art-native-20261024-051057` includes six natural completions at
frame1400,38 diagnostic registered component replacements and19 diagnostic
planned-stage material comparisons. All35 distinct textures match installed
artwork and palettes exactly. Completed behavior is specified below.
`bars_rendering.json.planned_ordinary_furniture` records the four initial planned
references. Core passes in `build/qa/ordinary-planned-native`; its GPU attempt
used the wrong restraint texture parameter and is excluded. Corrected
`build/qa/ordinary-planned-pixels` passes the new planned references,231 existing
completed references and reload checks with documented Godot diagnostics only.
The planned scene was inspected. Native source saves stayed unchanged and the
owned DF process closed.

Armor stand and weapon rack previews use material-colored empty artwork with
truncated half alpha before filtering. Glass selects the stone member, as native
DF does, rather than the generic material-class fallback. The bridge supplies
its existing owned `Building.material_solid_color` descriptor for these two
families as well as glass windows; no schema fields were added. The resolver uses this token in both planned and completed states, including
for built-in glass.
`bars_rendering.json.planned_equipment_furniture` retains eight native hashes
from the paused material comparisons in `ordinary-art-native-20261024-051057`.
Core and GPU `build/qa/equipment-planned-pixels` pass the eight new cases,
existing references and reload reset, with documented Godot diagnostics only;
the rendered scene was inspected. The earlier `equipment-planned-native` GPU
run identified the incorrect glass sprite fallback and is excluded.
Installed bridge capture `build/equipment-transport-native-20261024-053109`
verifies39 published material/color observations across eight completed-state
material replacements after two natural completions. Color publication is
stage-independent; this live check complements the paused preview reference.
The source save stayed unchanged and owned DF closed. Earlier diagnostic runs
052801 and052908 are excluded: advancing a forced incomplete building without
a construction job invalidated that test setup;052908 exited DF without a native
result. The successful probe does not advance those forced preview states.

Buildings publish the exact native `getBuildStage()` value through the additive
`Building.construction_stage` field, separately from Planned/InProgress/Complete.
The owned model invalidates changes between intermediate stages; the rendering
query receives the scalar without native menu or renderer state. Older recordings
retain -1 (unknown); do not infer an exact stage from coarse InProgress.
`fixtures/construction/layout_stages.json` retains the live transport regression:
28 observations across six synthetic Carpenter transitions, including repeated
1-to-2 transitions, match native values. The protected source was unchanged and
the owned process closed. Core tests and the existing building GPU regression
pass (GPU with the three documented engine diagnostics).

Grid layouts now select an available exact stage for both base and overlay,
retaining the coarse fallback only when the exact stage is unknown or absent
from the installed layout. Construction-stage art supplies its own opacity;
the viewer no longer applies the generic ghost/dim multiplier to that art.
Workshop, Furnace and TradeDepot publish their first permanent construction
component, falling back to entry zero if no permanent entry exists. Its ID,
actual material and native solid color use the existing construction-item
fields; the model owns these values and invalidates changes. Layout bases use
that component color at every stage, or raw colors when no component is present.
The separate native descriptor handles builtin glass colors; building material
is not a substitute. Foreground overlays retain their original palette.

Layout overlays use native split /256 channel truncation with a copied base.
Transparent destinations seed alpha from the overlay before blending, both
inside the footprint and on north overhangs. Layout and furniture composites
have separate cache keys; the furniture blend is unchanged. Captures in `layout_stages.json` compare
144 stage/material/order cases plus independent TEMP-only/two-PERM cases and
114 cells from eight existing completed buildings. Native pixels stayed identical
after independently replacing building material. Two protected transport runs
each match44 observations, including real temporary contents moved before the
permanent entry in two workshops. Source saves stayed unchanged and owned
sessions closed; these are rendering/transport checks, not new construction effects.

`layout_stage_gpu` compares all four component-free Carpenter stages and48
component/material/stage cases across Carpenter, Smelter and TradeDepot,
including overhangs, white tint, repeated stages and reload restoration. Core
and bridge-material regressions also pass; GPU diagnostics are the three known
engine signatures. The synthetic screenshot overlaps installations and is not
main-scene acceptance. The broader family and siege comparisons below extend
this rendering coverage.

Quern column artwork uses the selected construction component's native color,
with raw colors when no component is present. Its planned page cache applies
ceil(source alpha/2) before mipmaps and retains a white vertex multiplier;
completed pages retain full alpha. `quern_rendering.json` records32 native
component-count/stage cases and24 component-order cases. `quern_render_gpu`
checks ten component/material/stage pixel cases, mesh refresh and reload,
alongside the existing layout regression. The standalone planned image was
inspected; GPU checks pass with the documented engine diagnostics. These are
rendering checks, not new natural construction or Quern job effects.

Siege rendering evidence is retained in `siege_rendering.json.gz`:828 paused
synthetic cases, including636 with explicit facing/timer facts. Captured textures
match installed artwork; explicit-state cases also match artwork, palette and
alpha rules. Catapult/Ballista construction uses raw CONST_0 without contents,
otherwise CONST_1/2/3 at exact stages0/1/2. Completed color comes from entry zero
regardless of TEMP/PERM role. All eight facings select directional artwork.
Firing artwork uses timer1..5 for Catapult/Ballista and1..2 for Bolt Thrower;
exactly three Ballista contents also select firing art at every tested timer.
Unfinished Bolt Thrower uses directional READY artwork, raw color and floor-half
alpha. The older192 cases omit orientation/timer facts; these stay unknown.
No firing or ammunition effects are claimed. The bridge now publishes optional
`siege_facing` and `siege_fire_timer` fields, with unknown defaults for older
recordings, and siege contents count/component facts from entry zero. The owned
model copies these fields and invalidates appearance changes. The resolver uses
the captured direction, timer, stage and color rules, including Bolt Thrower's
own artwork and planned floor-half alpha. Schema/model/selector tests and the
bridge build pass. `siege_render_gpu` compares all828 uploaded RGBA references,
white vertex colors and three fresh-source reload targets; it passes with the
three documented Godot diagnostics. Fixture replay is forward-only, so an earlier
target requires reopening the source. The final Bolt Thrower image was inspected.
Protected `siege-transport-native-20261024-093005` matches71 observations across66
native states, including TEMP oak before PERM iron. Normal entity-full requests
publish the state while DF stays paused at frame zero. The source save was
unchanged and the owned session closed. These checks establish rendering and
semantic transport; natural firing and ammunition effects remain outside them.

`trap_rendering.json.gz` retains546 paused native cases for Lever, Pressure
Plate, Cage Trap and Stone-Fall Trap, including state, timers, all64 plate flag
combinations, contents count and mechanism ordering. The bridge publishes
`trap_state`, `trap_ready_timeout`, `trap_fill_timer` and `trap_trigger_flags`
as owned facts for Trap subtypes0..3. Unknown defaults lie outside the native
signed-byte/signed-short ranges; older recordings remain unknown. Trigger flags
retain the six native bits (units1, water2, magma4, citizens8, resets16, track32).
Contained entry count and component identity/material/solid-color facts also
cover these four subtypes. Their component is the first TRAPPARTS item regardless
of TEMP/PERM role or preceding non-mechanism entries. No mechanism means absent
component facts. Model changes include each field independently. Native menu and
renderer scratch are not runtime inputs. Core checks and the bridge build pass;
`trap_render_gpu` verifies all546 native pixel references, white vertices,
empty-art visibility and fresh-source reloads. It passes with only the three
documented Godot diagnostics. Completed traps without a mechanism intentionally
draw no art. Levers use pulled art when state is positive; pressure plates use
pressed art when state or either timer is positive, with trigger artwork priority
magma, water, minecart, then generic. Cage/Stone-Fall traps use loaded art with
at least two contents and nonpositive state. Their north top layer retains raw
colors independently of the mechanism-colored base. All four planned trap types
retain raw colors and ceil-half source alpha. This is per-layer palette metadata,
not a grid-layout classification. Older recordings retain unknown-fact fallbacks.
These captures establish artwork inputs, not activation or natural construction effects.
Protected `trap-transport-native-20261024-101431` matches70 observations across59
native states, including a boulder before the selected iron mechanism. It also
checks empty/no-mechanism contents and independent timer/flag changes through
normal entity-full publication. DF remained paused at frame zero; the source
save was unchanged and the owned process closed. This verifies semantic
transport; the separate GPU gate establishes the rendering coverage above.

`weapon_rendering.json.gz` retains578 paused native Weapon/Trap4 cases, including
component types/order, roles, count, state, retraction and timer boundaries.
The bridge publishes `weapon_count` (WEAPON/TRAPCOMP entries only),
`weapon_retracted` (Weapon only) and `construction_weapon_raw` (first eligible
item definition regardless of role). Component ID/material/solid-color facts
and total contained-entry count cover Weapon and Trap4; `trap_state` also covers
Trap4. Other pressure-plate facts remain restricted to Trap0..3. Unknown defaults
preserve older recordings. Each new fact participates in owned-model changes.
Core checks and bridge build pass. Protected
`weapon-transport-native-20261024-105340` matches130 observations across44 distinct
states through ordinary entity-full publication at paused frame zero. The source
save was unchanged and the owned session closed. These are semantic and artwork
references, not activation or natural construction effects. WeaponTrap rendering
now uses the first weapon definition's WEAPON_TRAP variant and component color
when at least two total contents are present and native state is nonpositive;
otherwise it retains raw empty-trap art. Planned art keeps raw colors with
ceil-half alpha. `weapon_trap_render_gpu` passes163 native references and reloads
with only the three documented Godot diagnostics. Upright weapons use owned
count/retraction/component facts: retracted art retains its raw palette; raised
upper and lower item-definition variants use the component color. Planned and
empty upright buildings use RETRACTED_10, with ceil-half alpha while planned.
`upright_weapon_render_gpu` verifies417 supported Spear/spike references, white
vertices and source reloads0/416/1; `build/qa/upright-weapon-approved-verified`
passes core and GPU checks with only documented Godot diagnostics. The ten-spike
render was inspected. Unsupported axe/short-sword ordering probes remain diagnostic
only; no new bridge contract or gameplay behavior was needed.

The supported native trap-component graphics decoder at RVA0xd007b0 masks the
shifted artwork selector with0x2f at RVA0xd00970, dropping bit4. For five-to-ten
raised spikes this selects an inventory icon, weapon-trap artwork or upper rows
instead of the declared lower rows. A fresh session with different item IDs and
count order reproduces all12 comparisons exactly. Raw definition texture
references are correct. The maintainer approved the declared lower artwork on
2026-10-24, changing appearance only. Corrected lower-image hashes are explicitly
separate from the observed native hashes in the fixture. The ordinary-weapon
decoder at RVA0xcffa00 uses0x1f instead. All44 iron/oak Spear count/retraction
captures match the declared artwork. Diagnostic native graphics data is evidence
only and is not read by the runtime bridge.

`farm_road_rendering.json.gz` retains 300 native stage references: 108 material
variations on 3x3 rectangles and 192 cases spanning six additional dimensions,
full rectangles and allocated native extent masks with a center or corner
excluded. Stage zero uses raw ceil-half artwork. Stages one, two and three draw
completed cells at local spacing four, two and one respectively; holes do not
shift this pattern. Farms retain faint unfinished cells while roads leave them
empty. Both native road classes select BLD_PAVED_ROAD. Independent building and
component materials do not change the four native texture hashes.

The resolver supplies per-tile half-alpha metadata to both mesh and footprint
resolution, with white vertices and raw palette. An entirely empty intermediate
road retains a successful resolution to suppress fallback glyphs. Farm/road
component facts are not published because the artwork does not consume them.
`farm_road_render_gpu` checks every cell's uploaded RGBA and position, native
empty visibility and fresh-source reloads. Core checks pass; the GPU run
`build/qa/farm-road-native-verified` passes with only the three documented Godot
diagnostics. The initial probe's attempted-hole duplicates are excluded; real
mask coverage comes from the separate shape capture. No cultivation, traffic or
natural construction effects are established by these paused references.

`layout_families_rendering.json.gz` adds560 native stage/material cases across
the remaining23 workshop and6 furnace routes. `layout_families_render_gpu`
compares their uploaded RGBA, white vertices and fresh-source reloads. This
identified and corrected transparent-base overlay alpha inside seven workshop
families, plus planned Millstone/Screw Press alpha and Millstone component color.
Quern, Millstone and Screw Press use ceil-half source alpha for their planned
artwork; this is resolver metadata used consistently for meshes, depth and
selection. Their completed artwork retains full alpha. A separate48-case native
probe confirms Millstone/Screw Press prefer the first PERM component, including
TEMP entries before it. Both native sessions preserved the source save and
closed their owned DF process. Core, the560-case GPU comparison and the earlier
layout/Quern regressions pass; GPU runs retain only the documented diagnostics.
These are rendering checks, not new natural construction or workshop-job effects.

Archery targets retain their painted palette at every stage. Their building
material selects stone, wood or metal artwork; native glass targets use metal
artwork. Planned targets use ceil-half source alpha through the raw-furniture
page cache and white vertices. `archery_target_rendering.json` records eight
pixel cases from18 native comparisons that varied component and building
materials independently. Core and `archery_target_gpu` pass, including planned
oak reload; GPU diagnostics are the three known signatures. The planned image
was inspected. No bridge/schema change was needed. The broader126-case native
capture is retained in `simple_construction_rendering.json.gz`; it establishes
initial trap/upright references but does not verify their pending contents/state
rendering. The source save stayed unchanged and the owned native process closed.

Tool-backed construction publishes the selected tool raw ID from the construction
job while planned and the first contained tool when complete. The additive
`Building.construction_tool_raw` field is bounded to128 bytes and restricted to
Bookcase, DisplayFurniture, OfferingPlace, Hive and NestBox. The owned model
copies it and invalidates changes; old recordings retain the family fallback.
This distinguishes display cases from pedestals without reading native menus.

Completed Bookcase, DisplayFurniture, OfferingPlace and NestBox use the actual
component material/color. Hive keeps the raw HIVE_BLD palette. TractionBench
uses building material and its raw palette: wood selects WOODEN, stone STONE,
and glass the METAL fallback. Supported CHAIN and ROPE definitions alias the
same cells, so no extra chain discriminator is needed for installed artwork.
Planned beds use the generic ITEM_BED; completed beds use component material
and published bedding facts. Native item/material getters select STONE frames
for glass beds; the shared bed compositor follows that selection. Planned tool
furniture uses raw artwork with ceil-half alpha and a white ghost multiplier.

Protected captures `build/tool-furniture-art-native-20261024-060022` and
`build/tool-furniture-source-native-20261024-060329` establish planned art and
independently distinguish building/component material sources. Forced planned
tool states without jobs are excluded from reference acceptance. Protected
`build/traction-improvement-native-20261024-060731` and native draw inspection
confirm the supported traction artwork aliases. All owned processes closed
without saving and preserved the source clones.

Installed bridge capture `build/tool-state-transport-native-20261024-062138`
verifies328 exact observations across63 states, including suspended natural
jobs, natural completions, registered component replacements and building-only
material changes. It supplies seven completed-bed references with native
bedding facts. The fixture retains62 tool-furniture references and those seven
bed references as hashes only. `build/qa/tool-furniture-bed-glass` passes core,
all69 GPU references and reload reset, with only documented Godot diagnostics.
The rendered scene was inspected. Native exported textures remain ignored.

Completed ordinary furniture uses native data sources appropriate to each
family. Coffin, Cage and AnimalTrap use the first contained component's actual
material and solid descriptor token. Their existing component identity/color
contract is now supported for these three families. Armorstand and Weaponrack
use the building material and its native color in both stages; glass uses the
stone member. Completed animal traps use the metal member even for wood.

The additive `Building.contained_item_count` field is an owned signed count of
DF's building entries for Coffin, Armorstand, Weaponrack, SiegeEngine and Trap
subtypes0..3, including TEMP and
PERM roles. Unknown is-1; negative values below-1 and other building contexts are
rejected. It participates in model change detection and reset. A coffin with
one entry uses `_UNUSED`; a second entry selects the generic used artwork.
Equipment furniture with more than one entry uses `_FULL`, otherwise `_EMPTY`.
Component-internal contents are not included. Old recordings retain their
existing unknown-fact fallback. No native rendering or menu scratch is read by
this runtime publication.

Protected `build/ordinary-material-source-native-20261024-053520` independently
changes building and component materials after six natural completions; all17
exported textures match installed artwork exactly. Protected
`build/ordinary-contents-native-20261024-053340` adds a registered boulder in
TEMP and PERM roles and then inside the component, with removals between cases;
all15 exported textures match. These tests establish artwork discriminators,
not normal burial, equipment-assignment or captured-creature gameplay.
`bars_rendering.json.completed_ordinary_native_reference` retains41 distinct
native material/contents references with their source runs and labels.

Core and the initial32 references pass in `build/qa/ordinary-completed-native`.
Installed bridge capture `build/ordinary-state-transport-native-20261024-055345`
verifies380 exact published observations across75 states: component material,
identity and color for three families, building color for equipment, and count
changes and removals for all three count-bearing families. Six buildings first
complete naturally; later registered replacements and TEMP/PERM contents
changes advance50 ticks per state without forcing construction stages.
The source save stayed unchanged and owned DF closed. Nine additional distinct
full-material references from that run extend the GPU checks to41. All pass in
`build/qa/ordinary-full-materials`, alongside the existing equipment/chain cases
and reload reset, with documented Godot diagnostics only. Scenes inspected.

Restraints select metal/rope artwork from the building material and retain its
painted palette. `build/chain-material-source-native-20261024-053630` separately
changes building and component materials between iron and cotton after natural
completion; all three exported textures match. Completed recoloring is removed.
Six native states are retained in `bars_rendering.json.completed_chain_native_reference`.
All three owned probes closed without saving and preserved their source saves.
Core passes in `build/qa/chain-native-palette`; its combined GPU run reached the
120-second limit after the growing fixture reached251 snapshots, so is excluded.
The eight equipment previews and six restraint references now run in
`equipment_furniture_gpu`, which reuses the source-texture assertion helpers and
checks reload reset. The original bars/opening/furniture cases remain in
`bars_render_gpu`. Both pass in `build/qa/equipment-furniture-split`, with known
Godot diagnostics only. The focused rendered scene was inspected. Future
completed ordinary-furniture references belong in the focused check.

Glass windows use the optional semantic `Building.material_solid_color` descriptor
published from DF's building material. The bridge supplies it for glass
windows and equipment furniture, including built-in glass materials absent from raw-file material definitions.
The string is bounded to128 bytes, participates in entity/model change detection,
and is copied into owned model storage. Older recordings retain the existing raw
material fallback. Planned window alpha is truncated to half before mipmap generation.
`bars_rendering.json.glass_window` records24 paused opening-art cases in
`build/opening-art-native-20261024-040050`; matching glass building/component
materials establish green/crystal planned and completed artwork. Protected
`build/glass-color-native-20261024-041625` verifies17 published observations over
green/clear/crystal material changes against native descriptor tokens. This is
transport evidence, not natural construction. The owned session closed and source
manifest was unchanged. `build/qa/glass-native-color-core-fixed` passes core/consumer
checks; `build/qa/glass-window-native-color` passes green-glass native pixel hashes
for planned/complete/reload with known Godot diagnostics only. Preview inspected.
The initial alpha-only test correctly failed because built-in color was missing;
its results are excluded. Door/hatch/grate synthetic findings need separate state
review and are not adopted as runtime rules by this glass-window change.

Floor bars and supports publish their first contained construction item's actual
material through the existing optional item facts. Planned artwork uses building
material with truncated half alpha before mipmaps; completed artwork uses the
first item material, or the original palette when no item is present. Support
shape still follows building material class. `bars_rendering.json.floor_and_support`
records native capture `build/simple-building-art-native-20261024-020638` and
focused GPU/core checks in `build/qa/floor-bars-support-rendering`. The shared
fixture checks exact native RGBA for completed iron, planned granite and empty
states, including reload. The completed screenshot was inspected. Protected
`build/floor-support-transport-native-20261024-021409` matches 50 observations
across12 item insertion/order/removal states; source remained unchanged and the
owned session closed. This synthetic transport check does not replace the
separate natural-construction effect evidence.

Vertical-bar rendering composes the native faces and northward spill from the
DF-supplied adjacency mask. Protected `build/bars-states-native-20261024-002223` checks64
paused states over16 cardinal wall masks, planned/complete and empty/iron first
item, with granite building material. All33 textures match ordered composites
of installed W/E/N-back/S layers and the separate N-upper spill. Planned art uses
building material and truncated half alpha; completed empty art is raw, while a
first bar item supplies its actual material. `bars_rendering.json.gz` retains
these captures and matches. Protected neighbor probe
`build/bars-neighbors-native-20261024-005752` adds 252 paused cases across four
sides, terrain-shape representatives, six fortification types, occupancy values
and seven synthetic neighboring building types/stages/closed states. All seven
textures match installed composites. With controlled Dynamic occupancy, closed
Doors and wall grates connect, and vertical bars connect regardless of closed
state; the tested floodgates, floor grates/bars and chairs do not. This does not
establish normal occupancy transitions or exhaustive terrain/boundary behavior.
`verticalBarsConnections` in `construction_site_native.cpp` supplies a semantic
N/S/W/E mask using fingerprinted native open-terrain and closed Door/wall-grate/
vertical-bar helpers, plus the native inline occupancy and bar-list checks.
It does not call the draw routine or access menu/graphics scratch. The diagnostic
`df3d bars-connections-read x y z` returns this mask, or -1 on unsupported input.
Protected `build/bars-helper-native-20261024-010250` matched all 252 masks against
the independent native wall-mask artwork captures. This checks the base cell,
not upper spill or mirror publication. An attempted exhaustive synthetic tile
render (`build/bars-terrain-native-20261024-005935`) exited before results and is
excluded from acceptance; the protected source was unchanged.
The additive `vertical_bars_connections` field uses -1 for unknown old recordings
and 0..15 for the native mask. Model revisions include adjacency; changed masks
rebuild the affected artwork. Planned opacity is applied after composition and
before mipmaps. Core checks passed in `build/qa/bars-semantic-contract` and
`build/qa/bars-rendering`; `build/qa/bars-native-pixels` passed exact native RGBA
checks for all 16 masks, upper spill, planned material/alpha, completed iron/raw
empty artwork, changed adjacency, removal and reload. GPU diagnostics were only
the known three signatures; completed/planned screenshots were inspected.
Protected `build/bars-transport-native-20261024-011510` matched 95 observations
across 21 states, including all wall masks and first-item order/removal changes.
These sessions preserved their source and closed. Diagnostic probes do not
establish natural construction or removal effects for every building family.

Gear/axle rendering consumes native signed machine phase, horizontal axis and
first-item material. Stable resident geometry uses cached shaft/fitting composites;
the shared machinery shader changes frames without rebuilding geometry. Planned
textures preserve native alpha rounding before filtering and mipmap generation.
Protected `build/axles-gears-states-native-20261023-233123` records546 controlled
cases across horizontal axes/orientations/lengths, vertical axles and gears,
signed phases, absent machinery, planned/complete, first-item materials and gear
disengagement. All858 footprint cells match28 native textures exactly when axle
shafts are material-colored and overlaid with uncolored fittings. Complete art
uses frame2 only for positive odd machine phase; planned art uses painted frame1.
Completed empty buildings retain painted pixels; otherwise the first item's
actual material supplies the shaft/gear palette. Horizontal axles need native
`is_vertical` even at1x1; dimensions alone are insufficient. Planned gear alpha
rounds half upward, while planned axle alpha truncates half. Gear disengagement
alone does not change these frames when machine phase is held constant.
`build/gear-neighbors-native-20261023-233800` checks648 neighbor combinations;
the gear tile retains ordinary gear art. Native graph-connected south NS axle
probe `build/gear-connected-native-20261023-234108` confirms reciprocal machine
nodes and ordinary artwork across the full vicinity before/after250 ticks.
The latter needed a recorded resume after native paused at frame1. No tested
case selects the south-axle artwork token; this does not prove it globally unused.
All sessions closed and preserved source manifests; screenshots were inspected.
`axles_gears_rendering.json.gz` retains the scalar captures and exact texture
matches, indexed by `machinery_directions.json`. These are diagnostic art/graph
observations, not natural construction or powered-operation acceptance.
Protected `build/transmission-transport-native-20261024-000532` verifies256
bridge observations across60 controlled states for horizontal WE/NS1x1 axles,
vertical axles and gears. Signed phases, absent/detached machinery, first-item
order and removals match native facts exactly. The source manifest stayed
unchanged and the owned session closed. This transport diagnostic uses synthetic
completed buildings and registered seed items; it does not prove recipe effects.
`build/qa/transmission-native-alpha` passes all five machinery GPU checks with
known engine diagnostics only. Transmission coverage compares uploaded RGBA
against native textures, including planned alpha, raw/oak/iron materials and both
frames; it also checks phase-only geometry stability, axis changes, removal and
reload. Completed/planned screenshots were inspected. Core checks passed in
`build/qa/transmission-rendering`.

Windmill rendering consumes native orientation, signed rotation and first-item
material facts. `WINDMILL_S_1` supplies stable resident geometry; the shared
machinery shader selects orientation and frame without rebuilding that geometry.
Protected `build/windmill-states-native-20261023-231110` establishes its native
replacement rules:1,080 paused controlled cases across nine orientation vectors,
ten signed rotations, planned/complete, working0/1 and none/oak/iron first items.
All12,960 footprint/signpost cells match672 installed textures exactly. Orientation
uses the eight compass directions (east-positive x, south-positive y); zero vector
uses south. Planned art retains orientation, painted pixels and half opacity,
but always frame1. Completed art uses frame2 for any nonzero rotation, including
negative values, and the first item's material palette or painted pixels when
empty. The working flag does not select the frame. Source preservation and owned
cleanup passed at frame0; screenshot inspected. Detailed scalar evidence lives in
`windmill_rendering.json.gz`, indexed from `machinery_directions.json`.
This is diagnostic artwork evidence, not natural completion or wind-power effects;
orientations outside-1..1 and multiple-item artwork precedence remain untested.
Out-of-range native vectors publish paired unknown values. The additive mirror
fields use-2 for unknown vector components and-129 for unknown rotation. Planned
windmills use the shared frame sampler through an alpha-blended ghost shader.
`build/qa/windmill-rendering/core.log` passes all19 core checks. The initial GPU
run caught a helper-function builtin-scope error; it is excluded. After passing
UV/color explicitly, `build/qa/windmill-shader-cells` passes all four machinery
GPU checks, including72 windmill orientation/rotation/stage cases against static
native-cell render references, unchanged mesh identity, material changes, removal
and reload. `build/qa/windmill-visual` passes the final capture version. Both
complete and planned images were inspected; only documented Godot diagnostics
remain. Protected `build/windmill-transport-native-20261023-232719` compares231
observations across50 states with DF, including all nine vectors, signed rotations
and first-item reordering/removal. All match; owned DF closed and source manifests
were unchanged. This transport probe controls windmill timers and simulation
fields; it does not establish natural wind-power effects.

Instrument material-picker artwork consumes owned instrument-definition facts.
Native protected captures
`build/instrument-picker-native-20261023-204630` and `...-204740` establish eight
registered candidates across keyboard/stringed/wind/percussion and oak/iron.
Controlled `PLACED_AS_BUILDING` flags were restored before exit. All eight
exported textures per capture exactly match the corresponding BUILDING sprite
and actual material palette. The expanded percussion group and individual each
match665 opaque texture pixels in the inspected screenshot. Both owned sessions
closed at paused frame0 and preserved the source. The earlier204542 probe failed
an ASCII-text expansion helper on an accented generated name; it is excluded.
Candidate appearance carries the definition's music-skill family and placement
flag through the bridge, mirror, model and Godot dictionary. Both are optional
for older data, validated together, and included in material-list revisions and
wire estimates. The resolver selects family-specific BUILDING/HANDHELD artwork;
runtime never consumes the diagnostic graphics cache. Adapter138 and all19 core
checks pass; `build/qa/instrument-picker-facts` also verifies all eight native
candidate texture hashes using installed art.
Protected `build/native-material-instrument-main-20261023-205940` verifies the
actual launcher/category/Instrument/map/group/individual pointer flow. Keyboard
facts reached the candidate dictionary; selected cherry instrument48520 completed
naturally in575 frames, stage1/1 with no jobs, retaining exactly that item. The
expanded picker and completed screenshots were inspected. Source preservation
and owned-session cleanup passed, with only the three documented Godot issues.
This natural completion covers one real generated definition; the eight texture
references cover artwork across all four families. Map-item streams still lack
these definition facts and retain their legacy approximation.
`instrument_rendering.json.native_material_picker` records this evidence.

Roller resource ownership is covered by registered `roller_pages_fixture` and
`roller_pages_gpu`:300 independent Rollers span two256-slot pages. Tests verify
unique slots and signed positions, stable geometry for phase updates, released
slot reuse across half/full population churn, unchanged surviving geometry and
fresh texture identities after fixture reload. `build/qa/roller-pages` passes
with the documented three Godot diagnostics. Protected
`build/roller-lifecycle-native-20261023-203509` verifies live detach clears the
Roller node/session and reconnect creates a fresh page containing a phase changed
in DF while detached. This uses a synthetic completed Roller and inactive machine;
it establishes publication/resource lifecycle, not construction or power effects.
Owned DF96140 closed at frame836, source remained unchanged, viewer assertions
passed and diagnostics were known only. Evidence is in `roller_rendering.json`.

`fixtures/construction/instrument_rendering.json` establishes Instrument artwork
rules from paused protected captures200157/200456/200604 on2026-10-23. The initial
34 cases use unmodified generated definitions;66 controlled cases vary their
`PLACED_AS_BUILDING` flag (restored after each class), four materials and both
stages. Another18 cases vary building material independently of a constant iron
instrument. Every exported RGBA image matches installed artwork/palette rules.
Planned Instruments use a keyboard BUILDING placeholder, recolored by building
material with half alpha. Completed nonempty buildings use the instrument raw's
`music_skill` (keyboard/stringed/wind/percussion) and `PLACED_AS_BUILDING` to choose
BUILDING versus HANDHELD art, with actual item material color. Completed empty
buildings use painted keyboard BUILDING art. The controlled native screenshot was
inspected after item cleanup. Sources stayed unchanged and owned sessions closed.
The separate placed-only probe200329 had no generated placed Wind definition and
is excluded; the controlled/restored flag probe covers that combination.
These are semantic fields on item definitions and actual materials; renderer/menu
scratch must not be used at runtime. Capture200823 adds14 exact first-entry
ordering cases with two families/materials and use_mode0/1/2. The bridge publishes
the first instrument definition's semantic family and placement flag, plus its
actual material. Unknown facts remain explicit. The building resolver now uses
these facts and the planned keyboard placeholder. Native planned alpha is now
rounded down in the cached RGBA bytes before filtering, with white vertex tint.

Protected `build/instrument-state-native-20261023-201924` verifies84 observations
across18 states: all four families, both controlled/restored placement flags,
planned/complete stages and empty-after-removal. Registered items were created
for this diagnostic; it does not establish natural construction. Inspector passed,
source remained unchanged and owned DF73156 closed. Actual recording replay in
`build/instrument-native-viewer` checks all18 sprite regions/tints and uploaded
RGBA cells exactly, distinct portable/placed images, invariant planned images
and empty-state recovery. The rendered percussion screenshot was inspected.
Only documented Godot diagnostics remain. An earlier test harness used the wrong
shader parameter; that failed harness run is excluded from acceptance.

The shared first-construction-item material now passes through the world model's
snapshot-local material remap. A regression verifies table reorderings preserve
color and actual material changes update it for Instruments, Rollers and Track
Stops. `instrument-semantic-remap` passes all19 CTest checks; installed plugin
build and `instrument-viewer-integration` Roller/Track Stop GPU checks pass
(GPU with known issues). Native capture
`build/instrument-icon-native-20261023-202515` verifies the fixed
`BUILDING_ICON_INSTRUMENT` header for all four families:716 opaque pixels per
capture match the installed icon exactly, selected IDs match, frame0/source
preservation passed and owned DF71052 closed. The percussion header image was
inspected. Selection now uses that fixed icon.

Registered `instrument_fixture` / `instrument_render_gpu` cover all four
families, portable/placed definitions, planned/completed art and tint, fixed
headers, empty recovery, removal/reused ID and fixture reload. Base-level RGBA
hashes retain the independently verified native artwork rules without shipping
art. `build/qa/instrument-render-final` passes with the three documented Godot
diagnostics. Two prior harness failures used a graphic-variant argument as a
palette row and included generated mipmaps in base-image hashes; corrected tests
exclude both attempts from acceptance. Live disconnect/resource coverage remains
part of the broader construction audit. Handheld map-item Instruments still use
their separate approximation; the placed-building path is corrected.

`fixtures/construction/track_stop_rendering.json` records protected capture
`build/track-stop-art-native-20261023-182731`: 160 synthetic granite Track Stop
cases spanning sixteen underlying track masks, five dumping settings and both
construction stages. Completed art follows finished track connections, with
single endpoints using straight art and bare floor using the crossing. Planned
stops always use four-way artwork with painted RGB and half alpha rounded down.
Dump settings do not affect these sprites. All13 exported textures match the
installed artwork byte-for-byte. The source save stayed unchanged, the owned
session closed and the native screenshot was inspected.
The asset query now consumes the existing semantic completed-track mask; no new
native field or graphics-cache access is needed. Terrain changes invalidate the
affected stop's cached artwork independently of building versions. World ghosts
use cached floor-half source alpha with white vertex tint. Resolver tests cover
all sixteen masks and both stages;
root/core and extension/item-icon gates pass in `build/qa/track-stop-core` and
`build/qa/track-stop-render`. Registered `track_stop_render_gpu` generates19
snapshots covering all16 masks with empty building deltas, an unrelated tile
change, planned state and track removal. It verifies native sprite coordinates,
white tint, batched completed stops, unchanged mesh identity for unrelated
changes, half-alpha separately sorted planned ghosts and exact restoration of
the original rendered image after removing track.
`build/qa/track-stop-lifecycle-final` passes with known engine diagnostics only;
core checks also pass in `build/qa/track-stop-lifecycle-fixed`.
Protected material probes `build/track-stop-material-native-20261023-183623` and
`build/track-stop-floor-material-native-20261023-183759` vary granite, iron, green
glass and oak across128 cases each. Stops have no contained construction items;
changing building or underlying construction material leaves stone artwork
unchanged. Static inspection of native trap draw RVA0x5a6c70 explains this:
Track Stop branch0x5a6f26 reads the first contained item's actual material/color
and selects wood art only for item type WOOD (log), not arbitrary wooden material.
Planned art uses a fixed sprite key. Runtime must not read the renderer scratch.
Protected `build/track-stop-items-native-20261023-184132` supplies a first
contained item (oak log, oak block, granite block, iron block or green glass
block) over16track masks and2stages. All160 exported-image comparisons match:
completed logs select wood artwork; blocks select stone artwork even when made
of oak. Completed sprites use the first item's actual-material solid-state
color, replacing the first18 palette keys with first-match duplicate precedence.
Planned art ignores these inputs and uses the uncolored half-alpha stone
crossing. The diagnostic stays paused at frame0, closes its owned session and
leaves the source save unchanged; synthetic item combinations do not establish
build eligibility. Additive `Building.construction_item_is_log` (-1 unknown,
0 non-log,1 log) and `construction_item_material` (actual material or65535 unknown)
now carry these facts. The plugin reads exactly `contained_items[0]` at a safe
point using native item getters; no item-role search or graphics state is used.
Validation rejects non-Track-Stop contexts, invalid log facts and material ranges.
The model clears unknown observations and revises artwork when either fact changes.
Completed rendering uses log status for the sheet and actual-item material for
palette; planned stops always use uncolored stone crossing artwork.
Core/serialization/model/resolver tests pass in `build/qa/track-stop-item-facts`.
Plugin build/install passes (`build/notes/pm/track-stop-item-build.log`).
`build/qa/track-stop-item-render` extends the GPU replay to23states, verifying
log-to-wood-block sheet changes, actual-material recoloring and unknown-state
palette clearing, with known engine diagnostics only. Protected
`build/track-stop-transport-native-20261023-185746` verifies25published observations
across six states using real seed logs/blocks: empty, log, log before block,
block before log, log after removal and empty after removal. Every first-item
fact and actual-material token matches native state; the inspector accepts the
recording. This caught and fixed a missing global-to-snapshot-local material
index remapping in the new field. The rejected earlier recording is not evidence
of acceptance. Plugin rebuild/install passes in
`build/notes/pm/track-stop-item-local-material-build.log`.
`build/track-stop-native-viewer` replays all six states through published batches,
checks sheet rows and visible transitions, confirms second-item addition keeps
the same mesh, and restores the original image when the stop becomes empty.
Uncropped frames were inspected; only known engine diagnostics remain. The owned
native session closed at frame600 and the source save stayed unchanged. Item
insertion/order/removal are diagnostic fixture operations, not a gameplay UI or
natural construction/minecart-effects claim.
Four clicked native headers match all709 opaque pixels of
`BUILDING_ICON_TRACK_STOP`. Selection now returns that fixed icon. Registered
`build/qa/track-stop-selection` passes exact icon RGBA checks across19 terrain/stage
states, with known engine diagnostics only. Both native sessions closed without
changing the source save. These synthetic captures do not establish natural
construction or minecart operation.

`fixtures/construction/pump_rendering.json` records protected capture
`build/pump-art-native-20261023-173325`: four synthetic stationary granite screw
pumps, each at stages0 and1, paused at frame0. All16 exported textures match the
installed source artwork exactly: native intake directions0/1/2/3 use S/W/N/E
output-facing art respectively. Completed pixels are not material-recolored;
planned pixels retain RGB with alpha divided by two and rounded down. Each pump
occupies two cells along its flow axis. Screenshot inspected, source unchanged,
owned session closed. Optional scalar `Building.pump_direction` now carries DF's
intake direction directly, with -1 for unknown old recordings. Validation rejects
out-of-range values and non-pump contexts; shadow equality and model revisions
include direction. World and selection queries use the captured output-facing
art and keep its painted palette. Unfinished world pumps use cached floor-half
source RGBA and white vertex tint. Unknown old recordings retain historical north artwork. Schema transport,
model revision/clearing and all four sprite layouts pass with the core, material
and item-icon checks in `build/qa/pump-direction`. Plugin build/install passed.
Protected `build/pump-state-native-20261023-174335` publishes all four directions
and planned/completed stages; inspector accepts the recording, source stays
unchanged and the owned session closes. GPU replay `build/pump-viewer-final`,
using `build/pump-state-native-20261023-174702`, checks all eight planned/completed
orientation cases against native cell positions and verifies vertex opacity.
All eight images were inspected; diagnostics contain known engine signatures
only. The source fixture reveals all sites before300-tick terrain warmup and the
replay visits samples chronologically; earlier harness failures lacked those
conditions and are excluded. This verifies stationary world artwork, not
screenshot-wide pixel equality.
Protected `build/pump-motion-native-20261023-175106` clicks all four completed
pump directions. Every native header uses `BUILDING_ICON_SCREW_PUMP`: all902
opaque pixels agree per capture. The selection icon API now returns that installed
asset for pumps, including multi-tile ones. Gate `build/qa/pump-selection-icon`
passes; GPU replay `build/pump-icon-viewer` checks byte-identical icon RGBA in all
eight planned/completed cases, with known engine diagnostics only.
The same native probe initializes pump energy100 and lets DF advance16ticks per
pump (64 total), observing natural energy decay and both animation frames. All16
exported textures match source art. Paused energy-only changes in the preceding
probe kept the first frame; animation cannot be inferred from energy alone.
Native follow-up `build/pump-phase-native-20261023-175603` checks424 samples,
including rows40..43 and natural energy decay to zero. All match variant2 when
energy is nonzero and `(cur_year_tick + 10*y1) % 20 >= 10`, otherwise variant1.
Static draw trace at RVA0x594a56 derives that phase from renderer scratch; its
writer at RVA0xe8fab1 copies `cur_year_tick % 10080`. Since10080 is divisible by20,
the semantic calendar tick is sufficient for fortress rendering. The scratch
counter was read only by the diagnostic; it must not become a runtime input.
Owned session closed and source stayed unchanged. Additive
`Snapshot.calendar_year_tick` transports DF's
calendar position, with -1 for unavailable old recordings. `Building.pump_running`
uses -1 unknown,0 idle,1 active from native nonzero pump energy. Validators check
calendar range and pump-only activity; model clock updates do not alter building
revisions, while activity changes do. Unknown observations and session resets
clear prior facts. Core/schema/model tests pass in `build/qa/pump-activity-transport`.
Plugin build/install passed; protected `build/pump-activity-native-20261023-180720`
matches all845 calendar samples and1098 activity observations, including each
natural stop transition. Inspector accepts the recording; source remains unchanged
and the owned session closes. A dedicated pump shader now selects the alternate
atlas frame from that semantic calendar and an immutable per-vertex displacement
encoding activity and base-row parity. Calendar-only updates change one global
shader uniform without rebuilding geometry; unknown clock/activity stays stationary.
The batching path preserves this payload and texture-array sampling.
Root/extension builds, item-icon and mesh-batching checks pass in
`build/qa/pump-animation`. GPU `build/pump-animation-batched-layers` checks32
cases across all four directions from protected recording
`build/pump-activity-native-20261023-181413` (845 calendar samples and1098 activity
observations match native state). Active/idle frames, native phase, paused replay,
unknown-clock fallback and published batch rendering pass. Source mesh identity
stays unchanged across clock-only updates. Diagnostics contain known engine issues
only. Registered `pump_animation_gpu` generates a semantic synthetic fixture and
checks all directions, row parity, published batches, stable clock-only geometry,
pause, activity restart, idle/unknown activity, unknown/backward calendar, and
fixture reload into a new session. `build/qa/pump-animation-lifecycle-final` passes
with known engine diagnostics only. Fixture replay advances forward; returning
to the beginning requires reload. Protected
`build/pump-reconnect-main-20261024-070017` separately verifies explicit live
detach/reattach with a synthetic completed active pump. Detach removes the node
and building batches and changes session generation. Reattach creates new node
and mesh resources; its image matches DF's newer calendar tick157609 after
initial tick157599. An independently set opposite half-cycle changes the image,
and restoring the current phase restores identical pixels. Initial energy50
and natural decay keep activity valid. Source preservation and owned DF cleanup
passed; the reconnected image was inspected. Only three known Godot diagnostics
remain. This is explicit viewer detach, not process-crash acceptance. These
synthetic captures do not
prove natural construction, mechanical power supply, liquid transfer or full
pump-operation UI. No native graphics cache is used as a runtime input.

Pump preview alpha is rounded down in cached source RGBA before filtering,
with white vertex tint; completed pump pages retain their original bytes.
Protected `build/pump-material-native-20261024-070243` compares32 paused states
across four directions, planned/completed stages and granite/iron/green glass/oak
building materials. All16 distinct native textures exactly match installed
painted artwork, unchanged by these material choices. Source preservation and
owned DF cleanup passed. `pump_material_gpu` checks all32 cases against native
texture hashes and reload reset. Core, that regression and existing completed
pump animation/lifecycle checks pass in `build/qa/pump-material-native`, with
only documented Godot diagnostics. The rendered scene was inspected. This is
rendering evidence, not another natural-construction claim.

Instrument, Track Stop, Roller, Water Wheel and Windmill previews also round
source alpha down before filtering, using the shared immutable building-page
cache and white vertex tint. Track Stop is selected by its Trap subtype5; other
traps do not enter this path. World geometry and selection artwork supply the
same subtype. Completed pages and animation/resource ownership are unchanged.
The separate bridge/gear ceil-half and axle floor-half rules remain intact.

`fixtures/construction/planned_machine_pixels.json` retains native planned-cell
hash sets from the existing Track Stop, Roller, Water Wheel and Windmill captures.
The shared test helper checks uploaded cells against these sets; existing family
tests independently assert cell positions, orientation, phase and draw ownership.
The Instrument test uses the directly captured planned keyboard texture hash.
`build/qa/planned-machinery-verified` passes core and nine GPU checks: those five
families, Roller resource pages, transmission, bridge materials and pump materials.
Only documented Godot diagnostics remain. The planned Windmill image was inspected.
The first build attempt omitted subtype propagation in the selection caller;
that failed run is excluded. No bridge/schema changes or native scratch access
are required for these presentation corrections.

`fixtures/construction/bed_bedding.json` records a later native investigation
on the same supported build. Protected `build/bed-native-observe-20261023-160803`
renders24 new granite beds while paused. Their24 unique native cache entries
match the item-ID-seeded sheet, pillow and sheet-color choices traced in
`0xc80546..0xc80768`; the screenshot was inspected and the source preserved.
The native generator at `0x2471c0` is a75-byte leaf that accesses only its supplied
state pointer, making independently owned state a candidate integration path.
The compositor at `0xcee8d0` mutates global graphics caches and is excluded from
the semantic runtime path. It uses descriptor palettes for base/sheet recoloring
and overlays pillow above sheet above base. This evidence covers loose granite
beds. Follow-up `build/bed-native-picker-20261023-161049` shows that the generic
granite group uses default sheet/pillow variants and no descriptor recoloring;
expanded individual rows show the distinct item-specific bedding. The native
picker screenshot was inspected. `build/bed-native-installed-20261023-161304`
selects item48525 through the native picker and naturally completes Bed1490
at frame425, stage1/1 with zero jobs and that exact input. Its capture is partly
occluded by a dwarf and does not establish pixel parity. Both runs preserve the
source and close their owned sessions. An earlier installed test used disconnected
display floor and is excluded. Generic group defaults must stay distinct from
item facts. `bed_appearance_native.cpp` now provides fingerprint-gated native
choices using independently owned generator state. The diagnostic command
`df3d bed-choices-read <item-id> <descriptor-color-count>` returns sheet, pillow
and zero-based descriptor color (-1 when no colors exist). Protected
`build/bed-native-wrapper-20261023-161613` matches all24 native-rendered choices,
verifies repeatability, invalid inputs, empty/single-color handling and the native
254-color limit, with unchanged graphics cache, paused frame0 and preserved source.
Bridge build/install passed. Optional `BeddingFacts` now carries native sheet and
pillow choices plus base/sheet descriptor color names on `Building` and `MapItem`.
The base color comes from the material's solid-state pattern, not an item dye
override. Missing facts remain unknown in old recordings; no graphics cache IDs
cross the bridge. The additive fields retain the schema version. Validators reject
out-of-range variants and facts on non-bed entities. Model equality and revision
tracking include bedding, including clearing known choices on a later unknown
observation. Core/schema/model tests pass in `build/qa/bedding-transport`.
Protected `build/bed-transport-native-20261023-162516` records23 observations
across loose item48525 and naturally completed Bed1490: sheet0, pillow1,
base CLEAR, sheet CHARTREUSE all match native rendering choices. The inspector
accepts the recording; source preserved and owned DF closed. Construction candidate
appearance now also carries optional bedding through the Lua adapter, wire codec,
world model and Godot dictionary. The adapter calls the owned-state native helper;
response-size accounting and revision hashes include these facts. Validators reject
non-bed contexts, invalid variants and oversized color names. The icon API accepts
valid optional bedding. The shared `df3d_assets/bed.h` compositor resolves installed
material, sheet and pillow artwork, replaces the first18 palette keys on base and
sheet, and lets each nontransparent upper-layer pixel replace the lower pixel.
Picker individuals, loose items, installed buildings and selection icons use this
compositor. Grouped picker rows use sheet0/pillow0 without descriptor recoloring,
matching the native generic icon. Unknown bedding remains unknown. Composite
resources share the existing asset-lifetime cache; item cache keys include bedding.
Core and material checks pass in `build/qa/bedding-picker`; the focused icon check
passes in `build/qa/bedding-picker-icon`, including existing native pixel comparisons
and malformed bedding cases. Bridge build/install passes (`bed-picker-build.log`
under ignored working notes). Procedural compositor tests pass in
`build/qa/bedding-renderer` (its initial extension type error was fixed); extension
and picker checks pass in `build/qa/bedding-renderer-fixed`. Native-capture regression
`build/qa/bedding-native-icons` matches all3,290 opaque pixels across the default
group and four individual icons. `bed_bedding.json.renderer` retains their native
pixel hashes and inputs. The65 partial-alpha pixels per icon are excluded from
this initial comparison. Protected live run
`build/bed-render-live-main-20261023-164452` verifies four candidate bedding
payloads against native choices, public exact-item48525 selection and natural
Bed1490 completion at frame425 with zero jobs and the exact permanent input.
The completed selection icon was inspected. The world screenshot is partly
occluded by a citizen, so full world pixel parity remains unproven.
Its group icon now matches all723 visible native pixels, including65 partial-alpha
pixels. This exposed and corrected the material-row picture frame from36x36 to
native40x36; the narrower frame changed20 translucent right-edge pixels.
`build/qa/bed-frame-width` passes; source save was unchanged and the owned session
closed. Diagnostics contain only the three documented engine signatures.
`bed_bedding.json.live_renderer` records the evidence and remaining material/world
coverage limits. An initial live comparison failed because the harness compared
JSON floats with integer dictionary values; explicit field comparisons resolved it.

Terrain atlas sampling uses per-face cell centers in CUSTOM2 (terrain in xy,
ground spatter in zw); furniture fragments also retain their atlas center in xy.
MSAA edge fragments can extrapolate UVs beyond their
primitive, so interpolated UVs must not select the atlas cell. Pooling, spatial
batching and restored source meshes preserve this stream. `terrain_seams_test`
checks fractional camera offsets/zooms across ordinary, array, spatter, cutout,
furniture and planned-furniture
sampling; `mesh_batches_test` verifies the corresponding vertex attributes.
Furniture uses native texture alpha as well as contour geometry: the 128-alpha
outline/shadow pixels must blend over the floor instead of becoming opaque gray
bands. A depth prepass retains opaque furniture occlusion. The seam check also
verifies half-transparent furniture/planned art against a colored background.

Billboard visibility bounds follow the fragment shader's ceiling clip. Item preparation
retains separate source-query `bounds` and renderer `render_bounds`; never use the clipped
box to track roof dependencies, since removing a roof must expand visibility again.
Unit bounds include the culling margin before ceiling clipping, with the
engine margin disabled for that billboard batch to avoid expanding it above the roof.
Classic sprite bounds are not ceiling-clipped. Camera movement does not invalidate these
bounds or rewrite sprite payloads. `item_preparation_gpu` covers roof lowering, raising,
removal and style transitions; `sprite_ceiling_revision_test` covers source invalidation.

Terrain and buildings render through the full map depth below the selected level.
Their geometry stays resident across level and depth changes. Each terrain block
has common faces plus covered-only and cut-only alternatives. Opaque terrain uses
32x32x16 batches (two DF blocks square, sixteen levels high). Source meshes and
occluders retain per-level parents for semantic visibility; merged batches live
under the terrain root. Their CUSTOM1 stream records source level and alternative.
Bulk faces and cut-only caps have separate batches within each spatial region;
only the slab containing the top level submits cap batches. Shared batch materials
select the active depth range and cut alternative in the
vertex shader, clipping excluded triangles before rasterization. Entire slabs
outside the depth range are hidden. Slice changes update material state and slab
visibility without remeshing or buffer uploads. Source materials stay independent
so disabling batching restores the same per-level rendering. Buildings retain
their per-level batching; fluid/ghost-containing terrain sources stay independent.
Frustum and occlusion culling still control submission of resident geometry.

Terrain consolidates compatible texture surfaces before their first GPU upload,
using immutable texture-array banks. Spatial batches preserve those per-vertex
texture layers. Hiding an original mesh after batching does not release its GPU
buffers, so consolidating only the final batches leaves texture-rich maps exposed
to renderer resource-pool exhaustion. Publishing a terrain batch releases its
duplicate source GPU surfaces while retaining CPU arrays, materials and bounds.
An edit retains its published batch until the complete replacement is ready.
Rebuilding reads retained CPU arrays and materials without restoring unchanged
source GPU meshes. Publication attaches the replacement before releasing the old
batch. Removed terrain may remain visible until that publication; semantic picking
and cutaways continue to read current sources. Leaving a group, disabling batching,
or clearing with restoration restores source drawing; unsupported replacement input
falls back to current sources instead of retaining an obsolete batch indefinitely.
Changing height retains the published buffers. Terrain teardown clears
batches without restoring sources that are about to be destroyed. Building meshes
retain their existing source-buffer ownership for presentation transformations.
`terrain_surface_inputs` and `terrain_surface_uploads` count pre-consolidation and
initially uploaded source surfaces. Batch statistics expose `source_surfaces` and
`retired_source_meshes`; settled terrain should have no duplicate source surfaces.
`mesh_batches_test` checks this ownership, restores source drawing when batching is
disabled, and compares material/vertex data at the GPU's color/normal precision.
`mesh_batches_lifecycle_test` builds an optional, separate test extension and checks
retired-source gathering, cancellation, deletion, fallback, teardown and edit
priority with deterministic steps. It does not add test bindings to the viewer.
`terrain_slabs_gpu` compares batched and source-rendered pixels across slab
boundaries, cut alternatives and shallow depth windows. `mesh_batches_test` also
compares the selected vertex/material streams and asserts no slice-driven rebuilds.

Initial preparation covers the entire map, including levels above the selected cut.
This trades loading time and resident memory for predictable vertical travel.
Terrain preparation and batch flushing each use an 8 ms soft budget during loading
and a 2 ms soft budget afterward. Published groups dirtied by edits take priority
over new groups and receive at least a 4 ms batch-flush budget to shorten stale
visuals; one indivisible job can exceed its budget, and this is not a frame-count
guarantee.
Source edits reevaluate the changed block and already resident neighbors in its
3-by-3-by-3 dependency neighborhood, including hidden levels and late block arrivals.
Exact CPU surface/material comparison preserves unchanged layer meshes and batches;
only changed payloads are uploaded again. Spatial instances and unchanged opaque
occlusion shapes survive mesh replacements. Occluder replacement/removal retains
the old resource until its instance rebind/detach has been submitted, so the render
thread cannot receive a resource free before the corresponding instance update.
Session, map-size, asset and reveal changes reset the appropriate geometry owners.
Occluder instances share immutable block-local shapes through a geometry-only cache
bounded to 4096 entries; that cache can survive session replacement. Eviction drops
the cache reference without invalidating instances still using the shape.
`built_block_count` counts prepared logical blocks, including empty blocks;
face counters describe resident geometry, including inactive cut alternatives.
`mesh_batches_test` asserts zero terrain/building rebuilds and batch invalidations
during level/depth changes. `terrain_occluder_test` compares retained geometry after
hidden source edits against fresh builds; the pure mesher tests verify both face
alternatives exactly against the original cut mesher.

Items and creatures render on the selected level and eleven levels below it.
This range follows the selected level; descending brings nearby sprites back.
The range check precedes appearance preparation, and cutout picking uses the same
filtered render arrays. Terrain residency and semantic source data are independent.
The shared stack/support atlas has stable map-wide addressing. Level and depth
changes refresh visible sprite membership without reallocating the atlas or
re-evaluating unchanged terrain support. Session, map-size, asset and reveal
changes still reset its owning layout cache. Terrain and item changes outside the
render window update retained membership so returning levels use current data.
The backdrop stays below the lowest map/window layer, rather than blocking deep pits.
Projectiles and transient effects retain their existing visibility rules.

The native depth setters remain available for deterministic tests and diagnostics:
`set_window_depth(0)` follows the current map height across session changes;
`set_sprite_depth(0)` inherits terrain depth. Ordinary startup requires no environment
overrides. `DF3D_WINDOW` overrides terrain depth for smoke tools and fixture captures.
`item_updates_test` and `vertical_motion_test` cover range boundaries, paused level
changes and exact stack restoration. Full-depth terrain still has a residency cost;
limiting sprites reduces preparation and drawing, not all terrain memory.

## Reporting bugs and contributing

Open a GitHub issue using the bug report template; do not upload game assets or saves.
Pull requests describe the problem, the change and the local checks run.

## License

Original DF3D code is [MIT licensed](LICENSE); FlatBuffers is Apache-2.0, doctest and godot-cpp are
MIT, and DFHack is primarily Zlib with component notices. DF3D does not distribute Dwarf Fortress game assets; Dwarf Fortress is a trademark of Bay 12
Games, and DF3D and its DFHack forks are independent projects endorsed by neither Bay 12 nor DFHack.


Reports wheel behavior is recorded in `fixtures/reports/scrolling.json` from the
protected paused060838 capture: CONTEXT_SCROLL advances one row and its PAGE
variant fifteen rows in the1200x800 Combat list; standard scroll keys are no-ops.
Installed native key bindings map these to wheel and Shift+wheel respectively.
Owned DF54624 closed at frame zero with unchanged source-save hashes. The view
now uses these steps; `build/qa/reports-wheel-verified` exercises actual Godot
wheel dispatch in both directions and passes with known engine diagnostics only.
Scrollbar drag, outside-list pointer handling, resize and pagination anchor
acceptance remain outstanding. Initial pwsh harness setup failed on its
System.Drawing reference before launching DF; the successful lane used Windows
PowerShell, matching the existing capture runner requirements.


`reports_controller.gd` connects the Reports state to the existing serialized
semantic action service. It detaches superseded/closed requests, rejects terminal
failures without displaying protocol messages, and closes/clears local state on
service session invalidation. The service remains responsible for DF epoch and
transport identity; the Reports state uses a local session generation for callback
ownership. The registered `reports_controller_test` exercises the real service
against an injected world, covering successful reads, queued selection replacement,
close during an outstanding read, late receipt, epoch invalidation and rejection.
`build/qa/reports-controller-final` passes with its extension prerequisite verified.
The earlier controller-verified test failed due to incorrect synthetic status
numbers and was corrected to use the contract enum before the successful rerun.
The GPU frame capture is explicitly classified as manual pending automatic native
image comparison. Public launcher wiring and live controller acceptance remain
unfinished; neither this controller nor the full Reports screen is exposed yet.


Protected `reports-controller-live-20261001-061416` verifies the actual Reports
controller and semantic action service with the public live model API: All20,
Combat97 across pages, Sparring11, and Sparring unit2905's697 retained log IDs in
exact native order after opening at the newest end and prepending earlier pages.
Closing releases the ticket and local rows. Native unit names/professions/IDs were
compared with the independently captured oracle. Owned DF40320 closed at frame
zero; source clone hashes were unchanged. Only the documented Godot diagnostic
signatures occurred (passed_with_known_issues). `unit_rows.json.controller_capture`
retains scope and provenance. Live disconnect/epoch injection, host integration
and full rendered-screen behavior remain unaccepted.


`reports_panel.gd` joins the Reports view/controller to the existing ui_host
ownership interface. Configuration builds a layer10 surface from installation
assets and registers the owner; opening claims modal map input, dismissal releases
it, and play locks/session changes close it. The view checks a host-provided input
guard in both global and GUI handlers so overlays block Reports right-click/back
and row/tab/wheel actions. `build/qa/reports-panel-owner` passes the registered
ownership test with the extension prerequisite. `build/qa/reports-overlay-input`
passes GPU pointer dispatch checks (blocked right-click preserves the screen,
unblocked right-click closes it) with known diagnostics only. The ordinary
fortress launcher/availability registry intentionally does not instantiate Reports
until its complete native behavior is accepted; these tests do not establish
completed launcher integration or complete-screen parity.


Reports All-list rendering now draws semantic report text using the installed
native palette and sourced `Date: <ordinal> <month>, <year>` line. The first15
rows match e7r01 exactly across (48,142)-(880,688), including native accent glyphs,
color/bright combinations, dates and36px pitch. Evidence:
`build/qa/reports-list-render/comparison.json` (zero differing pixels; known engine
diagnostics only). `fixtures/reports/list_rendering.json` transcribes the captured
native metadata verbatim; it is a rendering sample, not an All-membership rule.
The manual GPU capture additionally requires DF3D_REPORTS_LIST pointing at that
fixture. Recenter buttons/actions, report-list scrolling, long-text wrapping and
unit-log rendering remain unfinished. Current short-row pixel evidence does not
accept those cases or the complete screen.


Reports list recenter controls use original STOCKS_RECENTER artwork and the
native presence flags for each stored target. The state closes before emitting
that stored coordinate; zoom type, hidden flags and current unit position do not
replace it. The panel adapter clamps to map bounds when forwarding focus. Its
camera/highlight consumer remains unwired and unaccepted. Native e7 tooltip text
is copied verbatim. `reports-recenter-state` passes state/owner QA, covering absent,
negative/hidden and secondary targets. GPU `reports-recenter-render` verifies an
actual pointer click on the second button closes and emits position2; the first15
All rows including buttons match e7r01 exactly over(48,142)-(944,688). Diagnostics
are known signatures only. Ctrl+c hover behavior, native tooltip presentation,
stale refresh, camera/highlight effects and complete screen acceptance remain open.


Reports long-row work now wraps at110native character cells, keeps the fixed
36px row pitch, and paints opaque date cells over the start of the second text
line. Native Strange moods e7r06 provides a real long artifact report reference;
its `Crystal.` tail is overwritten by the date. First15short All rows remain
pixel-identical in `reports-wrap-order`; the long-row comparison still showed18
pixels at the overlapping button edge. Preserving the trailing wrap-space cell
is the subsequent correction and requires a fresh capture. The synthetic e7r29
fixture uses color10/11 with bright=true, exceeding the current16-color palette;
its native shades remain unresolved. Screenshot-specific color literals were
removed rather than accepted as a general color mapping. Long unbroken words,
newlines and color-edge cases remain unaccepted. Long ordinary-row overdraw now has
separate protected acceptance below.


The wrap-space correction is now verified by `reports-wrap-space`: zero differing
pixels for both the first15All rows and four Strange moods rows including the long
artifact report, with known engine diagnostics only. This supersedes the pending
18-pixel button-edge mismatch above; broader wrapping/color cases remain open.
Protected `reports-scroll-native-20261001-062551` captures Reports scrollbar
geometry at first rows0,1,15,40,81,82 for97Combat units/page15. Native thumb bounds
match `area_location_scrollbar.gd`'s inclusive-span formula with45interior cells.
`scrolling.json.thumb_capture` records samples. DF44860 closed at frame zero with
unchanged clone hashes. The click probe produced no movement and is not accepted
as arrow/track interaction evidence; dragging and Reports scrollbar artwork still
need verification before reuse is considered complete.


Reports scrollbar input is captured in protected062806: one-row bottom-arrow,
15-row track clicks and sampled drags agree with the shared native component.
Prior no-op probes addressed mouse_x121; pixel968 maps to native cell120 because
of the viewport inset. DF57188 closed/frame0/save hashes unchanged. Samples are
in `scrolling.json.pointer_capture`. `reports_scrollbar.gd` reuses component
geometry/input with a host guard and loads standalone `data/art/scrollbar.png`:
using the vanilla atlas instead left26pixel differences. GPU
`reports-scrollbar-native-art` has zero differences in both All/Combat scrollbar
rectangles(960,148)-(976,712), known diagnostics only. The view currently sizes
from loaded rows; full total/pagination anchoring is unfinished. Hover art, resize,
held repetition and full screen acceptance remain open.


Reports list pagination now retains total count and requested first row separately
from the displayed loaded range. Missing forward pages are requested sequentially
until that range is available; a rejection clears the pending scroll demand and
does not automatically replay. Close/selection/session changes reset the window.
The scrollbar uses full total rather than loaded length. `reports-page-window`
passes state/controller/panel QA, including a three-page jump and rejected demand.
`reports-page-window-gpu` replays native arrow/track/drag samples through actual
viewport input; known engine diagnostics only. Protected063244 then verifies a
Combat bottom jump to row82 through the actual controller/service: the first64
rows are extended to97 and the requested position is retained. Native identities,
Sparring11 and697log IDs still match. DF42596closed/frame0/cloneunchanged;
`scrolling.json.pagination_capture` records scope. Unit-log viewport anchors and
pending-request visual sequences still need acceptance.


The unit-log view now uses native e7r12's panel origin(32,64), sourced two-line
header,17fixed36px rows without dates, wrapped report colors and recenter artwork.
`list_rendering.json.unit_log` transcribes native q3unit2905metadata; the final17
rows match r12. `reports-unit-log-render` records zero differences in header
(40,76)-(920,100) and rows(40,112)-(944,724), known diagnostics only. On from_end
replies the state selects the last17loaded rows; prepending earlier pages shifts
its local offset to preserve the anchored report. `reports-log-anchor` passes
state/controller tests, including prepend identity. This does not accept a
complete log: scrolling UI, pause toggle, conversation speaker actions, secondary
positions and complete camera/highlight effects remain unfinished.


Unit-log paging state now tracks the global start of its retained window and a
requested global first row. Demands before/after the retained range use ID-cursor
pages; prepending preserves the anchored report, and rejected demand is cancelled.
`reports-log-window` state/controller QA passes with a65-report two-page anchor
case. This state capability is not yet wired to accepted unit-log scrolling UI.
Protected064044 independently confirms native unit2905 log total697/page17,
initial first680 and thumb bounds59..60 in native cells. The capture must yield to
DF after opening: immediate reads observed unpopulated popup state. An attempted
shared_ptr access failed; the successful capture reads its pointee only in the
oracle, never runtime. DF50792 closed/frame0/cloneunchanged. Wheel probes still
produced no movement and are not accepted input evidence. Fixture
`scrolling.json.unit_log_geometry` records these limits.


Native unit-log input is now distinguished from the tab list: protected064225/
064343 confirm tested CONTEXT/STANDARD/SECOND scroll inputs leave row680 unchanged,
including wheel-equivalent context input over the scrollbar. Up-arrow changes to
679; protected064456 track click changes680to663 and drag724to400 changes680to306.
DF12656/45656/20872 all closed/frame0/sourcecloneunchanged. `scrolling.json` records
sample scope. The log scrollbar is wired to global paging with page17, native
origin960,112 and636px height. Wheel handling is disabled for that view to match
the measured no-op. `reports-log-scrollbar` GPU verifies pointer arrow/track and
wheel no-op; its entire scrollbar region matches e7r12 exactly, with known engine
diagnostics only. This supersedes the unresolved log-input routing note above;
full live scroll-to-unloaded-history and held/resize cases remain unaccepted.


Protected064720 verifies live unit-log demands306->0->680 through the controller:
row306isID77070 after448loaded rows (start249); row0isID76758 after697loaded;
return680isID78288. Protected064827 repeats this through reports_panel/ui_host,
real model data and installation assets, with an injected world-input adapter.
The resulting live header,17rows and scrollbar match e7r12 with zero differing
pixels. All697IDs/order and unit-list identities were also checked. DF45792 and
DF29092 closed/frame0/sourcecloneunchanged; known engine diagnostics only.
`scrolling.json.unit_log_live_window` records scopes and limits. This verifies
assembled panel data/rendering, not the ordinary launcher, pause toggle, speaker
controls, stale-history mutation or complete camera/highlight effects.


Reports pause and refresh (2026-10-01): native captures070752/070854 establish
that every raw unit-log length change follows the cached newest row, including
removal and an append with no surviving report. Removed rows remain in the popup
cache until reopening. Same-length ID replacement does not trigger this policy.
With pause-on-new enabled, each length change pauses DF. The synchronous oracle
restores pause before returning and advances no simulation frames. The native
initial preference varied across captures; a fixed default is not established.

The controller polls filtered UnitList log_count every0.5seconds, with one owned
metadata ticket and identity/category/session/generation checks. Tail refresh
appends newer identities without dropping cached removed rows. Failed reads leave
refresh demand pending for a paced retry; that retry does not repeat the pause
intent. History pages extend the existing snapshot without counting source-total
changes twice. build/qa/reports-refresh-native-correction passes state/controller/
panel checks, including rejected-read recovery and partial-history accounting.

Protected build/reports-refresh-live-20261001-071007 verifies append/removal/
append/expired-only append through the real bridge, model, service and panel.
Cached counts are698/698/699/699, scroll positions681/681/682/682. An injected host
input adapter forwards to actual interaction._pause, and all four pause commands
received successful tick0 acknowledgements. Owned DF57000 closed, the verified
clone was unchanged, and only known engine diagnostics occurred. This is
already-paused command routing, not running-simulation auto-pause latency.

Native24x36 toggle art matches both states with zero differing pixels in
build/reports-pause-art. Tooltip wording is sourced; tooltip presentation,
preference initialization/persistence, running-simulation effects and protected
partial-history mutation/expiration remain open, alongside the wider Reports
surface. See fixtures/reports/pause_on_new.json. Reports remains hidden.


Reports recenter integration (2026-10-01): fortress_ui constructs Reports through
a staged route and connects its focus signal to the shared focus_tile camera path.
Reports and its notification rail remain hidden via allows_launcher. The focus
path exits Walk before selecting the new elevation, then synchronizes the rig
level before focus. Report coordinates use
DF x,y,z while Df3dWorld.map_size uses render x,elevation,y; off-map clamping
accounts for that mapping.

Protected build/reports-recenter-panel-live-20261001-071801 opens through the
factory and clicks report78288 in Free, DF and Isometric modes: stored tile
(131,71,165), camera(131.5,166,71.5), elevation165, distance80 unchanged, panel closed
and input released. Owned DF5896 closed at frame0 with unchanged clone hashes.
build/qa/reports-camera-modes passes panel, camera-mode and walk-camera tests;
build/reports-camera-modes-gpu verifies panel recenter after Walk exits to all
three modes and unequal-dimension off-map clamps with the actual GPU camera.
GPU/live diagnostics contain only known engine signatures. HUD hiding remains
covered by build/qa/reports-hidden-factory. Target highlights, live-terrain Walk
recenter and ordinary main-scene launcher promotion remain unaccepted; see
fixtures/reports/recenter.json.

Reports unit-log controls (2026-10-01): native072011/072115 captures primary-only,
secondary-only and paired recenter targets. Secondary-only occupies the right slot;
paired targets use local x856/880. Native secondary click closes Reports and
recenters on its stored140,80,165. Native072431 adds speaker-only, speaker with one
position, and speaker with both positions. The magnifier sits immediately left
of available recenter targets (x880/856/832 respectively). Its click closes Reports,
recenters on current creature132,70,165 (different from report125,50,165), and opens
ViewSheets/UNIT/Overview. Back returns to Default, not Reports.

ReportsView now renders these controls from native art. State validates the row's speaker ID; the factory resolves the current entity before
closing Reports, then focuses it and opens the existing inspector. build/qa/reports-speaker-route passes
panel/camera routing with an injected inspector destination. GPU
build/reports-speaker-gpu verifies secondary/speaker viewport clicks and all six
control layouts with zero differing pixels over864,112..936,328. Diagnostics
contain only known engine signatures. Native DF54208 closed at frame0 with clone
hashes unchanged. fixtures/reports/log_controls.json keeps synthetic copy test-only.
Speaker tooltip presentation and target highlighting remain open. The native hover probe is
inconclusive; no substitute tooltip wording was authored.

Protected build/reports-speaker-live-20261001-073355 verifies the real Reports
pointer -> factory -> inspector path with complete creature2905 data (25 sections),
current tile132,70,165, and Escape returning to the map. Native073209 shows the
magnifier remains visible for missing speaker2000000000 but clicking leaves
Reports open. The viewer now resolves before closing; the same live run verifies
that missing-speaker no-op. QA reports-speaker-missing covers the regression.
Owned DF52600 and native35268 closed at frame0 with clone hashes unchanged; known
engine diagnostics only. Early072815 is routing-only (loading shell), and072906/
073028 failed because the standalone harness omitted resident/session updates;
none is treated as populated-Overview acceptance. The corrected harness executes
both normal updates. Full creature-sheet visual parity and ordinary main-scene
Reports promotion are separate outstanding scopes.

Reports ordinary-tab scrolling (2026-10-01): protected native073547/073631 probes
All with20 rows/15 visible from row2. Arrows, PageUp/PageDown and wheel/Shift-wheel
over both body and scrollbar leave row2 unchanged. This differs from the unit
lists. Reports scrollbar wheel handling is now enabled only for Combat/Sparring/
Hunting lists, matching the existing unit-log no-op. GPU
build/reports-tab-input-gpu-verified verifies All no-ops plus existing unit-list
wheel and pointer controls, with only known engine diagnostics. The initial GPU
attempt failed a later recenter after an incomplete synthetic input sequence;
the corrected sequence releases keys/wheel and moves the pointer before clicking.
Native DF34432 closed at frame0 with clone hashes unchanged. Evidence and exact
sample scope are in fixtures/reports/scrolling.json; named-tab/held-input cases
remain separate from this All capture.

Reports category row colors (2026-10-01): protected074522 selects Combat, Sparring
and Hunting through native tab clicks. Combat uses LRED, Sparring LCYAN, Hunting
LGREEN. The renderer previously used Combat orange for all three; it now resolves
indices12/11/10 from the installed palette. Hunting evidence uses one existing
report reference added to unit2905's hunting log in the disposable clone. GPU
build/reports-unit-palette-gpu compares15 Combat,11 Sparring and1 Hunting row,
including text/buttons, with zero differing pixels in all three regions. Known
engine diagnostics only; native DF33984 closed/frame0/save unchanged. Fixture
reports/unit_rows.json.category_rendering records the evidence and palette mapping.

Ordinary Reports snapshot lifetime (2026-10-01): native074957 keeps All20 rows and
scroll2 across an appended report and a JobFailures/All tab round-trip. Closing and
reopening produces21 rows at scroll0; removing the appended source report then
leaves the open21-row list intact. Thus automatic ordinary-tab refresh would be a
native departure. Reports state now caches loaded ordinary-tab rows/cursors/scroll
until close, with explicit cancellation when restoring a tab; offline state,
controller and panel checks pass in reports-tab-retention/retention-owner.
Whole-open snapshot parity is still incomplete: never-visited tabs and unloaded
pages read current bridge state. A consistent semantic snapshot contract and live
viewer mutation acceptance are required before promotion. Native DF16400 closed
at frame0 with verified clone unchanged. See scrolling.json. Scratch completion
requirements are consolidated in build/notes/pm/REPORTS_ACCEPTANCE.md.

### Reports ordinary-tab snapshot (management 44)

Native evidence in `fixtures/reports/scrolling.json` establishes a snapshot for the
whole open Reports screen. The Reports helper now captures pointer-free rows for
all 22 ordinary tabs at a safe point. A zero `expected_list_revision` opens/replaces
it; later tab/page reads require its positive revision. Fresh UnitList/UnitLog
metadata reads use a separate reader. Epoch/bridge reset releases the helper;
failed captures preserve the prior snapshot. Retained data is bounded by 65536
source entries and a 32 MiB accounted payload budget (text bytes plus 512 per row,
not a measurement of actual Lua allocation). Replies retain 64-row/128KiB limits.

The viewer keeps the tab revision separate from UnitList revisions and retains
visited-tab scroll positions. Reopening on a unit tab first captures the ordinary
snapshot. Missing/foreign snapshot receipts are rejected. Management 44 requires
bridge/viewer rebuild together; session 10 is unchanged. Older captures must not be
assigned invented snapshot revisions.

Verification: root CTest 19/19 and targeted contracts/controller tests passed in
`build/qa/reports-snapshot-final` and `reports-snapshot-envelope`. Protected live
`build/reports-snapshot-live-20261001-081012` retained 170 rows across source text
change/removal/append, unloaded-page reads and first visit to Job failures after a
unit-list read; reopening refreshed the snapshot. DF 30244 stayed paused at frame 0,
closed without saving, and the clone manifest was unchanged. Result is
passed_with_known_issues for the documented three Godot diagnostics. This is
controller/transport acceptance, not main-scene or complete Reports acceptance;
Reports remains hidden. Working requirements are in `build/notes/pm/REPORTS_ACCEPTANCE.md`.

### Alert Entries text and copy evidence

`fixtures/reports/alert_entries.json.long_text_capture` records native and compiled
transport acceptance for a 6,408-byte report. Native scrolling exposes the final
text and `x3` for repeat_count 2. Entries now divides its existing 128 KiB text
budget across requested references, up to the common 16 KiB row limit, instead
of always cutting at 2,048 bytes. Singleton requests preserve the captured text;
64 duplicate references remain ordered, with incomplete prefixes. This stays
within management44 validators and requires no wire revision change. A popup
must resolve incomplete rows; texts above16KiB still require bounded retrieval.
Neither is complete merely because the prefix transport is accepted.

The category rail no longer generates enum-derived tooltips, counts, instructions
or missing-icon text. Native e7 records no hover on these icons; the red ALERT
button is distinct. Rail and Reports remain hidden. Targeted Entries/adapter/HUD
checks passed in `build/qa/alert-native-text`; protected081733 ended at frame0,
DF49296 closed and clone unchanged, with only the three documented Godot diagnostics.
This proves transport text preservation in the captured range, not popup UI parity.

### Alert Entries data ownership

`alert_entries_state.gd` and `alert_entries_controller.gd` stage ordered Entries
reads through the shared semantic action service. Reports precede unit references;
duplicates remain distinct rows. Incomplete bulk report rows trigger one singleton
read per identity, replacing all duplicates with the same resolved value. Missing
identities are omitted. Receipt order/identity, token and epoch are checked, and
closing detaches queued/sent observers. Loaded data and complete data are separate:
partial source references or still-incomplete singleton text cannot claim a full
popup. These states are internal and supply no invented visible copy.

`build/qa/alert-entries-owner` verifies paging, resolution, missing references,
receipt rejection, close/late replies and epoch changes. Protected live
`build/alert-entries-owner-live-20261001-082305` resolves64 duplicate6,408-byte
reports using exactly two management reads through the real controller/service.
DF47976 stayed paused at frame0, closed without saving, and the clone was unchanged;
only the three documented Godot diagnostics occurred. Popup rendering/navigation,
main-scene routing, text beyond16KiB, full groups beyond session reference caps,
and mutation during opening remain unaccepted. No alert exposure is enabled.

### Native alert popup rendering (captured scope)

`alert_entries_view.gd` renders the captured 1200x800 native popup using
`HOVER_RECTANGLE`, interface scrollbar sprites, installed font and palette. This
is distinct from Reports' standalone sheets. The body wraps at80 columns with29
visible12px lines; short entries are centered in at least three lines. Captured
native headers, repeat suffixes and icon positions are preserved. No main-scene
route or alert exposure is enabled yet.

Registered GPU `alert_popup_capture` checks rendering and pointer behavior.
`build/qa/alert-popup-track-fixed/comparison.json` records zero differing pixels
across complete top/bottom/mixed popup regions. Protected live
`build/alert-popup-view-live-20261001-084017` uses real controller data and scrollbar
clicks; both complete top/bottom panels match native exactly. DF14788 remained at
frame0, closed without saving and the clone manifest was unchanged. Both runs are
passed_with_known_issues for the documented three Godot diagnostics. An earlier
25-pixel hover mismatch was reproduced: captured motion after a drag reached the
scrollbar outside its local bounds. Its hover state now clears in both input paths.

These checks do not accept unit-log/history navigation, broader keyboard/wheel/
outside-click/resize behavior, partial-row controls, oversized text/reference
retrieval, opening-time mutation or main-scene lifecycle. Those remain required
before promotion; fixtures/reports/alert_entries.json carries the evidence limits.

### Alert popup unit/history navigation

`alert_popup_panel.gd` owns the staged alerts factory route and local host focus.
Groups must match the current fortress epoch. Its controller pages unit logs
oldest-first, retains the parent group, and cancels outstanding work on Back or
session changes. Popup Escape/right-click return from a unit log to the group;
Back from the group closes it. Header navigation closes the popup before opening
Reports. This differs from full Reports unit logs, which open at the bottom and
close the full screen on Back. Native unit text is inert; its magnifier opens the
log. Partial final rows omit controls that cannot fit their full36px height.

`build/qa/alert-popup-navigation-boundary` covers data ordering, cancellation,
epoch/overlay/play guards, host handoff and the partial-row boundary. Protected
`build/alert-popup-navigation-live-20261001-085108` exercises the real factory,
host, service, controller and renderer:838 retained unit reports open at line0,
Back restores the group, header opens Reports, and Reports Back releases the map.
Group/unit/back panel regions match native with zero differing pixels. DF36088
remained at frame0, closed without saving and left the clone unchanged. The run
has only the three documented Godot diagnostics. This is composed-factory
acceptance; ordinary main-scene lifecycle, live log refresh, maximum-size memory
budgets, full reference/text retrieval, and broader input/resize behavior remain
incomplete. The Reports launcher and notification rail remain hidden.

### Reports full-text transport (management 45)

ReportInspect Text (view5) captures one native report as a pointer-free UTF-8
snapshot. Request id identifies the report; cursor is a UTF-8 byte offset.
Expected_list_revision zero with cursor zero captures a new value; nonzero
revision reads the retained value without consulting native report pointers.
The Text owner is independent of the ordinary Tab and UnitList snapshots and
is discarded with the Reports helper on epoch/bridge reset.

Replies contain one report row, list_revision, total UTF-8 bytes and next_cursor
(zero at the end). Each chunk is at most16384 bytes and ends on a codepoint
boundary. text_complete is true only if that page contains the entire report;
a terminal suffix is not itself a complete row. Consumers must assemble and
validate identity, revision, offsets and total before publishing a complete row.
Raw/converted text each have a32MiB storage bound; rejection does not authorize
invented UI copy or truncation presented as complete. Missing initial identities
reject; existing retained text remains available after native expiry. Failed
captures leave the preceding handle intact.

This changes the management region to v45; rebuild bridge and viewer together.
Session remains10. No migration can infer missing text from a v44 prefix.
The popup now escalates incomplete singleton Entries to Text, validates every
page's identity/revision/byte offset/total and metadata, and publishes only the
fully assembled value. Duplicate references receive the same resolved text.
Back, close, rejection and epoch change discard the partial buffer.

Protected091111 retrieved40628 native bytes and matched complete popup top/bottom
regions with zero differing pixels. Protected091239 changed native text/repeats
between pages: continuations retained the original value, recapture observed the
edit, and the superseded revision rejected. Both owned clones stayed unchanged at
frame0. Evidence/limits are in fixtures/reports/alert_entries.json. The owner/panel
lifecycle checks pass; renderer checks have only documented Godot diagnostics.
This accepts per-report popup text paging, not aggregate memory bounds, complete
alert-reference retrieval, multi-report opening coherence or ordinary Reports
full-text rendering.

### Ordinary Reports long-text overdraw

Protected092109 demonstrates112-column wrapping and text continuing past the
nominal row height and bottom border. The previous two-line rendering cutoff and
110-column width were defects. reports_view now draws all available wrapped
ordinary-row text; glyphs may overlap the border, but background fill stops at the
panel interior. Date cells still overwrite the second line. Clicking report prose
is inert in this capture. The944x708 panel matches native with zero differing pixels.
See fixtures/reports/scrolling.json.ordinary_long_text_overdraw for provenance,
failed intermediate comparisons and limits. This does not accept unit-log long
text, arbitrary viewport sizes, Unicode beyond the mapped prefix, overlapping
long rows, or snapshot-safe full-text retrieval for the Reports screen.

### Unit-log long-text overdraw

Protected092727 independently establishes108-column report text wrapping in
Reports unit logs. The header still uses110 columns. Native log text continues
past its nominal three-line row and the panel border; reports_view now does too,
with background fill confined to the interior. The944x696 panel matches native
with zero differing pixels. The fixture adds a40628byte synthetic report to
unit998's Combat log; its visible ASCII prefix fits the mapped16KiB row.
See scrolling.json.unit_log_long_text_overdraw for provenance and limitations.

This capture explicitly switches native pause-on-new from true to false through
its UI, matching the viewer's local test state. It does not resolve the previously
observed variation in native initialization/persistence. No native widget is a
runtime input. Running pause effects, multiple overlapping long rows, Unicode
and arbitrary viewport full-text delivery remain unaccepted. State/controller/
panel regressions pass; protected GPU diagnostics are the documented three only.

### Native pause-on-new initialization anomaly

Protected093004/093117 disproves a simple Combat-versus-Sparring default rule.
With identical unit/category and no user toggle, reopening changes the native
flag. Read-only oracle inspection at the declared bool field finds raw values
110,32,105 as well as0/1; actual toggle input writes canonical0/1. This is consistent
with uninitialized/reused widget storage, but the constructor mechanism is not
proven. See fixtures/reports/pause_on_new.json.initialization_probe for exact
observations and source/save ownership. Both captures stayed at frame0 with the
owned source unchanged and DF closed.

This evidence does not authorize runtime widget reads or heap-dependent behavior.
The maintainer subsequently accepted deterministic initial false with session
persistence on 2026-10-02. This supersedes the earlier initialization-policy gate,
without asserting proven native parity. Explicit toggling is live verified, and
Reports is exposed in RC2. Do not reopen this native anomaly as a release blocker.

### Full text owned by the ordinary Reports snapshot (management 46)

Ordinary tab capture retains full UTF-8 text with each pointer-free row. Its
existing32MiB accounted payload limit now includes full text, rather than only
wire prefixes. Tab pages still return <=16KiB per row and128KiB aggregate text,
with text_complete=false where a retained row needs paging.

Text view with tab1..22 reads the existing tab snapshot and requires its positive
expected_list_revision; it never recaptures from native data. The report must
belong to that tab. Byte cursors and completion flags match Text semantics from
management45. Text tab0 remains the independent per-report snapshot used by
popups. These owners cannot retire each other. Failed tab captures preserve the
previous snapshot; reset/replacement invalidates its text handles.

Management46 requires rebuilding both peers, and session stays10. The prior
protocol rejects the new tab selector; no migration invents missing bytes.
Protected093932 retrieves40628original bytes across native text/repeat edits,
then proves that recapture sees the edit and the old revision rejects. Native
simulation stayed at frame0, source save unchanged, owned DF closed. Offline
core/contracts/Lua checks pass. scrolling.json.ordinary_tab_full_text records the
scope: main Reports client assembly is covered below; unit-log retention, arbitrary
viewport/Unicode and aggregate-memory acceptance remain separate.

### Ordinary Reports full-text page assembly

reports_state stages an ordinary Tab reply containing incomplete rows and resolves
those rows through Text with the same tab/revision. report_text_assembly checks
identity, metadata, original UTF-8 prefix, cursor progression, total length and
completion flags. A complete page is published together; an existing displayed
page remains until append resolution finishes. Resolved rows stay in the tab
cache. Close, tab change, epoch replacement and rejection release staged bytes;
late replies cannot publish them. Unit-tab snapshot bootstrap does not retrieve
unused ordinary text.

Protected094442 exercises the real service/controller/state and obtains40628bytes
with text_complete=true at tabrevision1. The installed-art944x708 panel matches
native with zero differing pixels. Frame0, source save unchanged, owned DF closed;
only documented renderer diagnostics. reports_text_test covers two long rows,
UTF-8 boundaries, metadata/revision/prefix errors, atomic append, cached tab reuse,
cancellation and bootstrap. State/controller/panel regressions also pass. See
scrolling.json.ordinary_tab_full_text.client_assembly. This does not establish
unit-log retained text, arbitrary viewport/Unicode rendering, maximum-memory
behavior or ordinary main-scene lifecycle acceptance.

### Long-report wrapping work

The previous wrapper repeatedly copied the full remaining suffix. Isolated
profiling measured roughly11.5seconds for1MiB versus2ms for40KiB. The replacement
uses bounded line windows and offsets; the same1MiB workload measured about4ms.
These are diagnostics, not portable acceptance thresholds.

Reports passes a line limit based on the row's global position and viewport edge.
Text may still overdraw the panel border, as native does; only lines below the
viewport are omitted. Popups retain complete wrapping for scrollbar content.
Optional work counters are off by default. reports_wrap_test verifies identical
legacy output for bounded samples, Unicode/hard-word boundaries and full popup
content; a55-line112-column demand scans6160 characters and copies at most12320,
independent of the unread suffix size. This guards work counts rather than timing.

Protected095026/095104 confirm ordinary/unit-log panel regions still match native
with zero differing pixels, frame0 and unchanged source saves. Exact sources and
profile data are in scrolling.json.wrapping_work. Maximum aggregate popup/log
memory, multi-row overlap, arbitrary resized layout and unit-log full-text
transport remain separate acceptance work.

### Retained unit-log protocol (management 47)

UnitLog revision zero captures a pointer-free history with full UTF-8 rows. A
positive expected_list_revision reads that retained history. Explicit refresh
requires a positive revision and forward cursor; on a raw source-length change it
appends newer identities while preserving existing text/metadata and expired rows.
Same-length replacement alone does not refresh. Failed capture/refresh leaves the
previous value intact. Retained rows are bounded at65536 and32MiB accounted payload.

Text with tab0 plus unit_id/unit_category and the log revision reads full text from
that unit-log owner. Text without a unit still uses the independent popup owner;
ordinary tab Text remains separate. UnitLog replies require list_revision>0.
Epoch/bridge reset releases the owner. Row/history values do not consult native
objects on retained reads; the adapter's existing fresh tab-count metadata is
independent. Management47 adds the refresh request field, requiring both peers to
rebuild; session remains10. Older replies cannot acquire an invented revision.

Protected100551 verifies40628 retained bytes, source mutation, explicit append,
unchanged historical text after refresh, recapture observing edits, and rejection
of the superseded revision. Frame0/source save unchanged/owned DF closed; known
renderer diagnostics only. Core/contracts/Lua checks pass. Evidence is in
scrolling.json.unit_log_retained_transport. Client acceptance follows below;
this protocol capture alone does not establish wider screen completion.

### Retained unit-log clients

Both Reports and alert popup clients retain the positive UnitLog revision across
history pages. Incomplete unit-log rows resolve through Text with the same unit,
category and revision, preserving text and metadata from the original capture.
Reports marks live append requests explicitly with refresh=true. Popup unit logs
use the retained owner directly, without recapturing through singleton Entries.
Publication waits for complete text; close, Back and session replacement discard
partial buffers. Revisions and selectors are checked before accepting receipts.

Protected101434/101507 changed native text/repeats during actual client assembly;
both retained all40628 original bytes. Reports appended the new identity without
replacing historical text; popup Back restored its parent. Protected101554 also
verifies complete text in Reports and a944x696 native panel comparison with zero
differing pixels. All three owned sessions stayed at frame0, closed without saving
and preserved their source save. Diagnostics are the documented three only.
Six targeted client checks and popup owner-boundary follow-up pass. Provenance
and limitations are in scrolling.json.unit_log_retained_transport.client_assembly.
Partial-history mutation/expiration, popup automatic refresh, maximum memory,
main-scene lifecycle, wider input/resize and Unicode rendering remain incomplete.


### Multi-page retained unit history

Protected101942/102025 exercise both real clients with150 captured rows. After
the first page, native data changes two texts, removes one unit-log reference,
expires another report from the report vector and appends three reports. Later
pages and a43218-byte long row preserve every original value. Reports refresh
extends retained history to153 rows; reopening either client captures151 current
rows, including both edits and excluding the two missing source rows.

Both owned sessions stayed paused at frame0, closed without saving and preserved
the source save. Only the documented renderer diagnostics occurred. See
scrolling.json.unit_log_retained_transport.history_mutation_clients. This accepts
controlled in-memory expiration across client pages; naturally timed running
expiration, main-scene lifecycle, aggregate memory and wider rendering remain
separate requirements.


### Alert popup log lifetime differs from Reports

Protected102152 opens native unit998 Combat through the alert popup, then changes
text, removes a reference and appends reports (both unchanged and increased source
length). Open popup identities/text stay fixed; full752x420 panel comparison is
zero differing pixels after both mutations. Back/reopen captures the new source.
See alert_entries.json.unit_log_open_lifetime. Native DF36904 stayed paused at
frame0, closed without saving and preserved the source save.

Do not add standalone Reports metadata polling or automatic append behavior to
this popup on the basis of earlier pending-work notes. Its retained snapshot and
fresh capture on reopening match this native evidence. Running-simulation popup
behavior, other categories and broader lifecycle remain unverified.


### Complete alert-group protocol (management48)

Group view6 reads one native notification category, or the distinct red ALERT
source with alert_button=true and no category. Revision zero captures all current
contents at one safe point; positive revisions page the retained snapshot. Native
vectors never supply continuation pages. Duplicates/order are retained, missing
references omitted, and full text/unit captions captured together. Text view5 with
the same group selector and revision reads that owner's full text. Group, tab,
unit-log and independent Text owners are distinct; selectors cannot be mixed.

Pages contain up to64 total entries and128KiB report prefixes. Text pages contain
up to16KiB UTF-8 bytes. Failed captures preserve the preceding owner; replacement
and reset invalidate old handles. Group storage is bounded at65536 combined
source references and32MiB accounted payload: unique report text plus512 bytes
per report, unit strings plus512 bytes per unit/category, and16 bytes per retained
reference. This accounting is not a measurement of actual Lua/client heap size.
Management48 requires both peers rebuilt; session remains10.

Protected103937 matched301 native report rows and2 unit rows across duplicates
and missing references. Source mutation between pages did not alter retained
text or identities. Fresh capture saw edits, red ALERT used its separate source,
and stale revision rejected. The first live103707 exposed an old Lua envelope
view bound; that guard and selector type/range checks were corrected and tested.
Both owned sessions closed at frame0 without saving and preserved the source.
The successful run has only documented renderer diagnostics. Core19/19, Godot
request contracts, group/adapter tests and Lua envelope regression passed. Exact
text length and evidence are in alert_entries.json.complete_group_transport.

The popup client migration is accepted below. Maximum aggregate memory, ordinary
main-scene lifecycle and broader rendering remain separate requirements; no
exposure is enabled.

### Complete alert-group client

Category opens now read Group even when the session summary says complete. The
summary identifies the source; it does not define the open snapshot's contents.
The client validates selector/revision, exact cursor progress, stable total and
report-before-unit ordering. Incomplete text resolves with the retained group
owner, preserving duplicates without recapturing individual native reports.
Red ALERT uses its separate source selector. Explicit Entries requests remain
available as a separate reference API. Group and unit-log revisions are distinct;
Back restores the fully retained parent without a new group read. Close, epoch
change and rejection discard partial text. No new visible copy is introduced.

Protected104453 opens a real303-entry native group through the composed fortress
factory using its capped256-reference session summary. Source edits, reference
removal, report expiration and append occur during paging; every original row
and full39616-byte text remain intact. Unit navigation/Back preserves the parent.
Complete752x420 open and restored panels match native with zero differing pixels.
The separate red ALERT data selector returns its own source. DF51304 stayed at
frame0, closed without saving and preserved the source save; only documented
renderer diagnostics. Client and category-route lifecycle checks pass. See
alert_entries.json.complete_group_transport.client_assembly. Main-scene workflow,
red ALERT launcher, maximum aggregate memory and broader input/resize/Unicode
remain unaccepted; Reports and the notification rail stay hidden.


### Compact popup line layout

alert_text_layout indexes entry heights and packed character spans instead of
allocating a Dictionary/String for every wrapped line of every reference. Each
unique immutable text/repeat value wraps once; duplicate rows share the layout.
Visible lines are located by binary search and materialized on demand. Resolved
client rows remain immutable and shared across duplicate references and parent
navigation. Closing clears the renderer's retained index. Native spacing, repeat
suffixes, trailing spaces, blank padding and partial-entry controls are preserved.

The deterministic boundary check uses65536 references to one32505344-byte report,
exactly the group helper's32MiB accounted limit including metadata/references.
Its26628390912 logical lines require406317 packed spans (3250536 bytes) and65536
64-bit entry ends (524288 bytes), plus entry/source/engine storage. These counts
are not a total heap measurement. Mixed text/repeat samples compare every logical
line against the previous wrapper, including Unicode and newline characters.

Protected105158 repeats the actual303-entry client workflow with zero differing
pixels for open/back native panels; source save unchanged, paused frame0, DF37820
closed, known renderer diagnostics only. GPU top/bottom/mixed images also match
the previously accepted native baseline with zero differing pixels. Layout, owner
and panel checks pass. See alert_entries.json.compact_popup_layout. Maximum-size
transport/aggregate client heap, simultaneous retained owners, arbitrary viewport
and native Unicode glyph behavior remain separate acceptance work.


### Initial unit-log read recovery

Reports retains an initial read demand until the first full UnitLog page has
committed, including required Text pages. The existing0.5-second controller poll
retries that read after rejection. Before capture it requests a new snapshot;
after capture it keeps the acquired log revision and rereads the original tail
page. Retries are not refresh appends and do not emit pause commands. Empty logs
complete normally. Close/session changes clear the demand and detach queued work.

Protected105801 injects real bridge rejections for the initial UnitLog and later
Text continuation through a scratch transport wrapper. Production controller/state
recover all40628 bytes on revision1; the final944x696 panel matches native with
zero differing pixels. DF33456 stayed at frame0, closed without saving and left
the source unchanged; only known renderer diagnostics. State/text/controller/panel
regressions pass. See scrolling.json.initial_unit_log_read_recovery. The earlier
105655 harness accidentally targeted ordinary Tab Text and is failed evidence,
not acceptance. General recovery below supersedes the initial-only scope.
No visible error copy was added.


### Reports and alert read-failure recovery

Reports retains the failed read request, assembly mode and requested navigation
position. A Text failure restarts its enclosing page with the already captured
revision. UnitList continuation also validates the expected list revision. Alert
popups retry the unadvanced Group/UnitLog/Entries cursor; independent Text retries
from byte zero using its captured descriptor. Both controllers retry outstanding
read demand at 0.5-second intervals. Successful ordinary tabs and alert popups do
not poll for changes. Close, epoch changes and superseding navigation cancel the
demand; retries never replay pause or mutation commands. A permanently retired
snapshot is not silently replaced with a new capture.

Protected110438 injects real bridge rejections during ordinary Tab Text, initial
UnitLog and UnitLog Text; all40628 bytes recover and the native panel differs by
zero pixels. Protected110829 injects initial Group, continuation and Text failures
through the actual fortress popup factory; all303 original entries and39616-byte
text survive source mutation, unit navigation and Back. Popup open/Back panels
match native with zero differing pixels. Both owned DF processes closed without
saving, stayed at frame0 and preserved the source; known renderer diagnostics
only. Six state/controller/text/panel checks pass in report-read-recovery-covered.
See fixtures/reports/{scrolling,alert_entries}.json read_failure_recovery.

UnitList and later-history retries have offline regressions, not fault-injected
live coverage in these captures. Main-scene disconnect/reconnect and late replies,
retired owners, running pause behavior, maximum transport/aggregate heap and broad
input/viewport parity remain separate acceptance requirements.

Initial Tab reads that fail, including their Text assembly, are not eligible for
per-tab caching. Scrolling cannot discard that initial demand; switching away
cancels it and switching back requests the retained tab again. Successfully
committed content still restores from cache. The navigation regression covers
both page rejection and Text rejection, plus successful later cache restoration;
Reports state/text/controller checks pass in reports-recovery-navigation. This is
offline recovery coverage, not an additional native visual acceptance claim.


Recovery lifecycle regression checks integrate the actual semantic service with
both Reports and alert controllers. Timeout queues a retry behind the undrained
read; its late receipt cannot publish through the retired observer. Transport
loss, world epoch changes and model generation changes close the owner and cancel
queued recovery. reports-recovery-lifecycle passes all three selected checks.

Protected111352 uses the actual fortress popup factory and real bridge with a
scratch wrapper withholding an actual receipt. Closing after timeout cancels the
queued retry, releases modal input and prevents publication of the late receipt;
a fresh open loads302 current entries. DF47408 stayed at frame0, closed without
saving and preserved the source; known renderer diagnostics only. This accepts
that timeout/close/reopen path, not real disconnect or the complete main-scene
lifecycle. See alert_entries.json.read_failure_recovery.live_timeout_close.


Protected111601 verifies native popup Back preserves the parent group's scroll
position:30 short reports followed by unit998, track clicks to bottom, opening
the unit log at its top and Back. Native parent panels before/after differ by
zero pixels. Legacy scroll_position_alert stays0 and is not a valid current
scroll oracle. DF38460closed/frame0/source unchanged. The viewer now captures
parent position when unit navigation starts, preserving it even if Back occurs
before the first unit-log receipt. Both interrupted and completed navigation,
plus close reset, pass popup panel regression; entries and GPU capture also pass
(the GPU run has documented known renderer diagnostics). Long-parent viewer vs
native pixel comparison and broader input/viewport coverage remain separate.
See alert_entries.json.parent_scroll_restoration.


Protected111845 exercises the long parent through the real client factory and
pointer inputs:31entries, firstline64, unit firstline0, completed and interrupted
Back both restore64. Native panel comparisons for open/unit/Back/interruptedBack
are0pixels. Its25-pixel bottom jewel mismatch was later resolved as differing
pointer states:112345 native readback reports all mouse fields -1 despite posted
window motion. Pointer-matched112452 moves the viewer pointer outside the bar;
all five panels (open/bottom/unit/Back/interruptedBack) match native with0 differing
pixels. DF9276/32644/54792closed/source unchanged; client runs have known renderer
diagnostics only. No production hover change was justified. Persistent native
hover behavior remains unverified. See parent_scroll_restoration for provenance.


Protected112636 establishes parent-popup wheelUp one-line scrolling and
Shift+wheelUp29-line paging at1200x800; standard Up/PageUp commands do nothing.
Outside left closes the parent. Installed interface.txt bindings and hash are in
alert_entries.json.popup_input. Viewer handles wheel across its popup rectangle
under the host input guard and consumes outside-left dismissal. QA panel/entries
pass and GPU passes with known diagnostics. Actual client112916 confirms scroll
positions63/35 from64 and modal-input release; Shiftwheel panel matches native
0pixels. The one-line thumb mismatch was corrected against12 native intermediate
positions in113212: an interior popup thumb cannot touch the bottom endpoint
before the final row. The popup-only override leaves standalone Reports unchanged.
Protected113342 now matches all seven panels (wheel/Shiftwheel plus open/bottom/
unit/Back/interruptedBack) with0pixels; DF13348/50036closed, source unchanged,
known renderer diagnostics only. Native113534/client113650 additionally accept
unit wheelDown over body/header/bar (one line), outside (no scroll), ShiftwheelDown
(one29-line page), and outside-left closing the whole unit popup. All5 region
panels match native0pixels; modal input releases. GPU viewport regression passes
with known diagnostics. DF49188/16852closed/frame0/source unchanged. Resize,
persistent hover and full main-scene workflow remain separate.


Popup resize captures113913/114105 establish a fixed752x420 panel/29-line page
anchored at(32+floor((width mod8)/2),48+floor((height mod12)/2)). The view now
listens for viewport size changes and follows that centered native grid origin.
GPU five-size resize regression and panel check pass with known renderer issues.
Real client114245 matches native panels0pixels at1600x900,1237x805,1238x810 and
1200x800. Native clamps a requested800-wide window to912. At960x600/912x600 the
native minimap occludes upper-right16x144/64x144 pixels; the factory harness lacks
that full HUD composition, so narrow full-panel parity remains unaccepted. All
three owned DF processes closed at frame0 with source unchanged. See
alert_entries.json.resize_acceptance. Other scale settings, persistent hover and
full main-scene lifecycle remain separate requirements.


### Fortress management startup claim and full-scene reconnect

The fortress composition enables startup/session bootstrap on its shared semantic
service. The management client requires its own successful Catalog receipt before
any other request; the prior main-scene setup omitted it, causing repeated
not_sent reads. Catalog is now queued before ordinary requests when a live epoch
is available, and required again after epoch/generation/transport invalidation.
Failed claims wait0.5seconds before retry; mutations are never replayed. Existing
explicit-claim service users retain their configuration. Service/Reports claim
ordering/rejection/session tests and UI composition pass in
main-scene-management-claim-covered.

Protected115136 instantiates the real main scene without a manual harness claim:
loader/terrain readiness, staged31-entry popup, resize, actual client detach and
automatic reattach, stale owner remains closed, fresh open and input release all
pass. Native popup open/restored/reopened panels differ0pixels. DF40072 remained
paused at frame0 after the viewer, closed without saving and preserved source;
known renderer diagnostics only. Initial114637/114812 failures are retained as
failed evidence. At960x600 native minimap overlaps the popup by16x144pixels while
the viewer minimap stays behind it; full HUD parity remains unfinished. This run
does not accept a visible notification launcher, producer restart/different-world
load, or full HUD/loader copy/layout. See alert_entries.json.main_scene_lifecycle.


### HUD copy containment and remaining source audit

Minimap/elevation instruction tooltips without native provenance were removed;
the shared button factory's +/- tooltips are explicitly cleared. Missing native
fortress name/population/stress/elevation metadata leaves values blank rather than
substituting a generic name, dash counts or raw model-Z Level caption. Actual
transported native values remain. HUD/minimap/UI composition checks pass in
hud-unsourced-copy-contained. This is source/offline containment, not native
hover behavior or full HUD visual acceptance.

Tile hover still synthesizes descriptions from enum/material identifiers, and its
synthetic formatting tests do not establish native copy. Native description
transport/mapping remains required. Loader copy/layout, remaining HUD tooltip/
feedback/settings prose and the missing-resident readout message also need source
audits. No agent-authored spec or approval authorizes those departures. Detailed
working inventory remains in build/notes/pm/COPY-PARITY-AUDIT.md.


Tile-hover prototype exposure is now disabled through
ui_availability.TILE_HOVER_AVAILABLE: the current tile_hover_info contract exposes
enum/material tokens and semantic flags, not native descriptions. Main composition
does not instantiate the generated-copy prototype. Its formatting tests remain
explicitly synthetic and are not native-copy acceptance. Composition/HUD/prototype
checks pass in tile-hover-native-copy-gate. Tile semantics and picking remain.
This is unfinished containment; completion requires actual native description
capture and semantic/native-string transport or exact evidenced mapping, covering
shapes/materials/smooth/engraved/liquid/plants/hidden/unknown states. Native widget
or cursor state must never become runtime input. Restore exposure only after the
semantic, lifecycle and rendered behavior is accepted.


### Staged red ALERT launcher

The HUD now owns a distinct red ALERT launcher under the unchanged Reports
availability gate. It uses installed SIEGE_LIGHT artwork (3x3 tiles expanded7x3),
verbatim native ALERT glyphs/palette6+bright, and emits alert_button=true with the
current fortress epoch into the existing popup route. Its visibility uses the
session's authoritative report_count, not the capped reference list. Opening or
Back does not clear native references. Native120347 supplies label/art/click
provenance; actual client120737 verifies separate group selection and Back with
popup0pixels and1980 opaque launcher pixels0differences (36transparent background
pixels excluded). Both owned DF processes closed with source unchanged. UI/HUD
checks pass and GPU/live runs have only known renderer diagnostics. Native
hover/tooltip, acknowledgement/right-dismiss, full HUD layout/scaling and global
launcher exposure remain unfinished. See alert_entries.json.red_alert_launcher.

## Native red ALERT dismissal contract (2026-10-01)

Protected native121354 (DF24664) and121444 (DF57588) establish right-click
on red ALERT clears its entire alert_button_announcement_id vector, including
multiple report IDs, duplicate IDs and expired references. Repeated right-click
leaves the empty vector empty. Both preserve the exact302 category references,
3300 global report count and paused frame0. Owned processes closed and source
clone manifests unchanged. fixtures/reports/alert_entries.json records evidence.
This does not establish unchanged report fields/flags or all native state.

Red-button dismissal clears red references without deleting report/category
records. Retired Session AcknowledgeAnnouncement and legacy Alert/Dismiss are
not semantic red-button dismissal endpoints. Use the receipt-based actions below;
unknown mutation outcomes must not replay.

## Red ALERT semantic dismissal helper (2026-10-01)

Native121628 expands the oracle to all3300 report records (all named XML fields),
announcement IDs/order, every category report/unit reference, status flags and next
report ID. All remain identical after right-click and repeated click; only the red
reference vector clears. Raw report strings were compared byte-preservingly via
Latin-1 JSON decoding, not decoded as UTF-8 or used as product copy.

`bridge/plugin/report_alert_dismiss.lua` captures pointer-free ordered
IDs under a receipt, validates the exact source before resize(0), consumes mutation
receipts, rejects stale/replayed requests, and resets ownership without reusing
receipts. Outer caller must validate fortress epoch and command ownership. At the
native safe point it touches no report/category/widget API. The65536-reference
limit matches group retention. `report_dismissal.lua` supplies the protocol wrapper.

QA report-alert-dismiss-helper passes deterministic duplicate/expired/zero-ID,
empty, append/remove/reorder/same-length replacement, reset, old receipt and cap
cases. Protected helper-live121843 reproduces native effects with all captured
state unchanged; native/helper launcher crop comparisons are recorded in fixture
red_alert_native_dismissal.full_effect_followup. DF32576/40992 closed; saves unchanged.

## Red ALERT dismissal protocol49 (2026-10-01)

ManagementAction PrepareAlertDismissal68 (read) and DismissAlert69 (mutation)
were introduced in schema49, with model/Godot contracts, a model request codec,
an extension request/reply path and a bridge helper registry.
Report payload uses flat defaults: expected_list_revision is the consume receipt;
reply list_revision is that receipt and total is captured/cleared reference count.
Strict validation rejects mixed read selectors, missing/invalid receipts and bad
success replies. New v49 region prevents old-peer interpretation; PINS documents
migration. Session10 stays unchanged; retired native UI endpoints remain retired.

report_dismissal.lua owns a separate cached helper and binds preparation to client
identity plus fortress epoch; epoch lifecycle retires the closure. Complete source
IDs stay in the producer; the capped HUD reference list is not a write precondition.
The core helper consumes receipts and rejects changed ordered IDs. Generated policy
classifies only DismissAlert as mutation, preserving unknown-outcome handling.

Verification: red-alert-dismiss-protocol-covered core passes (including real model
request encoding, ID/receipt precision and invalid combinations). Helper/wrapper
checks pass client/epoch rejection and replay behavior. red-alert-dismiss-bridge
compiles pinned MSVC bridge successfully, build-only. Final extension round-trip
red-alert-dismiss-roundtrip-final passes new actions and malformed local requests,
including receipt9007199254740993. Earlier failed QA runs exposed test scaffolding:
Lua vararg invocation, fake producer ordered actions/switch and ordinal-sensitive
legacy expectations. These were corrected; no failed run counts as acceptance.

## Red ALERT right-click end-to-end (2026-10-01)

Installed bridge protocol49 with DF closed (red-alert-dismiss-install.log). Added
red_alert_dismiss_controller.gd and actual launcher -> HUD -> fortress composition
routing. One click prepares then consumes a receipt; duplicate pending clicks are
ignored. Epoch/producer checks and cancellation guard preparation; no automatic
replay, optimistic local removal or authored visible copy. Authoritative session
count controls launcher disappearance. Reports gate remains unchanged.

QA red-alert-dismiss-controller passes controller lifecycle/receipt and composition
checks. Protected123915 (DF55832) actual viewport right-click -> service -> installed
bridge cleared4 red references including duplicate/expired IDs. Left open/Back
preserved them first. Protected124039 (DF34708) injected wrong receipt: native
Rejected preserved4 refs and identical rendered panel; duplicate click suppressed,
no automatic retry. A new explicit click succeeded. Both compare all3300 report
records, announcements, category report/unit refs, flags and next ID unchanged;
paused frame0, save manifests unchanged, owned processes closed. Known3 Godot
shutdown diagnostics only; passed_with_known_issues. Fixture records exact scope.

## Red ALERT stale source and unknown completion (2026-10-01)

Protected124317 (DF2412): withheld real preparation reply, replaced red source ID
78823 with78824 at a native safe point without changing count, then released the
original receipt. Production DismissAlert rejected "Alert references changed";
exact changed vector remained intact, duplicate click stayed suppressed, no replay.
Fresh explicit right-click prepared a new receipt and cleared the vector.

Protected124435 (DF32856): withheld a real successful dismissal receipt from the
service until timeout. Controller observed unknown; service kept the sent request
active and issued no replay. Releasing the late receipt reconciled Ok/count4,
without reviving the controller observer or sending another command. Empty
session source rejected another dismissal. This is controlled receipt withholding,
not a claim of real producer-death/restart coverage.

Both compare all captured report records, announcement/category refs, status flags
and next ID unchanged; red vector cleared only as intended; paused frame0, source
save unchanged, owned processes closed. Known3 GPU shutdown diagnostics only.
Fixture red_alert_native_dismissal.production_stale_and_timeout records evidence.

These controlled dismissal cases do not establish real producer death/restart,
new-world transitions or running-simulation behavior.


## Popup/minimap composition defect (2026-10-01)

Native124838 (DF56428) at960x600: left click(775,100), within both minimap
content and popup rectangle, keeps popup open and moves native window from
(98,60,165) to(-3,94,165). Click(900,100), outside popup but inside map, also
keeps popup open and moves window to(122,94,165). All frame0/source unchanged,
owned process closed. fixtures/reports/alert_entries.json.popup_minimap_input.

Native map content appears above the popup while its frame and elevation
caption stay below. Raising the whole HUD panel would reproduce neither native
layout nor behavior. Map input must preserve the popup without enabling general
world commands through it. The composition and input checks below cover these
separate requirements; layering alone does not establish terrain-color parity.

Removed authored elevation_overview tooltip (instruction/surface-description
prose) without replacement. Existing elevation_overview_test passes in
QA elevation-overview-copy-contained; navigation behavior remains tested. This
is copy containment, not completed native tooltip or minimap acceptance.


## Parent popup/minimap composition correction (2026-10-01)

Implemented native200x216 frame with192-square map content,12px white elevation
caption and native RGB128 uncovered background. Removed visible unsourced numeric
stepper (native elevation overview remains). Frame stays HUD layer1; separate map
content rises to11 only for the captured parent alert popup. Other panels retain
prior ordering. Native helper hover hides frame/map together; HUD scale and entered
state propagate to the separate layer.

ui_host grants a scoped minimap-input opt-in to parent alert popup; unit history
is not extrapolated. Popup _input yields left clicks inside the actual transformed
map rectangle, so map navigation preserves the popup while world commands remain
blocked. HUD state caching tracks this policy, including save/overlay changes.

QA popup-minimap-scoped-layer passes HUD, host, popup owner, composition and minimap;
popup-minimap-native-background passes minimap. Initial geometry test caught theme
application replacing margins; reconfigured after theme apply. Initial live color
comparison caught incorrect palette8 assumption (installed DGRAY160 vs native128),
and caption tint was corrected to native white. Final protected130254 main scene
(DF25548) verifies both native-reference clicks, narrow/restore, detach/reconnect,
fresh reopening31entries and close/release. Caption/frame and background crops
have0 differing pixels; popup has22 remaining pixels from existing 3D footprint
outline (previous mismatch2304). Full minimap algorithm/footprint not accepted.
All owned runs125855/130016/130139/130254 closed/source unchanged/frame0; known3
Godot shutdown diagnostics only. Fixture popup_minimap_input.main_scene_acceptance.


## Unit-popup minimap navigation and wheel priority (2026-10-01)

Native130543/130703 establishes minimap left navigation while unit998 history
stays open. Wheel-down over overlap leaves unit scroll0; after right-click Back,
wheel-up leaves parent scroll64. Right-click again closes the parent. Camera Z
unchanged. This closes the earlier unit-view extrapolation gap. First130449
capture failed on an incorrect oracle field name; owned DF41552 closed/source
unchanged, no acceptance claimed from that attempt.

Extended alert_popup_panel minimap opt-in to both views. alert_entries_view now
yields map left clicks and consumes overlapping map wheel events before popup
scrolling; right-click retains Back. Updated owner test; QA popup-minimap-unit-input
host/composition/popup checks pass. Main-scene130809 actual magnifier -> unit log,
map clicks at775/900, wheel exclusion and right Back to parent64 pass, as do
resize/detach/reconnect/fresh open/close. Unit popup comparison differs only by22
existing camera-footprint pixels. DF41476/9720/43596 closed/frame0/save unchanged;
known3 shutdown diagnostics only. Fixture popup_minimap_input.unit_and_wheel_acceptance.


## Minimap Shift-wheel acceptance; drag probe unresolved (2026-10-01)

Native131059 Shift-wheel at775,100 keeps unit scroll0 and parent scroll64;
right-click Back remains active. Actual main-scene131956 verifies normal and
Shift-wheel exclusion, map navigation, right Back, resize, detach/reconnect,
fresh31-entry reopen and close. DF4264 closed/frame0/source unchanged; only the
three previously classified Godot shutdown diagnostics. No production change
was required. Fixture popup_minimap_input.shift_wheel_acceptance records stages.

Probes131059–131908 did not establish drag behavior. First probes131059/131235 accidentally omitted the held
pseudo key inside gui.simulateInput, which overwrites enabler mouse fields.
Corrected131708/131805/131908 use _MOUSE_L_DOWN but still show no held motion;
the native scrollbar positive control also fails to move. A second discrete
map press navigates normally. Do not interpret this as evidence native drag is
unsupported or change production from this negative result. DF1732/55948/15460
closed/frame0/source unchanged. The press-only correction below uses a working native held-input control.


## Minimap press-only native correction (2026-10-01)

Resolved the earlier inconclusive drag probe. Native132303 repeats the known
full Reports scrollbar held-input control successfully. Native132402 repeats
that control (Combat scroll0,0,5,12,36,58,82,82) in the same session as minimap
sequences in unit history, parent popup and ordinary fortress view. All three:
press800,80 navigates to native window22,74; held900,100/outside700,100/reenter850,100
and release leave that position unchanged; a fresh900,100 press navigates122,94.
The alert-popup scrollbar was an unsuitable positive control; its earlier no-op
results alone did not establish native minimap behavior.

Removed continuous dragging from fortress_minimap.gd. Fresh presses retain all
permission/availability/map-rectangle guards; motion remains consumed. Regression
checks actual viewport held motion, outside/reentry, and a fresh subsequent click.
QA minimap-native-press-only passes. Actual main-scene132538 passes these gestures
in all three views, normal/Shift-wheel exclusion, popup retention, right Back,
resize, detach/reconnect/fresh31-entry reopen and close. Native DF2636 and viewer
lane DF32432 closed/frame0/save unchanged; only three known Godot diagnostics.
Fixture popup_minimap_input.press_only_acceptance contains observations/control.
Intermediate132204 (DF8748) no-render probe stayed inconclusive;132303 (DF50132)
established the working control. Both owned sessions closed/save unchanged.


## Native minimap elevation oracle (2026-10-01)

Native132928 uses actual CURSOR_UP_Z/DOWN_Z inputs and asserts target elevation.
At960x600, map192-square crop changes7108 pixels atz164,7374 at166 and7407 at155
relative to165. The native map is selected-elevation dependent. Colors in this
sample include RGB128 background,192/64 grays,200/140/0 ochre,0/24/192 blue,
100/224/255 cyan and255/224/128 marker color; correspondence to semantic terrain,
buildings/liquids/units was not established by this capture alone.
Returning to165 differs by82 pixels; this sample does not isolate marker/footprint effects. Fixture popup_minimap_input.terrain_elevation_oracle has counts.

Excluded132823: directly assigning native window_z did not invalidate the native
minimap cache, yielding stale identical maps. Do not infer elevation independence
from that capture. DF50836/46972 closed/frame0/save unchanged.


## Native minimap semantic correlation (2026-10-01)

Native133221/133336 pair192-square map images with semantic tiles (shape,
material, hidden, liquid, building occupancy, dig/smooth), at165/164/166/155.
Candidate underground mapping: hidden RGB128; nonzero building occupancy or
construction200/140/0; water0/24/192; wall/fortification64; stone floor/ramp/stair192;
open air/ramp-top100/224/255, or water-blue when the tile below contains water.
After excluding camera marker RGB255/224/128 and rightmost column, this matches
all36588 sampled pixels at165 and36606 at166. This is oracle correlation, not
runtime or full minimap acceptance. Fixture terrain_semantic_oracle records limits.

Unexpected light-gray walls are exclusively x191 (45/44/3 pixels at165/164/166);
none has dig/smooth designation. The dig hypothesis is rejected; edge rule remains
unresolved. Surface materials/trees/ice/magma, precedence and deeper/hidden shaft
behavior still need captures. DF37248/49304 closed/frame0/save unchanged.

Occupied cells require per-tile occupancy facts, not zone/room bounding boxes.
Below-level liquid colors require invalidation when the lower level changes.


## Minimap surface facts and missing semantics (2026-10-01)

Native133621/133800 captures elevations170/175/180 with tile facts. Sampled
native RGB: grass/saplings128,192,0; shrubs50,128,0; tree trunks100,70,0;
branches/twigs/tree ramps32,96,0; soil floors128,64,0; sky100,224,255; brook
surfaces0,24,192. Roofed/unroofed surface stone floors are128 gray. Outside
alone cannot explain the difference from underground192 gray.

Controlled133916: four existing unoccupied stone floors, outside=false, with
orthogonal light/subterranean flags. Subterranean=true produces192 gray with
either light value; false produces128,192,0 green with either light value.
Thus subterranean matters and light alone does not, but ground-cover/material
context still matters. Do not implement a two-gray flag switch from this test.
The floor-finish control below resolves this counterexample.

Transport must preserve brook-top, subterranean and per-tile occupancy facts;
room extents do not establish occupied cells. Native minimap/cache/widget output
is not a runtime input.

Fixture popup_minimap_input.surface_semantic_oracle stores correlations/control.
DF20796/47140/53560 closed/frame0/save unchanged. This capture establishes
surface correlations, not the complete material precedence or runtime mapping.


## Minimap floor-finish rule resolved (2026-10-01)

Native134213 controls grass events on the four prior floor-flag test tiles:
no event, native grass104 event amount0, then100 all give identical colors.
Native134336 repeats that control and switches the same tiles from
StoneFloorSmooth to StoneFloor1 and back, retaining orthogonal light/subterranean
flags and outside=false. Subterranean floors stay RGB192 gray throughout.
Non-subterranean rough floors become RGB128 gray; smoothed floors return to
RGB128,192,0 green. Light has no effect in this matrix. This resolves the earlier
surface-floor counterexample; ground coverage was a rejected hypothesis.

The mapping uses smoothness, subterranean state, brook-top shape and native
per-tile occupancy. Grass coverage does not explain this sample; room bounds
cannot substitute for occupancy, and native minimap pixels are not runtime inputs.

Fixture popup_minimap_input.floor_finish_oracle contains exact flags/types/events/
RGB stages. DF27408/46228 closed/frame0/save unchanged; modifications were only
in disposable process memory. No production mapping change or broad acceptance.


## Minimap material and below-level precedence (2026-10-01)

Native134653 controlled matrix: ice floor/wall RGB224,255,255; depth1 water
0,24,192; depth1 magma128,24,0. Dry MagmaFlow uses contextual floor color,
not liquid-magma color. Hidden tiles conceal built+wet contents with128 gray;
building occupancy overrides liquid with200,140,0; liquid overrides wall shape.

Native134815: ordinary floors ignore water/magma below. BrookTop1 and OpenSpace
above water render water-blue; dry brook without below liquid uses contextual
floor color. Ice stays ice above water. Hidden status on the below-water tile
does not suppress blue in this sample. Preserve hidden-top priority separately.
This establishes need for the brook-top semantic distinction and below-level
cache invalidation. It does not justify copying native minimap/cache output.

Oracle correction: earlier raw terrain JSON magma fields used Lua truthiness
of an enum and are invalid as water/magma classifiers. These new captures use
an explicit df.tile_liquid.Magma comparison. Earlier screenshots/RGB counts and
other semantic fields remain valid. Do not derive liquid kind from the old field.
Fixture popup_minimap_input.material_precedence_oracle records both matrices.
DF49420/41004 closed/frame0/save unchanged; test mutations were in memory only.


## Terrain environment transport implemented (2026-10-01)

Snapshot schema10 appends sparse TileEnvironment facts to MapBlock while keeping
fixed snapshot TileState at8 bytes. Resident grid5 uses14-byte TerrainTile records;
model TileState is16 bytes with packed subterranean/brook-top/occupancy fields.
Publisher reads native designation/shape/occupancy; snapshot and resident-grid
paths both preserve the facts. Native subterranean changes now participate in
the terrain dirty mask; occupancy was already in the block signature. No native
minimap/widget/pixel state enters runtime. PINS records the required paired upgrade.

Validators reject unknown environment bits, occupancy>7, out-of-range tile indices
and duplicate sparse entries. Regression tests cover both paths, absent defaults,
and clearing prior resident facts on a later publication. Final QA
build/qa/minimap-environment-transport-final passes root build and all19 core tests.
Bridge compilation passes in minimap-environment-transport-covered. That earlier
run had core failures from the old demo fixture/schema-version expected string;
regenerated synthetic demo fixture with schema10, retained its old bytes under
that QA directory, and corrected the expected-version test. First two build
attempts caught model/block-size assertions; both corrected before final success.


## Native minimap color renderer implemented and live compared (2026-10-01)

Replaced classic-palette approximation with captured RGB/semantic priority in
mesher/minimap.h, consumed by the Godot extension. MinimapRevision tracks both
selected and immediately lower levels, session/scope included. Tile occupancy
arrives as terrain updates; unchanged output retains its existing GPU texture.
Regression tests cover native floor finish, liquid/hidden/building/ice/below-level
precedence and below-liquid/selected-occupancy invalidation vs unrelated levels.
QA minimap-native-color-mapping and minimap-native-surface-shapes pass core19/19,
extension builds and fortress_minimap_test. Installed matching snapshot10/grid5
bridge; management49/session10 unchanged. Install log minimap-environment-install.log.

Actual main-scene140607 texture comparison identified171 differences at170 and12
at175: roots plus rough ramps/stairs. Corrected ramps/stairs using native terrain
correlation. Final140921 comparison has0 differences at164/165/166/175/180 and108
at170. Those108 are TreeRoots: native64 gray vs current trunk brown100,70,0.
That source build merged ROOT/TREE/MUSHROOM columns into TreeTrunk. The root
and full-border correction below preserves the missing semantic distinction. Frame/map inspected in
viewer-unit.png. Comparison explicitly excludes outermost border pixels and native
camera marker RGB255,224,128; native edge and viewer footprint remain unaccepted.

Both actual main-scene runs pass navigation, press-only held movement in unit/
parent/fortress views, normal/Shift-wheel exclusion, Back, resize, detach/reconnect,
fresh31-entry reopen and close. DF51120/34916 closed/frame0/save unchanged; known
three shutdown diagnostics only. Fixture popup_minimap_input.native_color_implementation.


## Minimap root and full-border comparison passes (2026-10-01)

Preserved semantic root tissue through publisher/environment flags/snapshot/grid/
model; renderer distinguishes roots from trunk wood. Snapshot11/grid6 explicitly
reject older peers; grid14-byte and model16-byte sizes unchanged. Synthetic demo
fixture regenerated with old schema10 bytes retained in build/notes/pm. PINS
updated; matching bridge/viewer installed (minimap-root-install.log). Management49
and session10 unchanged. Range/duplicate validation, root decoding/clearing and
color precedence regressions pass in QA minimap-root-semantic, including bridge.

Native141515 tests all four map edges: exposed walls/roots/fortifications are
RGB192 gray. Ice, construction, liquid and hidden higher priorities retain their
captured colors. Renderer applies this from semantic tile coordinates/map size;
no native camera/widget/cache inputs. QA minimap-native-boundary core19/19,
extension and fortress_minimap_test pass. Native DF15304 closed/frame0/save unchanged.

Actual main-scene142158 exports six textures: z164/165/166/170/175/180 have ZERO
mismatches over220770 pixels, including all border pixels. Only native camera
marker RGB255/224/128 is excluded. Reproducible comparator:
build/notes/pm/compare-minimap-colors.py <capture> --require-exact.
Same live run passes navigation, press-only motion in fortress/parent/unit views,
normal/Shift-wheel exclusion, Back, resize, detach/reconnect/fresh31-entry reopen
and close. DF40932 closed/frame0/save unchanged; known three Godot diagnostics.
Fixture popup_minimap_input.root_and_boundary_acceptance contains exact evidence.


## Minimap camera-marker styling corrected (2026-10-01)

Native133800/deep map contains exactly66 RGB255,224,128 perimeter pixels in
inclusive bounds98,60..118,73: a one-pixel rectangle with no center cross.
Changed fortress_minimap.gd from white perimeter to captured pale-yellow and
removed unsourced center-cross drawing. No camera/widget runtime coupling added.
QA minimap-native-marker-style passes extension and fortress_minimap_test.

Actual main-scene142539 rendered viewer-unit map crop has0 white pixels and198
native-color marker pixels (prior142158:198 white,0 native-color). Image inspected.
All six terrain comparisons still have0 mismatches over220770 pixels, full border
included, native camera marker excluded. Existing navigation/held-input/wheel/Back/
resize/detach/reconnect/fresh-open/close checks pass. DF35692 closed/frame0/save
unchanged; known three Godot shutdown diagnostics. Fixture camera_marker_style.

LIMIT: viewer footprint still projects the local3D camera. Stroke styling does
not establish equivalence to native rectangle geometry. Texture acceptance covers
the sampled 192-square world; wider dimensions/scales and remaining material
combinations are unverified. Arbitrary scaling and physical hold timing are
outside the captured gesture sample.


## HUD header clipping corrected; copy/data gaps identified (2026-10-01)

Header inherited16px font vs native installed8x12 cells and used64px frame,
forcing count/calendar content beneath the alert popup. Applied12px/zero-line-gap
white value labels, removed extra mood/resource column separation, and used48px
frame anchored flush to the viewport top (including non-cell-aligned window heights). Heading/calendar/population fit actual
main-scene143101 at960x600; frame593x48 at8,0. Screenshot viewer-unit.png inspected:
all current header text readable above popup. QA hud-native-header-metrics passes.
Full main-scene input/resize/Back/detach/reconnect/fresh-open checks also pass;
DF57052 closed/frame0/save unchanged, known three Godot diagnostics only.

At this clipping checkpoint, source data omitted the native site name and
settlement class, calendar spelling differed, and header grouping/controls and
Saving text lacked native acceptance. The following calendar, identity and
composition sections record their corrections. This metric test alone establishes
readability, not whole-header fidelity. Fixture hud_header_metric_acceptance
records its scope.


### Native HUD calendar copy (2026-10-01)

The DF53.16 calendar matrix in `fixtures/reports/alert_entries.json` records all
12 native month/season lines. Early/Late use a space; Mid- uses a hyphen.
`fortress_hud_test` verifies those captured strings. Native143703 and main-scene
143833 protected captures passed without advancing/saving the clone; main scene
has only the three documented Godot diagnostics. Removed the unsourced Saving
suffix from the fortress-name label. Original name, settlement class and complete
header composition remain unfinished; calendar acceptance does not accept them.
An earlier oracle143326 used incorrect season_tick units and is excluded.

### Native fortress identity oracle (2026-10-01)

`fixtures/reports/alert_entries.json` now records the native identity mapping:
fortress ranks0..5 yield Outpost, Hamlet, Village, Town, City, Metropolis;
king_arrived overrides with Capital and king_hasty does not alter the caption.
Protected144207 captured all24 combinations without simulation ticks or saving.
Original and translated site-name translation matches the native name rows,
including the accented original name. This capture establishes oracle facts;
the Session11 section records transport and rendered-heading acceptance.

### Session11 fortress identity (2026-10-01)

Session11 adds original UTF-8 site name, fortress rank(-1 unavailable) and capital
status. The bridge reads semantic site/plotinfo fields and clears identity on
unload/reset; publication detects identity changes. Paired bridge/viewer rebuild
and installation is required; v11 region isolates older session readers. Do not
infer absent identity facts in older recordings. Snapshot11/grid6/management49
are unchanged. HUD renders original name, translated name and native rank/Capital
caption on three lines. Core19, extension, HUD and bridge compile pass; protected
main-scene145140 verifies the accented City-case heading within its48px frame,
with no ticks/saving and only the known three Godot diagnostics. Full header
composition and long-name/culture coverage remain unfinished.

### Native header group visibility (2026-10-01)

Native width fixtures record moods at133 text columns and one resource column per
seven columns from139 through181. HUD applies these rules at logical8px width,
replacing the previous arbitrary two-or-seven resources. Unsourced mood tooltips
are removed. QA hud-native-groups-final and protected main-scene145942 pass;
960 view hides both groups and retains native identity/calendar with no save/tick
changes and only known Godot diagnostics. Native fixed placement, auto scaling,
Stocks route and moon remain unfinished; current layout is not fully accepted.

### Native header anchors and playback (2026-10-01)

Header uses captured text-cell anchors and three-line population. Pause/play are
separate16x24 idempotent controls, using installed active/inactive artwork. Native
gear opens fortress options; help opens tutorial/guides. Custom DF3D/Game header
launchers were removed; native gear/help integration remains unfinished and hidden.
HUD QA native-controls-final and protected main-scene150909 pass exact960 anchors,
identity/calendar and bounds plus existing popup/input/reconnect checks; no saving
or simulation advance, only known Godot diagnostics. Moon, frame details, auto
scale and broader width comparisons still prevent full-header acceptance.

### Native header frame and moon oracle (2026-10-01)

Header frame uses installed8x12 HOVER_RECTANGLE cells with the top edge clipped.
HUD QA and protected main-scene151129 pass; sampled960x600 border/top regions
match native pixels exactly. Moon fixture records all28 authoritative world-data
phases and exact installed32x32 sprite matches at date.x-40,y+2. The Session12
section records transport and presentation; year_tick is not used to infer phase. Both runs
preserved paused clones without saving; only known main-scene diagnostics occurred.

### Session12 native moon indicator (2026-10-01)

Session12 transports authoritative moon_phase(-1 unavailable,0..27), clears it on
unload/reset, and isolates older peers in the v12 session region. Rebuild/install
bridge and viewer together; snapshot11/grid6/management49 unchanged. No migration
infers phase from calendar. HUD maps recorded native phases to installed32x32 art.
Core19/bridge compilation and corrected HUD/extension checks pass. Protected main
scene152504 verified all28 phase changes and zero differences across28672 native
moon pixels, then popup/input/reconnect checks; paused clone unchanged, known3
Godot diagnostics only. Harness waits for both bridge and HUD phase before capture.
Native HUD appearance/scaling now follows the viewer-settings section above.
Native options/help and Stocks actions remain unfinished; visible slots are inert
except the gear, which opens DF3D Settings.

### Wide native header groups (2026-10-01)

Mood icons/counts and resource labels now use captured native alignment/colors,
including gray None counts. Protected152950 matches entire mood/resource groups
pixel-for-pixel at1200x800,1400x800,1600x900; HUD QA passes. Paused clone unchanged,
known main-scene diagnostics only. Current count lengths are covered; automatic
scaling and visible Stocks geometry are now covered by the main-HUD pass above.
Native Stocks/options/help actions remain unfinished; long-value overflow has
not received full native acceptance.

### Native Options viewport layout (2026-10-01)

The unexposed native Options menu now follows viewport resize at1x8x12 cells,
matching origins and complete opaque menu pixels at960x600,1200x800,1600x900.
Native1600 capture154808 preserved the paused clone; GPU menu/input and session
adapter checks pass in native-options-responsive with only known diagnostics.
Other child viewport layouts, Settings/retire/abandon and main-scene integration
remain unfinished; this check does not promote the gear route or whole Options.

## Native Options confirmation resize corrected (2026-10-01)

Confirmation placement now responds to viewport changes using native whole8x12-cell
placement:960x600 origin224,252;1200x800 origin344,352;1600x900 origin544,396.
Protected native evidence options-confirm-layout-native-20261001-155116: Retire
opened and cancelled only, DF29692 closed, paused frame0, clone manifest unchanged.
Both complete504x120 native dialog crops match previously accepted1200 render with
zero differing RGB pixels. Native wide screenshot inspected. No retire/save effect.

native_options_confirmation.gd connects viewport resize; exact prompt copy and
input behavior retained. GPU native_options_view_capture tests all four prompts at
both additional sizes, all pixels, translated confirm/Cancel targets and consumed
Escape/right-click. native_options_session_test passes; QA native-confirmation-responsive
PASSED_WITH_KNOWN_ISSUES, only the three documented Godot signatures.
Fixture native_options_confirmations.json records provenance and limits. This
component remains unexposed; native resize oracle covers Retire, not separate
captures of all four prompts. Automatic scaling, save/timeline naming resize,
Settings/retire/abandon actions and full main-scene Options ownership remain open.


## Native save-name resize corrected (2026-10-01)

native_save_name_view.gd now relayouts on viewport resize, matching native
960x600 origin224,240;1200x800 origin344,340;1600x900 origin544,384. Native
options-name-layout-native-20261001-155715 opened and cancelled manual-save naming
at both additional sizes. DF59088 closed, paused frame0, source clone unchanged.
Full504x144 crop:960 has zero differences;1600 has exactly8 differing pixels in
blinking underscore, zero outside that cursor cell. Wide native image inspected;
Cancel plus subsequent menu dismissal returned to fortress in both captures.
No save submitted. Fixture native_save_name.json records provenance and limits.

GPU native-name-responsive PASSED_WITH_KNOWN_ISSUES, only three documented Godot
signatures; session test passes. Resize checks compare every dialog pixel with
fixed cursor phase, preserve existing draft bytes, consume Back and exercise
translated Cancel targets. Shared timeline subclass receives same layout and GPU
checks; the Native timeline prompt resize section records its separate oracle.
These component checks do not establish main-scene ownership, automatic scaling,
launcher exposure or Settings/retire/abandon actions.


## Native Options main-scene composition added (2026-10-01)

fortress_ui now creates the native Options view and session owner for live main
scenes, updates it from the existing session poll, and closes local pages on host
reset/loss of entered fortress without destroying pending request ownership.
The HUD includes native Options visibility in its overlay gate; its legacy Escape
handler no longer intercepts native child Back behavior. Native view layer21
sits above the existing overlay shield/HUD. No launcher exposure was added:
Settings/retire/abandon and remaining lifecycle/effect acceptance are unfinished.

QA native-options-main-composition: session, UI host and HUD tests pass; GPU
component capture PASSED_WITH_KNOWN_ISSUES (three documented Godot signatures).
Protected options-owner-main-live-20261001-160135 exercised actual main composition:
menu/naming/confirmation pointer routes, typed draft retained, resize, non-dismissive
child Escape/right-click, Cancel/menu dismissal, minimap click blocked, input gate
released. Cancel-only navigation left native session pending_seq0. Existing Reports
navigation/minimap/detach/reconnect suite also passed. DF51504 closed, paused frame0,
source clone unchanged, known diagnostics only. Main confirmation image inspected;
full504x120 confirmation crop equals native155116 with zero RGB pixel differences.

This owner/input run does not establish save effects, Settings/retire/abandon,
manual overwrite completion, automatic scaling or launcher exposure. Its screenshot
showed hidden minimap content, corrected and independently checked in the following
section. The harness opened the internal owner explicitly while the launcher was gated.


## Options minimap display/input separation verified (2026-10-01)

Main-scene capture exposed equal-layer overdraw: the opaque native minimap frame
covered its separate map canvas even before Options opened. The initial160345
comparison had zero differences but only one color (both maps blank), so it is
NOT display acceptance. Explicit ordering now uses map layer2 above ordinary HUD1,
map21 above Options HUD20, native Options22; Reports map11 remains unchanged.
The map stays input-disabled under Options. fortress_hud_test expectation updated.

QA native-options-minimap-order HUD/minimap checks passed cleanly. Protected
options-owner-main-live-20261001-160528 passed actual main owner/dialog/input and
existing Reports/minimap/detach/reconnect checks, only documented Godot diagnostics.
DF16148 closed, paused frame0, source clone unchanged. Inspected Options screenshot
shows terrain; options-map-comparison.json proves all36864 map pixels unchanged
before/after opening Options,7 distinct colors (explicit nonblank check). This
supersedes the minimap-hidden gap recorded in160135 and failed160345 visual attempt.
This display/input check does not establish save effects, launcher exposure,
automatic scaling or the broader Options lifecycle.


## Main-scene SaveContinue accepted (2026-10-01)

main-save-20261001160814 completed PASSED_WITH_KNOWN_ISSUES; exec92429 terminal0.
All363905 backup files verified before mutation. Actual main-scene Options pointer
SaveContinue and40-byte name, repeated Enter suppression, single success receipt,
exact destination and independent-process reload at paused frame0 passed. World
IDs2004778519/1401278833 and map192x192x193 match. Only known rendering-thread notice.
Final non-test/source/prior-test/new-destination preservation passed; owned DF5040
and49140 closed. Evidence/hashes retained in native_save_effect.json under
main_scene_save_continue. Main screenshot inspected. Destination:
df3d.godot-20261001160814xxxxxxxxxxxxxxx.

Options remains unexposed. Semantic manual overwrite, Settings/retire/abandon,
broader lifecycle/filename cases and automatic scaling are outside the established
acceptance. Writer checks require verified backups as described in the save lane.


## Native manual overwrite Cancel verified (2026-10-01)

Protected overwrite-cancel-native-20261001-171325 passed. Existing owned40-byte
manual name opens native SAVE_OVERWRITE; Cancel returns to naming with all bytes
retained. Before/after: entering_manual_folder=true, timer/stage/substage0,
do_manual_save=false, paused frame0. DF51960 closed, source and existing destination
hashes unchanged. Native confirmation screenshot inspected; full504x120 crop
matches existing Godot SAVE_OVERWRITE image with zero RGB differences.
Recorded in native_options_confirmations.json.overwrite_cancel_effect. This verifies
native conflict/Cancel behavior only; semantic overwrite submission remains absent.


## Main-scene QuitWithoutSaving accepted (2026-10-01)

Protected main-quit-effect-20261001-171435 PASSED_WITH_KNOWN_ISSUES; exec6730 terminal0.
Actual main-scene owner/normal polling: Escape retains confirmation, Cancel sends
nothing, repeated confirmation retains one sequence, one success closes Options.
Receipt action9/status2 at title phase1/epoch0 retains origin124639950929921 and
empty saved_save_id. Same DF29020 reached title; reload proved unsaved in-memory
name discarded and exact original world/timeline, paused frame0. Source manifest
unchanged; owned DF closed. Only known rendering-thread notice. Main confirmation
screenshot inspected; long synthetic marker is test data, not accepted header
truncation/product copy. Evidence retained as native_save_effect.json.
main_scene_quit_without_saving. Legacy loader, remaining Options actions and
launcher exposure are outside this QuitWithoutSaving acceptance.


## Main SaveReturn/new-folder accepted (2026-10-01)

main-return-20261001171634 completed PASSED_WITH_KNOWN_ISSUES; exec25800 terminal0.
Actual main scene matched fresh native catalog [region17,region18]; cancelled draft
preserved catalog; repeated click suppressed. Sequence2/action2 succeeded once
after catalog success, reached native title, created ACTIVE region20 in the exact
existing timeline. Separate-process reload: correct world/map192x192x193 and
paused frame0. Both DF52576/10104 closed. Final all-root/source/prior-test/new-save
preservation passed. Only known rendering-thread notice. Chooser image inspected.
Evidence retained in native_save_effect.json.main_scene_save_return_new_folder.


## Main SaveReturn/new-timeline acceptance (2026-10-01)

`native_save_effect.json.main_scene_save_return_new_timeline` records the actual
main scene saving a new timeline in region21 and independently reloading it.
The catalog matches a fresh native capture; Cancel preserves it and repeated
Enter submits one save. Exact 40-byte metadata, world identity and paused frame0
survive reload. Existing verified backup was reused; final unrelated-save,
source, prior-test and destination preservation passed. Both owned processes
closed; only the known rendering-thread notice remains. This case does not cover
empty/non-ASCII metadata, manual overwrite or launcher exposure.

## Main SaveReturn/existing-folder acceptance (2026-10-01)

`native_save_effect.json.main_scene_save_return_existing_folder` records main-scene
selection of owned region18 from a fresh native catalog, duplicate-click suppression,
exact-target overwrite without creating another directory, and independent reload.
A unique unsaved name marker persisted; world/timeline identity and paused frame0
matched. The target matched its verified backup before mutation. Final unrelated-save,
source, prior-test and reloaded-destination preservation passed. Both owned processes
closed; only the known rendering-thread notice remains. This does not establish
manual filename overwrite confirmation, which is still missing semantically.

## Native timeline prompt resize (2026-10-01)

`native_timeline_name.json.resize_acceptance` now verifies the timeline prompt
separately from manual-save naming. Opening at960x600 and resizing the same native
prompt to1600x900 matches the rendered component's whole-cell placement. Full
504x144 comparisons differ only by eight blinking-cursor pixels in the larger
capture. Cancel starts no save; paused frame0 and source preservation passed,
and the owned process closed. Automatic interface scaling remains unfinished.

## Native manual overwrite: durable effect, incomplete finishing state (2026-10-01)

`native_save_effect.json.native_manual_overwrite_recovered_effect` records native
confirmation starting an overwrite of a fresh disposable test copy and a separate
successful reload proving the changed world file and persisted marker. Original
unrelated-save preservation and read-only reload target/source preservation passed.
The effect runner failed a compound assertion before recording final completion
fields; this remains explicit incomplete evidence, not a fully passing native flow.
Semantic overwrite confirmation is still absent. Record completion fields before
asserting them in future captures, and retain separate effect and UI acceptance.

## Native pixel reference renderer

`project/shaders/native_tile_composite.gdshader` is a controlled top-down
reference path, exercised by `native_pixel_parity_test`. It is not connected to
ordinary fortress rendering. Two independently supplied tile layers are sampled
with native NEAREST positioning, blended in encoded RGB, rounded to an 8-bit
result, then decoded for Godot's linear output pipeline. The opaque background
and one foreground layer are explicit inputs; this does not use a screen-texture
feedback approximation or claim to solve general transparent depth sorting.

Run `python tools/qa/verify.py --check native_pixel_parity_test`. The GPU check
creates synthetic color, alpha-gradient and high-frequency atlas tiles and
compares complete RGBA output hashes against native DF 53.16 build 24557528 at
32, 48 and 64 destination pixels per 32-pixel source tile. Camera scale changes
reuse resident geometry. Its fixture contains hashes/provenance, no game art.

Native nearest sampling selects from each destination pixel's leading edge;
ordinary center-based GPU nearest sampling disagrees at fractional scales.
Rounding the encoded blend before conversion is also required: HDR precision
otherwise changes near-half values by one byte. Both details are covered by
zero-tolerance whole-image comparisons (237,568 pixels across the three sizes).

Protected native captures `build/notes/pixel-parity/native-20261013-124823`
(synthetic) and `native-20261013-125804` (installed artwork) used a paused,
verified save clone and temporary renderer overlays, then exited without saving.
The artwork run repeats the 32-cell scene with statues, bins, barrels and floor
textures, with zero differing pixels at all three NEAREST scales. Diagnostic
native texture exports stay ignored; they are not runtime asset inputs. This
establishes the compositor/sampler for identical input layers, not independent
semantic asset selection or full-fortress parity.

The reference shader intentionally retains its exact NEAREST scope. Main-world
AUTO filtering and color blending now use the production path below. Native's
precise AUTO transition thresholds and every Lanczos rounding operation are not
claimed identical; the maintainer accepted nearly identical output adapted to 3D.

## Native-like world color and AUTO filtering

Native-style world rendering is off by default in every camera mode. The saved
Display toggle in DF3D Settings enables it immediately without rebuilding meshes
or materials. Off restores standard linear-light blending. The separate saved
Texture smoothing toggle defaults off: magnified 3D textures use nearest texels,
while minified surfaces retain bounded mip/anisotropic filtering. Enabling
smoothing restores linear magnification. Native aligned-view reconstruction takes
precedence when native rendering is enabled. The HUD filter and sprite
correctness fixes remain unchanged.

When enabled, the main world camera installs `world_color_pipeline.gd`. All world materials
output encoded RGB into the world target so hardware transparency and MSAA
resolve blend consistently, including overlapping transparent layers. A single
`world_color_effect.gd` compute pass decodes the resolved result after transparent
draws, before tonemapping and the separate canvas/HUD pass. It does not sample a
stale opaque screen copy. This contract applies to the current unshaded world;
new world shaders/materials must use `world_output`, and additional world cameras
must install the matching compositor. Do not enable linear-light post effects
inside the encoded world pass without explicitly accounting for this contract.

`world_view` duplicates its Environment before installing the pass. The owner
restores clear color/compositor and releases the global mode on teardown. Compute
resources are created and freed on the render thread; cached uniform sets follow
render-target lifetimes. Headless rendering does not enable the pass. Standard
world overlays, designations, liquids and construction ghosts now use matching
shader materials; UI textures and HUD colors retain their existing canvas path.

World texture sampling reads encoded source bytes before filtering. At aligned
magnification, AUTO uses nearest within 0.025 of an integer scale and radius-three
Lanczos elsewhere, rounding/clamping the horizontal intermediate and final
sample. Those are viewer policy thresholds, not a claim to have recovered all
native AUTO thresholds. Oblique and minified surfaces use mip filtering, with
anisotropic sampling for isolated textures and bounded LOD/footprints for atlas
cells. Stable per-face atlas centers remain mandatory. Array batches and ordinary
textures implement the same kernels; camera changes do not rebuild geometry.

Immutable world artwork clears RGB only where source alpha is zero before
publication. Existing mipmaps are regenerated when this cleanup changes the
base level. Palette/composite preparation therefore precedes normalization;
partially transparent shadows and opaque colors are preserved. Native artwork
uses transparent black, while installed PNGs can contain invisible white and
edge-dilated composites can retain hidden gray. Filtering those hidden colors
washed out the statue outline even after transparency ordering was corrected.

Furniture with artwork extending beyond its building footprint retains an
individual draw instead of joining material-sorted building batches. Its
`furniture_order.gd` uses bounds-centered camera depth in angled views. In the
straight-down view it includes the same native foreground lift as the shader,
with a camera-relative south-over-north row tie-break. Camera changes update
only instance sorting offsets, never geometry or material resources. Other
buildings retain their spatial batches. This is object-level transparency
sorting, not a general solution for intersecting transparent geometry.

`furniture_order_test` checks overlapping half-alpha surfaces where native lift
reverses physical depth, four angled directions, return to top-down, MSAA off/on,
and stable mesh/material identities. Pure asset tests check hidden-RGB cleanup
and preservation of partial alpha; recorded statue checks cover uploaded RGB
and picking. The matched native crop in `build/notes/alpha-integration` has mean
RGB byte error 0.055 and maximum 2 after both corrections, compared with mean
2.073 before them. This is scoped visual evidence, not full-fortress pixel parity.

Furniture tops use a full source-tile alpha surface above the existing opaque
silhouette sides/bottom. Trimming that surface to the 50%-alpha contour clips
partial-alpha outlines and the filter's reconstruction fringe into hard steps.
The transparent material determines visible coverage; no additional framebuffer
is needed. Opaque actor meshes retain contour caps. Building picking uses retained
CPU vertex/UV streams and source alpha, so the added transparent area cannot
intercept selection. Physical footprint/depth allocation still uses the original
opaque mask. The mesher regression covers cap coverage, unchanged sides/bottom,
partial-only images and empty images; the recorded depth-cache check exercises
both transparent-padding rejection and opaque statue picks.

`world_color_pipeline_test` renders actual terrain/furniture layers through the
production shaders and compositor, using synthetic native capture references at
32 and 48 pixels per tile. Ordinary/array paths with MSAA off/on have mean RGB
byte errors 0.034 and 0.066 respectively, maximum errors 1 and 3. It also checks
three overlapping layers (maximum error 0.535), unchanged clear/HUD colors and
idempotent teardown. The exact single-quad NEAREST regression remains separate.

Evidence: `build/notes/native-auto/final-qa` passes construction/designation,
combat-anchor, status-depth, production-color and resource-lifetime checks with
only documented Godot diagnostics. The earlier `qa` run also passes depth-cache,
mesh batching, world sampling, seam and exact-reference checks; its failures were
the subsequently corrected overlay-test material API and render-thread resource
cleanup. Fresh `verified-*` captures cover straight-down, isometric, distant and
perspective views and have empty stderr. The matched pedestal crop's mean RGB
byte error fell from 6.67 to 2.48. On the local RTX 3080 Ti at 1920x1080, sampled
median GPU times were 5.11 ms straight-down, 4.96 ms close isometric, 1.98 ms distant
and 4.62 ms perspective. These are scene-specific observations, not universal
frame-rate guarantees or a controlled before/after performance benchmark.
