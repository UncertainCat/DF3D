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
## Native material navigation integration (2026-10-04)

Construction material distance lookups call DF53.16's native flood through
`bridge/plugin/construction_material_native.cpp`, including connected Track.
Candidate admission, grouping, placement geometry and construction commands have
separate owners; this callback computes material-navigation distances only.

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
  launcher remains gated with the rest of this unfinished release.

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

Other current defects include Track Closest choosing different items when native
search reports negative distances (cause unresolved), cold-first-preview routing,
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

## Windows package

Run `DF3D-0.1.0-windows-x64.exe`, select your installed Dwarf Fortress, and use **Set up bridge**
with the game closed. The launcher discovers Steam libraries and also accepts `DF3D_DF_PATH`
or a folder selected with Browse. Godot and the required runtimes are included.

Setup verifies file hashes and backs up replaced files under `%LOCALAPPDATA%/DF3D/backups`.
**Restore bridge files** reverses setup, refusing to overwrite files changed afterward.
Extracted application files and logs are under `%LOCALAPPDATA%/DF3D`.

The release launcher leaves the native game window available. Closing the packaged viewer
does not terminate DF. The 0.1.0-rc.1 cut excludes save-and-close; viewer exit sends
no save command. DF remains running with its simulation and save ownership intact.
This differs from the temporary owned session started by the source `Play.cmd` launcher below.

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
hidden intermediate tiles are not. PendingTrack requires a compatible native job
classification, and BlockingBuilding requires an established blocking family/state;
unclassified buildings remain Unknown. Unknown shapes and malformed liquid data
remain Unverified, not native refusal. Callers must not use this result alone to
authorize placement: directed movement, current job stages and material effects
remain separate checks. Bridge fact extraction is not implemented yet.
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
model, not exact pixel acceptance. Production compositing correction remains open,
including transparent underlays and sorting. Native screenshots were inspected;
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
`construction_material_candidate_gate.lua` implements this partial Track flag/bin
predicate using copied facts, with unknown results for missing facts and unsupported
containers. The registered core check `test_construction_material_candidate_gate`
replays all 29 observations and checks malformed/unsupported inputs. This helper
is not yet embedded or used by production Materials. Recipe suitability, positions,
site reachability, other containment and stale-item validation remain separate work.
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
remain allowed. `construction_track_material_recipe.lua` implements this partial
recipe predicate with unknown results for missing policy facts, and the registered
candidate test replays all 42 probes. The recipe source vector contains13369 items
of many types. The initial pointer/ordered-content comparison did not enumerate
the fixed vector container correctly; the subsequent source capture below resolves
this gap. BAR subtypes/materials, artifacts and full candidate integration remain
open. Initial213248/213322/213410
oracle attempts failed setup assumptions;213447 is the accepted capture. The game
stayed paused and the owned source save remained unchanged.
Protected `213738` explicitly indexes all135 named item vectors and compares every
ordered item ID. Native recipe source uniquely matches `world.items.other.IN_PLAY`
in all three policy states (13369 entries). Runtime can enumerate that semantic
collection; it must not read the native recipe/filter vector. Protected `213836`
adds baseline/melt/restored flag evidence: the melt designation excludes the block.
The Track gate mask is now0xe90c32 and short-circuits known primary exclusions
without requiring unrelated missing facts. The registered candidate check includes
that native exclusion. Both captures remained paused and preserved the owned save.
Protected `214209` adds twelve BAR material probes: iron, platinum, tin, steel,
copper and silver are accepted; coke, charcoal, ash, potash, pearlash and soap
are rejected. All twelve match native isBuildMat and the existing partial recipe
predicate without additional token rules. Soap comes from an installed creature
material explicitly flagged SOAP. The registered recipe replay now covers54
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
`construction_material_selection.lua` implements that pure kernel;17 candidate
tests replay it and the expanded ordering captures. It is not embedded or connected
to picker actions yet. Direct method evidence does not establish actual button
behavior, post-click list sorting, stack consumption or placement. Both owned
captures remain paused with source saves unchanged and processes ended.
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
Production integration of independent navigation and enumeration remains unfinished.
The existing visible-workflow material scanner remains an approximation and must not be accepted as native
Track behavior. See `native_material_order_audit` in the Track fixture.

`bridge/plugin/construction_material_terrain.lua` implements the separate native
material-flood destination predicate. It reads semantic map/building state only
and remains unconnected to the material query. Its native table fixture covers
all 697 pinned tile identities, including Campfire, tree-trunk and twig exceptions
that prevent reuse of normalized display shapes. The predicate checks
`designation.flow_forbid` (not the hidden bit), static occupancy, and the traced
closed hatch/grate/bar branches. It is not a complete movement edge, liquid-depth
rule or item eligibility decision. Missing loaded terrain or dynamic-building
facts remain unknown. `test_construction_material_terrain` is registered in the
core gate and checks 18122 tile/occupancy/flow/dynamic combinations plus missing
facts against `fixtures/construction/material_destination.json` and the traced
branches. Full movement rules and protected live integration remain required.

`wm::materialEnvironmentAllowed` implements the liquid/temperature portion of
native material movement flags `0x901020` (AllowUnrevealed, ShallowWater, WalkLand,
LevelMapless). Protected native captures `195106` and `195236` verify a controlled
floor corridor: water depths 0..6 pass, depth 7 fails, nonzero magma fails,
temperature_1 10199 passes and 10200 fails. Hidden and zero-walkable-group barrier
tiles remain traversable; flow_forbid blocks them in the separate destination
predicate. The fixture test compares 22 floor cases against native reachability;
`fixtures/construction/material_environment.json` retains all 23 observations.
For water over a vertical opening, the environment helper requires verified lower
opening/depth facts and rejects a full lower tile. That branch is traced and unit
tested, but still needs native live coverage. DFHack `canStepBetween` rejects
water depth >=4 and is not equivalent to this material search.
In these deliberately controlled fixtures, unreachable items can remain native
picker choices with negative distances derived from stale path scratch. Those
history-dependent values are diagnostic evidence, not valid distance results or
proof of natural candidate availability. Production candidate filtering and
unreachable-item behavior remain to be established independently.

`construction_material_opening.lua` supplies three vertical-opening modes used
by material navigation. Liquid and ramp-clearance modes accept only the four native
open-space/ramp-top identities; stair movement additionally accepts down/up-down
stairs, branches and twigs. All reject floored, obstacle and impassable occupancy, while Well
occupancy does not itself close the opening. A closed hatch blocks liquid; both movement modes
blocks it only when forbidden, complete and setting occupancy. Closed floor grates
and floor bars block all three. These rules have native binary-table and synthetic
building-state coverage in `test_construction_material_terrain`; full directed
movement and protected live opening acceptance remain unfinished. The helper is
embedded with the construction closure, but not yet used by production material queries.

`fixtures/construction/material_movement.json` retains 48 protected native
material-search observations (`202830`): all dry floor/stair pairings, cardinal
and diagonal stair controls, and RampTop/OpenSpace ramp crossings in both
elevation directions. Search seed/source costs prove the isolated flood ran;
negative stale target costs are diagnostics, never usable material distances.
The paused clone stayed unchanged. An initial oracle assertion incorrectly
required a nonempty choices list and was corrected; an empty picker is possible.
`materialMovementGeometry` in the independent model matches all 48 observations
through the recorded-fixture CTest. It preserves unknown opening/support facts,
handles integer boundaries, and distinguishes pure stair transitions from
cardinal/diagonal ramp transitions. Protected `203254` adds 64 destination-water
cases (depths 0 through 7, both directions). Geometry plus destination environment
classification matches these cases: depths 0–6 retain valid crossings; depth 7
rejects. Native material flags `0x901020` have no intersection with the swim/fly
fallback mask `0x20012800` at RVAs `dc1bad` and `dc1ef0`, so those branches are
inactive. The CTest now compares all 112 retained cases. The paused clone remained
unchanged. The geometry helper is not wired into production material queries.
Lower-liquid opening integration, seed selection and full candidate filtering
remain separate gaps; controlled dynamic-building evidence is described below.

`construction_material_facts.lua` composes the destination, opening and raw-tile
classification helpers through injected functions. At a safe point it observes
native shape, ramp/support/open facts, stair/ramp clearance, temperature, liquids
and the extra destination predicate. Lower liquid depth is read only when
nonzero, non-full water has a known downward opening. Missing blocks and unknown
dynamic state remain unknown. `destination_allowed` alone is not full movement
approval; compose it with environment and geometry using `materialMovementAllowed`.
For fixed material flags `0x901020`, all 697 native general surface classifications
match the extra destination predicate, and the active building branches reduce
to the same obstructions/support. The table and branch hashes are retained in
`material_destination.json`. Protected `204118` matches 28 controlled building
cases through the composed model check: floor/open-space Door, Hatch, vertical
and floor Grate/Bars states. With flow-forbid cleared, closed/forbidden doors
remain traversable; closed vertical grates/bars block; closed hatches and floor
grates/bars provide surfaces over open space. This does not establish natural
building-state transitions. The paused clone remained unchanged and fixture
buildings were removed. Native flags for other movement contexts differ. Protected native-only `203703` retains these actual reader
outputs at 48 controlled movement cases; direct model replay matches every native
outcome. The paused clone stayed unchanged. Reader tests additionally cover
unknown dynamic buildings and unavailable lower blocks. These Lua helpers are
embedded and owned by the cached construction closure. Production Materials
queries still use the unfinished older implementation.
The safe-point command `df3d material-distances-read <sx> <sy> <sz> <tx> <ty> <tz>
<tile-limit>` uses the same cached construction closure and its embedded reader,
with actual map bounds. It returns numeric status and ordered reachable/distance
rows; it selects no materials and creates no jobs. Invoke it through the protected
lane's DFHack helpers. Protected `205901` compares 48 installed-callback queries
to native material-search reachability/distances, with unchanged native search
generation and paused clone. Build and installed plugin hashes match. An initial
loader error returned the reader factory instead of calling it; the accepted run
uses the corrected initialization. Protected Track Preview regression `205933`
still matches four native ordered paths/counts and preserves pending jobs; it is
`passed_with_known_issues` for the pinned startup notice. These checks do not prove
production material seed/candidate selection or the full picker workflow.

Protected `210320` verifies the Track material seed for fourteen controlled
five-tile same-level drafts: both endpoint directions and seven target identities
(floor, ramp, three stairs, OpenSpace and RampTop). Each has exactly one observed
zero-cost cell at the second endpoint in the bounded oracle window. All requests
retain subtype TrackNSEW, and all 56 installed-callback distance probes from that
endpoint match native. The native search generation, paused frame and owned save
remain unchanged. `material_movement.json` retains `track_seed_capture` and input
hashes. This establishes the tested endpoint rule, not multi-level draft coverage
or production integration. Runtime must derive its seed from the semantic draft;
native buildreq and pathfinder scratch remain oracle-only. Candidate enumeration,
group copy, selection effects and the complete material picker remain unfinished.

`construction_material_shapes.lua` classifies native movement ramps and ramp
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
source eligibility conditions still need acceptance. The standalone material shape
helper remains unconnected to production material queries.

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
Protected010407 establishes ordinary settling without flag writes: a four-cell
native Track preview and cancellation clears pending reindexing, changing the
level-map counter5417->5420. All11 subsequent ordered native paths match production
bridge/Godot Preview under the unchanged strict comparator. See
`ordinary_native_settling`; known renderer notice only, paused frame0, unchanged
save and owned process ended. This accepts those settled-state paths, not the
first search with reindex pending. Product warmup/suppression is not authorized
by this test; the cold-search mismatch remains open.

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
runs the viewer but fails those checks. The D3D12 separate-renderer shutdown can also leak two plain engine Objects: this
was reproduced on 2026-09-28 in an empty project with no DF3D scripts or extension.
The classifier recognizes exactly that pair only with the same pinned process's
D3D12 renderer, startup notice and known finalize callsite; extra objects, other
renderers, changed callsites and isolated leak warnings still fail. Local reproduction
and raw trace are in `build/notes/pm/leak-isolation/`. This remains a known engine
issue, not a clean pass. One known failure: the GPU combat test reports a
misaligned billboard hit effect.

### Installation and shipping checks

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

DF3D uses [Semantic Versioning 2.0.0](https://semver.org/), starting with **0.1.0**.
The application version lives in `presentations/godot/project/project.godot`
(`config/version`); release tags use `v` plus that exact version, such as `v0.1.0`.
Version 0.1.0 is the next release target, not a claim that a package has been published.

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

Billboard visibility bounds follow the fragment shader's ceiling clip. Item preparation
retains separate source-query `bounds` and renderer `render_bounds`; never use the clipped
box to track roof dependencies, since removing a roof must expand visibility again.
Unit bounds include the culling margin before ceiling clipping, with the
engine margin disabled for that billboard batch to avoid expanding it above the roof.
Classic sprite bounds are not ceiling-clipped. Camera movement does not invalidate these
bounds or rewrite sprite payloads. `item_preparation_gpu` covers roof lowering, raising,
removal and style transitions; `sprite_ceiling_revision_test` covers source invalidation.

Terrain and buildings render through the full map depth below the selected level.
Items and creatures render on the selected level and eleven levels below it.
This range follows the selected level; descending brings nearby sprites back.
The range check precedes appearance preparation, and cutout picking uses the same
filtered render arrays. Terrain residency and semantic source data are independent.
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
path exits Walk before selecting the new elevation (Walk restores its prior
cutaway), then synchronizes the rig level before focus. Report coordinates use
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
frame with native viewport y remainder. Heading/calendar/population fit actual
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
Native header integration remains incomplete: gear/help, Stocks, automatic scaling
and wider geometry/overflow coverage are outstanding.

### Wide native header groups (2026-10-01)

Mood icons/counts and resource labels now use captured native alignment/colors,
including gray None counts. Protected152950 matches entire mood/resource groups
pixel-for-pixel at1200x800,1400x800,1600x900; HUD QA passes. Paused clone unchanged,
known main-scene diagnostics only. Current count lengths are covered; automatic
scaling at1920x1080, overflow, Stocks and native options/help remain unfinished.

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
