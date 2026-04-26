# CLAUDE.md — Eon ECS

Quick reference for Claude Code working in this repository.

## Build & Test

**Always use `just`. Never call `opam exec` or `dune` directly.**

```sh
just build          # compile the workspace
just run-tests      # full test suite
just check          # build + test (pre-push gate)
just test <suite>   # single target, e.g. eon_ecs/test/test_main.exe
just bench <name>   # release-profile bench: sparse_set | entity_manager | query | world | loop
just bench-ci       # full benchmark matrix
just clean
just tasks          # list all available tasks
```

## Repository Layout

```
eon_ecs/          # ECS library (public package: eon-ecs)
  eon_ecs.ml      # composition root — wire everything together here
  eon_ecs.mli     # public API contract — everything exported here is stable
  world.ml/.mli   # central state: entities, components, resources
  entity_id.ml    # generational entity handles
  entity_manager.ml
  component.ml    # typed component wrappers (Obj.magic boundary)
  component_registry.ml
  sparse_set.ml   # core data structure (indexed, O(1) add/remove/iter)
  resource_store.ml
  query.ml        # iter1–iter4 + count over component intersections
  bus.mli         # BUS signature (collect / drain / emit / on)
  single_bus.ml   # same-frame: drain = collect
  double_bus.ml   # next-frame: emit → next queue; drain swaps buffers
  loop_default_buses.ml
  system.ml       # reactive system builder; Make / Make_with_kinds functors
  pipeline.ml     # phase graph + topo sort; no .mli (internals exposed)
  progress.ml/.mli # Variable / Fixed / Hybrid / Custom time modes
  loop.ml/.mli    # Make functor: collect → tick → drain → render
  clock.ml/.mli
  test/           # Alcotest unit + QCheck2 property suites
  bench/          # Bechamel benchmarks
eon_engine/       # Higher-level engine layer (separate package)
dune-project
Justfile
AGENTS.md         # Authoritative design doc — read before changing architecture
```

## Key Architectural Facts

### Default stack aliases (use these)
| Alias | Module |
|-------|--------|
| `Eon_ecs.Signals` | `Single_bus` (same-frame, transient) |
| `Eon_ecs.Events` | `Double_bus` (next-frame reactions) |
| `Eon_ecs.Commands` | `Single_bus` (same-frame mutating) |
| `Eon_ecs.System.Default` | `System.Make(Signals)(Events)(Commands)` |
| `Eon_ecs.Pipeline.Default` | `Pipeline.Make(System.Default)` |
| `Eon_ecs.Progress.Default` | `Progress.Make(Pipeline.Default)` |
| `Eon_ecs.Loop.Default` | `Loop.Make(Clock.Mtime)(Progress_adapter)(Noop_renderer)(Loop_default_buses)` |

### Frame order (never reorder)
```
collect Signals → Events → Commands
Progress.tick
drain   Signals → Commands → Events
Renderer.render
```

### Bus semantics
- **Signals** (`Single_bus`): `drain = collect`; dispatches emitted messages to subscribers immediately. Same-frame: emitted during a frame are dispatched during `drain` at end of that frame.
- **Events** (`Double_bus`): `emit` → `next` queue; `drain` runs `collect` on `current`, then swaps `next → current`. Previous-frame emissions become visible the next frame.
- **Commands** (`Single_bus`): same as Signals; handlers execute synchronously during `drain`.

### Component lifecycle
1. `World.register_component world ~name:"Foo" ~id:N` — must happen before any `add_component`.
2. `World.add_component` — first attach (raises if component unknown).
3. `World.set_component` — update existing (promotes to add if missing).
4. `World.get_component` — returns `Some v` or `None`; **raises** for unregistered names (not documented in .mli for `get_component`).
5. `World.remove_component` — detaches from entity.
6. `World.destroy_entity` → `remove_all_components` — safe to call without manual cleanup.

### Resource store key collisions
Services and data are keyed by `Obj.repr key` (physical identity of the variant). OCaml's `Hashtbl` resolves internal collisions with equality checks, so distinct variant keys with the same hash do **not** silently overwrite each other. Keep service keys as top-level variant constructors for best clarity.

### Query iteration
- `iter1`: iterates all entities in the component's sparse set.
- `iter2`–`iter4`: picks the smallest sparse set as the iteration base; checks membership in others. Values are passed to `f` in the order the component names were given.
- `count`: same intersection logic without a callback.

### Pipeline topo sort
The topological sort result is **cached** (`order_cache` field). It is computed once on first access and reused across frames. The cache is invalidated only when phases or ordering edges are added (`add_phase`, `before`, `after`). Adding systems does not invalidate the cache. Do not add phases or edges after `register_all` is called.

## Public API Contract

- **Everything exported from `eon_ecs/eon_ecs.mli` is public and stable.**
- Internal modules not re-exported there (e.g. `Sparse_set`, `Entity_manager`, `Resource_store`, `Component_registry`) are private/unstable.
- When adding a public module: update both `eon_ecs.mli` (types + docs) and `eon_ecs.ml` (wiring).

## Commit Convention

Primary format:

- For changes in `eon_engine`: `[eon_engine :: <area>] <imperative summary>`
- For changes in `eon_ecs`: `[eon_ecs :: <area>] <imperative summary>`
- For cross-cutting changes (e.g. tooling, CLAUDE.md, dune-project): `[eon :: <area>] <summary>`
- When nothing applies, use the rule for cross-cutting changes.

If one commit addresses multiple areas:

```
[eon_engine :: <area>] <imperative summary>
```
or
```
[eon_ecs :: <area>] <imperative summary>
```

Area tokens:
- `docs` — documentation, comments, .mli doc strings
- `bench` — benchmarks, benchmark helpers
- `core` — runtime logic (query, world, pipeline, progress, loop)
- `tooling` — build files, Justfile, dune, CI, warning flags, missing interfaces
- `ecs` — cross-cutting ECS concerns, composition root, default stack wiring
- `fix` — bug fixes (use alongside the primary area when one commit = one fix)

Style rules:
- Imperative mood, sentence case, no trailing period.
- Mention the primary subsystem; avoid generic summaries like "update files".
- If one commit spans multiple areas, pick the dominant one.

## Adding a New Core Module

1. `eon_ecs/<module>.ml` + `<module>.mli`
2. Re-export from `eon_ecs.mli` if public; wire in `eon_ecs.ml`
3. Unit tests in `eon_ecs/test/test_<module>.ml`; property tests in `test_prop_<module>.ml`
4. Register suites in `test_main.ml`
5. Benchmarks in `eon_ecs/bench/bench_<module>.ml` if perf-relevant
6. Update `AGENTS.md`

## Testing

- Framework: `Alcotest` (unit) + `QCheck2` via `qcheck-alcotest` (property)
- Property test file naming: `test_prop_<area>.ml`
- Run a specific suite: `just test eon_ecs/test/test_main.exe`

## Benchmarking

- Framework: `Bechamel` with `Staged` benchmarks
- Config: `Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) ()`
- Metrics: `monotonic_clock`, `minor_allocated`, `major_allocated`
- Helpers in `eon_ecs/bench/benchmark_helpers.ml`

## Tasks

**Primary source of truth:** All tasks (completed, in-progress, and future) are tracked in Org (org-roam) files located in `~/Roam`.

When asked about tasks—whether to show what was worked on last, list pending work, or check status—always consult the `~/Roam` directory and parse the org-roam files.

**Task file pattern:** Files are named like `YYYYMMDDHHMMSS-ecs_XXX_description.org` and contain:
- `:TASK-ID:` property (e.g., `ecs-001`)
- `:LAST_UPDATED:` property (ISO timestamp, e.g., `2026-04-26 14:36`)
- A `** Tasks` checkbox section (unchecked items = in-progress)
- A `** Notes` section with implementation summaries

**Example queries:**
- "What task did we work on last?" → Find the file with the most recent `:LAST_UPDATED:` timestamp
- "What tasks are still pending?" → Find files with unchecked items in `** Tasks` or `* TODO` headings
- "Show me the status of ecs-001" → Parse `~/Roam/*ecs_001*.org` and report task state and notes
