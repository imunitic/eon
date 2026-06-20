# AGENTS — Eon ECS Guide for Automation

This file is the **canonical reference** for all agents working in this repository. CLAUDE.md defers to this file; on any conflict, this file governs.

## 1. Project at a glance

Eon ECS is a minimal, deterministic, backend-agnostic ECS runtime.

Core modules:
- `World`: entities, components, services, data resources.
- `Signals`, `Events`, `Commands`: message buses with explicit frame semantics.
- `System`: reactive systems (`register`, `update`, `on_signal`, `on_event`, `on_command`).
- `Pipeline`: phase graph + dependency ordering.
- `Progress`: variable/fixed/hybrid ticking over pipeline kinds.
- `Loop`: frame orchestrator (`collect -> tick -> drain -> render`).

Core design goals:
- Minimal primitives.
- Composable functors and open variant keys.
- Deterministic fixed/hybrid simulation when needed.

## 2. Public API boundary

**`eon_ecs` public API:**
- Contract: `eon_ecs/eon_ecs.mli`
- Composition root: `eon_ecs/eon_ecs.ml`
- Rule: if a module should be public, wire and document it in both files. Internal modules not re-exported from `eon_ecs.mli` are private.

**`eon_engine` public API:**
- Contract: `eon_engine/eon_engine.mli`
- Composition root: `eon_engine/eon_engine.ml`
- Rule: same as above. `Eon_ecs` types needed by game code are re-exported here — see §13.

## 3. Design documentation

The `docs/design/` directory contains the authoritative source of architecture and design decisions. See `docs/design/index.md` for the full list and one-line summaries.

Current design documents:
- `eon_engine_design.md` — top-level `eon_engine` philosophy, module structure, re-export convention
- `eon_engine_query_design.md` — query builder and backend abstraction
- `world_module_design.md` — `World.S` signature and per-world `Id_counter`
- `query_view_design.md` — unified `iter` + typed `View` replacing `iter1..4`
- `thread_safety_design.md` — concurrency philosophy, `World_cap` capability types, reactive system model
- `parallel_pipeline_execution.md` — concrete parallel pipeline spec: `Dependency_graph`, `Executor.S`, `World_cap`, `Eon_engine.System`
- `rendering_layer_design.md` — backend-agnostic rendering layer
- `data_service_plane_namespacing.md` — data/service plane namespacing at the engine layer
- `world_manager_design.md` — stub for future `Worlds` multi-world module

Key principles:
- Design documents take precedence over implementation details.
- New architectural decisions must be documented here **before** implementation begins.
- Changes to public API or architecture invariants must update the relevant design doc.

When making significant changes:
1. Review the relevant design document(s) first.
2. If the implementation diverges from a design doc, **stop and ask the user** before proceeding — do not silently leave them out of sync.
3. After approved changes, update the design doc to match.

## 4. Architecture invariants (do not break)

Bus order invariants:
1. Collect: `Signals`, then `Events`, then `Commands`
2. Tick: `Progress.tick`
3. Drain: `Signals`, then `Commands`, then `Events`
4. Render/read-only work after drains

Bus semantics:
- **Signals** (`Single_bus`): `drain = collect`; dispatches emitted messages to subscribers immediately. Same-frame: emitted during a frame are dispatched during `drain` at end of that frame.
- **Events** (`Double_bus`): `emit` → `next` queue; `drain` runs `collect` on `current`, then swaps `next → current`. Previous-frame emissions become visible the next frame.
- **Commands** (`Single_bus`): same drain=collect semantics as Signals; intended for world-mutating operations. Handlers run synchronously during `drain`.

Component rules:
- Register component names before `add_component` or `set_component`.
- `World.get_component` returns `Some v` if the component is present on the entity, `None` if absent — **but raises** if the component name was never registered. Do not use the exception for control flow.
- `World.set_component` and `World.remove_component` also raise on unregistered component names.

Pipeline:
- **Never add phases or ordering edges after the simulation loop starts** — the topological sort is cached and will not re-run. The cache invalidates only on `add_phase`, `before`, or `after` calls; it does not invalidate when systems are added.

## 5. Default stack aliases

Use the default stack unless customization is required:
- `Eon_ecs.World`
- `Eon_ecs.System.Default`
- `Eon_ecs.Pipeline.Default`
- `Eon_ecs.Progress.Default`
- `Eon_ecs.Loop.Default`
- `Eon_ecs.Signals`, `Eon_ecs.Events`, `Eon_ecs.Commands`

For custom scheduling kinds, use `System.Make_with_kinds` and `Progress.Make_with_kind`.

## 6. Build, test, benchmark

Use `just` tasks only. Never call `opam exec` or `dune` directly.

```sh
just tasks
just build
just run-tests
just check
just test eon_ecs/test/test_main.exe
just bench sparse_set
just bench loop
just bench-ci
just bench-compare world
just clean
```

**Preferred tools:** Always use `rg` (ripgrep) instead of `grep`, `find`, or similar search commands. Use `rg` for all content and file searches.

**External dependencies:** Do not add opam dependencies unless strictly necessary and not achievable with stdlib alone. Every non-stdlib dependency must be justified.

## 7. Testing and benchmark layout

Tests:
- `eon_ecs/test/`
- Entrypoint: `eon_ecs/test/test_main.ml`
- Frameworks: `Alcotest` (unit), `QCheck2` via `qcheck-alcotest` (property)
- Property test file naming: `test_prop_<area>.ml`

Benchmarks:
- `eon_ecs/bench/`
- Shared helpers: `eon_ecs/bench/benchmark_helpers.ml`
- Framework: `Bechamel` with `Staged` benchmarks
- Config: `Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) ()`
- Metrics: `monotonic_clock`, `minor_allocated`, `major_allocated`

## 8. Contribution checklist

After code changes:
1. `just build`
2. `just run-tests`
3. Run relevant benchmarks for performance-sensitive changes.
4. Update `AGENTS.md` if public behavior or API changed.
5. Update the relevant design document(s) in `docs/design/` if architecture or design decisions changed.

When adding a new core module:
1. Add `<module>.ml` + `<module>.mli` in `eon_ecs/`.
2. Decide whether it is public; if yes, re-export in `eon_ecs/eon_ecs.mli` and wire in `eon_ecs/eon_ecs.ml`.
3. Add unit tests in `eon_ecs/test/test_<module>.ml`; property tests in `test_prop_<module>.ml`.
4. Register suites in `eon_ecs/test/test_main.ml`.
5. Add a benchmark in `eon_ecs/bench/bench_<module>.ml` if performance-relevant.
6. Update `AGENTS.md` and relevant `docs/design/` documents.

## 9. Planning process

When working on a new task or complex change:
1. **Plan first**: Do not start implementing until the plan is approved.
2. **Update task file**: Write the implementation plan in the org-roam task file (in `~/Roam`).
3. **Get approval**: Wait for an explicit "green light" before making any code changes.
4. **Task files are NOT code**: Task files live in `~/Roam` and are never committed to git.

**What counts as a complex change** (plan first):
- Adds or modifies a public API in `eon_ecs.mli`.
- Touches more than one module boundary.
- Requires a design decision not already covered in `docs/design/`.
- Introduces a new module, functor, or bus type.

Simple changes (a single-module bug fix, a documentation update, a test addition) do not require a plan.

## 10. Commit message convention

**Format by package:**
- Changes in `eon_ecs` only: `[eon_ecs :: <area>] <summary>`
- Changes in `eon_engine` only: `[eon_engine :: <area>] <summary>`
- Changes spanning both packages: `[eon_ecs, eon_engine :: <area>] <summary>`
- Cross-cutting changes (tooling, docs, dune-project, AGENTS.md): `[eon :: <area>] <summary>`

**Append task ID when a task file applies:**
- `[eon_ecs :: <area>] <summary> (ecs-<id>)`
- Multiple items: `[eon_ecs :: <area>] <summary> (ecs-<id1>, ecs-<id2>)`
- Omit the ID suffix when no org-roam task item is directly applicable.

**Area tokens:**
- `docs` — documentation, comments, .mli doc strings
- `bench` — benchmarks, benchmark helpers
- `core` — runtime logic (query, world, pipeline, progress, loop)
- `tooling` — build files, Justfile, dune, CI, warning flags, missing interfaces
- `ecs` — cross-cutting ECS concerns, composition root, default stack wiring
- `fix` — bug fixes (use alongside the primary area: `core :: fix`, `ecs :: fix`)

**Style:**
- Imperative mood, sentence case, no trailing period.
- Mention the primary subsystem; avoid generic summaries like "update files".
- If one commit spans multiple areas, pick the dominant one.

## 11. Release checklist

Before tagging:
1. `just build`
2. `just run-tests`
3. Run relevant benchmark tasks.
4. Ensure docs and API wiring are in sync.
5. Confirm dune/opam metadata still resolves.

## 12. Tasks

**Primary source of truth:** All tasks (completed, in-progress, and future) are tracked in Org (org-roam) files in `~/Roam`.

When asked about tasks — what was worked on last, pending work, or status — always consult `~/Roam` and parse the org-roam files.

**Task file pattern:** Files are named `YYYYMMDDHHMMSS-ecs_XXX_description.org` and contain:
- `:TASK-ID:` property (e.g., `ecs-001`)
- `:LAST_UPDATED:` property (ISO timestamp, e.g., `2026-04-26 14:36`)
- A `** Tasks` checkbox section (unchecked items = in-progress)
- A `** Notes` section with implementation summaries

**Status management:**
- **NEVER mark TODO items as DONE** unless explicitly told to do so by the user.
- When work is completed, update status to **REVIEW** instead.
- Mark as DONE only when the user explicitly requests it after reviewing the work.
- Update `:LAST_UPDATED:` timestamp whenever task status changes.

**Git commit and push rules:**
- **PROHIBITED:** Agents are prohibited from committing and pushing to git.
- **REQUIRED:** Every commit and push requires explicit user permission.
- Even if previously granted permission, ask again for each commit/push.
- Never assume permission based on previous authorization.

**Task file version control:**
- Task files are stored in `~/Roam` and are **NOT** under git version control.
- **NEVER** attempt to add, commit, or modify task files via git commands.

**Example queries:**
- "What task did we work on last?" → Find the file with the most recent `:LAST_UPDATED:` timestamp.
- "What tasks are still pending?" → Find files with unchecked items in `** Tasks` or `* TODO` headings.
- "Show me the status of ecs-001" → Parse `~/Roam/*ecs_001*.org` and report task state and notes.

## 13. `eon_engine` conventions

### Single-import rule

**Game code imports only `Eon_engine`, never `Eon_ecs` directly.** `Eon_engine`
re-exports all `Eon_ecs` types that game code needs. When `Eon_engine` grows its
own replacement for an `Eon_ecs` type, the re-export line is swapped — zero
call-site changes for users.

Modules `Eon_engine` already owns (do **not** re-export from `Eon_ecs`):
`World`, `System`, `Pipeline`, `Query`, `Component`, `Bus`, `Single_bus`, `Double_bus`,
`Signals`, `Events`, `Commands`.

`Signals`, `Events`, `Commands` are semantic aliases (`Single_bus` / `Double_bus` /
`Single_bus`) defined in the engine composition root — the same pattern as `eon_ecs`.
Game code uses `Commands.emit`, never `Single_bus.emit` or `Double_bus.emit`.

Modules re-exported from `Eon_ecs` (game code uses `Eon_engine.X`, not `Eon_ecs.X`):
`Entity_id`, `Clock`, `Progress`, `Loop`.

### Extension pattern — build upon, don't replace

`Eon_engine` wraps `Eon_ecs` modules rather than replacing them:

- `Eon_engine.World` wraps `Eon_ecs.World` with typed component descriptors
- `Eon_engine.System.Make(Core_system)` wraps any `Eon_ecs.System.S` with `World_cap` capabilities
- `Eon_engine.Pipeline.Make` uses `Eon_ecs.Dependency_graph` for phase ordering

The embedded core types are fully functional — engine systems work with both
`Eon_ecs.Pipeline.Make` (sequential) and `Eon_engine.Pipeline.Make` (parallel).

### Two pipeline stacks

| Use case | Pipeline | Executor | System type |
|---|---|---|---|
| No `World_cap` needed | `Eon_ecs.Pipeline.Make(Eon_ecs.System.Default)` | N/A (core fold) | `Eon_ecs.System.Default` |
| Engine sequential | `Eon_engine.Pipeline.Make(System.Default)(Sequential)` | `Sequential` | `Eon_engine.System.Default` |
| Engine parallel | `Eon_engine.Pipeline.Make(System.Default)(Domain_pool)` | `Domain_pool` | `Eon_engine.System.Default` |

Engine systems always go through `Eon_engine.Pipeline.Make`. The executor controls
parallelism — `Sequential` for deterministic single-threaded dispatch, `Domain_pool`
for concurrent dispatch. The same `System.Default.make` definition works with both;
swap the executor, not the system code.

`Eon_engine.System.Default.t` is its own record type (stores `update_kind` alongside
the embedded core) and does not satisfy `Eon_ecs.System.S`. Never pass engine systems
to `Eon_ecs.Pipeline.Make`.

### Parallel pipeline — reactive system model

All systems in the parallel pipeline follow the reactive model:

- `update_kind = Parallel of (World_cap.ro World_cap.t -> float -> unit)` — **always read-only**, enforced at compile time. Runs in parallel across all systems in a phase.
- `update_kind = Exclusive of (World_cap.rw World_cap.t -> float -> unit)` — **always sequential**, runs after parallel systems in the same phase. Can write world state directly.
- `on_signal / on_event / on_command : World_cap.rw World_cap.t -> ... -> unit` — **always read-write**, always sequential (fire during `collect`/`drain`, never during `tick`).

`on_*` handlers are optional — defaulting to no-ops makes a non-reactive system.

### `World_cap` — pipeline-internal

`World_cap` is constructed and managed by the parallel pipeline. Game code
never calls `World_cap.wrap`. Game code sees `World_cap.ro World_cap.t` in
`update` and `World_cap.rw World_cap.t` in `on_*` handlers — it does not
construct these values.

`World_cap` lives in `eon_engine` only. Never add `'perm` phantom types to
`Eon_ecs.World.t`.
