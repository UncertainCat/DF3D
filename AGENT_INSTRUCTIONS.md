# Project rules

Engineering rules for anyone, human or AI agent, changing this repo; section 2 is the architecture contract.

Terms used below:

- lane: a group of checks in `tools/qa/checks.json` (core, assets, gpu, bridge, live).
- protected live lane: checks that launch the real game; only selected with `--allow-live`, run one
  at a time via `tools/smoke/Df3dLane.psm1`.
- owned vs attach session: the launcher starts and contains DF (owned) vs connects to a DF you started.
- capture lane: a live lane that records a bridge fixture (`tools/smoke/capture_fixture.ps1`).

## 1. Scope and documentation

`README.md` is reserved for human authorship: the maintainer's own words to readers.
An empty README is intentional until the maintainer writes it; do not fill it with a placeholder.
Agents must not write, rewrite, polish, reformat or automatically update it, including
badges, generated sections and link maintenance. When changes make README facts stale,
tell the maintainer in conversation and update the agent-maintained technical reference;
leave README wording and edits to the maintainer. Do not draft replacement README prose
as part of routine documentation work.

Other first-party files may be agent-maintained within the requested scope. Keep build,
run, verification and release guidance in `ENGINEERING.md`, architecture and engineering
rules here, and compatibility pins in `PINS.md`. This separation preserves a human voice
in the README while letting technical documentation evolve with the implementation.

DF remains the authoritative simulation; DF3D is a swappable presentation with a semantic command
path back to DF. Godot is the current host, not a dependency of the foundation. Do not change
engine, product UX/art direction or distribution posture without maintainer decision.

Working documents (plans, notes, status) stay in ignored scratch space such as `build/notes/` and
are never committed or shipped. Persist a document only when its ongoing value justifies maintaining
it, say why in the change description, and prefer updating an existing reference over adding one;
remove stale material instead of archiving it (Git keeps history).

Write durable docs and comments around current behavior, invariants, ownership and
limitations. Update the owning section instead of appending an iteration log.
Remove superseded plans and references that require conversation or experiment
history to interpret. Keep dated evidence when it establishes provenance, a supported
release's behavior or an unresolved defect; scope its claims to that build/run.

### Current release cut (maintainer direction, 2026-10-01)

Work toward a release candidate using useful verified subsets. If a candidate
expands materially, defer or narrow it for this cut and record why in the release
scope at the top of build/notes/pm/TRACKER.md. A release exclusion does not remove
project requirements, grant native-parity acceptance, or mark a hidden feature
complete. Preserve deferred work and its evidence for later releases. Included
behavior still follows the native-copy, ownership and verification rules below.

Subsequent maintainer clarification, 2026-10-01: the next feature-release targets
are Reports/alerts AND full construction. The maintainer explicitly rejected a
furniture-only construction release. For construction, the earlier scope-cut
permission does not authorize silently dropping tracks, machinery, traps,
variable-size placement or native material-selection modes. Small workflows may
be implementation milestones; the delivered target remains the realized native
construction feature. Track current evidence and gaps in the release tracker.

Maintainer clarification, 2026-10-02: fix the Reports "Pause on new"
initialization issue for this release if feasible; some bugs are acceptable for
this cut. Record retained defects and their practical impact explicitly. This
does not remove project requirements or authorize invented visible copy.

Subsequent maintainer decision, 2026-10-02: "don't fuss it, whatever's simpler.
Player can pause." Pause on new may start off per fortress session and remember
explicit toggles within that session. This specific simplification is accepted;
do not reopen native initialization matching as an RC2 blocker. Explicit toggle
behavior remains supported. Other native-parity and visible-copy rules still apply.

Maintainer request, 2026-10-03: show a visible busy indication while construction
material lookup/placement is pending. A text-free indeterminate animation is
authorized for this asynchronous wait; it does not authorize authored status
copy, fabricated progress percentages or broader native-UI departures.

## 2. Architecture and runtime ownership

- Preserve bridge -> pointer-free mirror -> engine-independent world model ->
  presentation boundaries. Presentations use the model API, never mirror memory.
- Use game semantics below the presentation layer. No renderer/atlas/mesh concepts
  in mirror/model contracts; no raw pointers cross process boundaries.
- Bridge work runs at safe points. Prioritize smooth ordinary gameplay. Routine
  streaming and automatic refreshes should be economical; brief simulation slowdowns
  from opening or using panels are generally acceptable. Use judgment about caching,
  batching, incremental processing or synchronous work, favoring simplicity unless
  there is evidence of a performance problem. Existing streaming implementations can
  stay where useful.
- Maintainer authorization, 2026-10-03: prefer verified native DF APIs over
  recreating DF rules. Native material calculations may run synchronously at a
  safe point with independently owned inputs and scratch restoration. Godot
  frame responsiveness takes priority over simulation throughput during these
  interactive actions. Keep Godot asynchronous and validate native behavior
  before release. Do not drive or borrow the global native build-menu state.
- Maintainer clarification, 2026-10-03: prioritize prompt responses to explicit
  gameplay actions over simulation throughput during those actions. Larger safe-point
  batches are allowed when measurements justify them; keep the viewer responsive.
- Performance policies do not impose universal step ceilings or require blanket
  rewrites. Correctness, safe-point execution, ownership,
  stale-target checks and unknown-outcome handling remain separate requirements.
  Memory, payload, geometry and retirement-storage limits retain their independent
  justification. Pause, load, slowdown and rewind remain normal lifecycle cases.
- Commands are validated semantic intents with stable IDs and current epochs.
  Sent is not succeeded. Unknown outcomes must not be automatically replayed.
- Panels own local tabs, selection, scrolling and drafts. Native viewscreens,
  widgets, cursor/camera state and staged edits are prohibited runtime inputs.
  Pause/load/save/session lifecycle are explicit global exceptions; existing native
  load/save coupling is not a precedent for ordinary management actions.
- Keep engine resources on the main thread. Worker-prepared data must be immutable
  and identity/revision checked before application. Joining workers, resetting old
  epochs and retiring state are explicit ownership responsibilities.

## 3. Assets and native UI

- Require the supported Steam DF installation and resolve art/graphics definitions from it; ship no
  DF-derived sprites, textures, fonts or audio. Missing/unrecognized installs fail clearly. Derived
  caches and captured art stay ignored and out of distribution. Exceptions require human review.
  Maintainer-approved exception: retain upstream DFHack's bundled UI artwork unchanged with
  its license/permission notices. This does not authorize DF3D to bundle extracted game assets.
- Native DF is the UI reference. Inspect the supported build's actual layout and behavior before
  changing a surface; source/tests alone do not establish visual fidelity. Reuse valid evidence when
  available, otherwise capture through protected lanes; hand-supplied screenshots are a last resort.
- Preserve native hierarchy, labels, grouping and actions; original artwork on an invented layout is
  not parity, though small documented spacing/wrapping differences are acceptable. Use sourced prose
  or factual values; missing descriptions stay blank rather than being fabricated.
- Maintainer clarification, 2026-09-28: agents and generated specs must not author substitute
  visible copy. Map native copy or reproduce it verbatim, with traceable native evidence.
  Bot-authored specs, review approvals and documented departures do not override native DF
  behavior or appearance. Treat conflicting requirements as defects to resolve, not permission
  to ship compromises. Audit labels, tooltips, status/error text and unsupported-state copy;
  flag text without a native source rather than inventing a replacement.
  Synthetic copy in test fixtures is acceptable, but is not evidence for product copy
  and must not become visible runtime text or a native-parity acceptance expectation.
- Specs are implementation guidance, not the product authority. Every worker and reviewer
  must compare its task against the primary objective: native DF behavior and appearance.
  A spec requirement or documented departure that conflicts with native parity is a defect
  in the spec, even if Fable, Astra, or another worker/reviewer approved it. Identify the conflict, correct the
  spec and implementation within the authorized scope, and update tests to verify native
  evidence rather than preserve the compromise. Do not claim completion from compliance
  with a conflicting checklist. Only an explicit maintainer-authorized product departure
  can override the native target; agent/PM acceptance is not that authorization.
- Hidden/disabled screens are unfinished, not complete. Unknown routes stay hidden; no native-screen
  fallback. `ui_availability.gd` defines current exposure.
- Compare rendered output and exercise actual game effects, including cancellation, stale targets,
  disconnects, epoch changes and late replies. Read-only acceptance does not authorize editing; disclose
  gaps.

## 4. Rendering and performance

- Camera/projection/animation changes update view/shader state, not unchanged resident geometry.
  Separate source changes, style transitions and stale demand. Hidden stale groups retain
  invalidations. Global revisions only trigger precise dependency checks; record absent inputs so
  late arrivals repair fallbacks.
- Keep grouping separate from dynamic payloads and object/creature ordinals independent. Coalesce
  dirty causes; immediate repairs consume queued work for the same owner. Preserve picking, ramp
  support and clipping agreement.
- Sparse updates require exact source and storage bases; missed patches or external resets recover
  from complete retained data. Scope/session/asset replacement must invalidate the right owner.
  Record cache identity and reset ownership beside fields.
- Use deterministic work-count regressions, not machine-specific timing thresholds; a between-job
  budget is soft. Profile before optimizing, on equivalent workloads without concurrent build/test noise.
- Keep raw traces in ignored build output and use bounded digests. Overlapping intervals must not be
  added; missing instrumentation is unknown, not zero. Diagnostic clocks/readbacks stay opt-in.
- Known Godot diagnostics (font atlas, render-device shutdown, dummy mesh, occluder) are deferred by
  maintainer decision: do not patch Godot or reprobe them during unrelated work; triage rules and
  upstream references are in `tools/qa/diagnostics.py`.

## 5. Verification and compatibility

- Use fixture-driven, deterministic tests with injected time. Extend reproducing fixtures for bugs.
  Synthetic logic tests do not replace recorded/live evidence; fixture manifests carry provenance and
  omissions. Never use shipped game art to make tests pass. `consumers/inspector` must keep working.
- Schema lives in `schema/mirror.fbs`; update validators, generated contracts and required versions
  together. Breaking schema changes get their own commit with migration notes. Migrations must not
  invent facts absent from old recordings.
- Use the cheapest adequate tests; root CTest runs before commits. Presentation behavior requires
  engine checks; bridge changes and DF/structure version bumps need protected live acceptance.
  Passing headless tests is not GPU/UI parity.
- The offline gate is `python tools/qa/verify.py`. Its manifest defines coverage; missing
  prerequisites mean incomplete, not success. Never count unselected lanes, old binaries or
  assertion completion with unexpected engine errors as success. A run whose only diagnostics are
  the documented signatures reports passed_with_known_issues; keep that distinct from a clean pass.

## 6. Local execution and save protection

- Prepend your MinGW bin directory to PATH (the gate reads `DF3D_MINGW_BIN`, default
  `C:/msys64/mingw64/bin`); other installed compiler/runtime DLLs can shadow it. Close Godot before
  replacing its loaded extension DLL.
- Run only one live lane at a time through `tools/smoke/Df3dLane.psm1`; check that DF is closed
  before starting an owned lane. Never kill DF by process name.
- Never invoke `dfhack-run.exe` directly from a terminal: it can hide the inherited console. Use
  `Invoke-Dfhack`/`Invoke-DfhackRaw` from the lane module, which provide a private console.
  `console_guard.ps1` diagnoses/restores a hidden console.
- Preserve process/save ownership and verified backups. Owned development sessions end without
  saving; attach sessions leave the game running (see `ENGINEERING.md`).
- Compatibility baselines are in `PINS.md`; exact dependency revisions are Git submodule pointers.
  External trees are separate repositories: DFHack changes go to the fork in `.gitmodules` (the DF3D
  plugin stays in `bridge/plugin`) and are pushed there before this repository's pointer moves;
  nested DFHack dependencies update in DFHack first; godot-cpp stays on upstream unless a change
  requires a fork. A pin change needs the corresponding build/live checks; don't silently upgrade.
- After pulling, check for your own edits inside the dependencies before running
  `git submodule update --init --recursive`. Avoid `--remote`: it upgrades dependencies rather than
  checking out this project's tested versions.
