# CLAUDE.md — Eon ECS

Quick reference for Claude Code working in this repository. **AGENTS.md is the canonical design and rules document; this file is an operational summary for Claude Code. On any conflict, AGENTS.md governs.**

## Build & Test

**Always use `just`. Never call `opam exec` or `dune` directly.**

```sh
just build          # compile the workspace
just run-tests      # full test suite
just check          # build + test (pre-push gate)
just test <suite>   # single target, e.g. eon_ecs/test/test_main.exe
just bench <name>   # release-profile bench: sparse_set | entity_manager | query | world | loop
just bench-compare <name>  # compare bench results
just bench-ci       # full benchmark matrix
just clean
just tasks          # list all available tasks
```

**Output filtering:** Pipe build and test commands through `tee` and filter to warnings/errors/summary only — full output gets truncated in the UI:

```sh
just build 2>&1 | tee /tmp/eon_build.log | grep -E "Warning|Error|warning|error" || true
just run-tests 2>&1 | tee /tmp/eon_tests.log | grep -E "FAIL|Error|tests run|failures|Successful" || true
just check 2>&1 | tee /tmp/eon_check.log | grep -E "Warning|Error|warning|error|FAIL|tests run|failures|Successful" || true
```

If a command produces no filtered output, the full log is at `/tmp/eon_*.log`.

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
docs/design/      # Authoritative architecture and design decision docs
dune-project
Justfile
AGENTS.md         # Canonical design doc and agent rules — read before changing architecture
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
collect: Signals, then Events, then Commands
Progress.tick
drain:   Signals, then Commands, then Events
Renderer.render
```

### Bus semantics
- **Signals** (`Single_bus`): `drain = collect`; dispatches emitted messages to subscribers immediately. Same-frame: emitted during a frame are dispatched during `drain` at end of that frame.
- **Events** (`Double_bus`): `emit` → `next` queue; `drain` runs `collect` on `current`, then swaps `next → current`. Previous-frame emissions become visible the next frame.
- **Commands** (`Single_bus`): same drain=collect semantics as Signals; intended for world-mutating operations. Handlers run synchronously during `drain`.

### Component lifecycle
1. `World.register_component world ~name:"Foo" ~id:N` — must happen before any `add_component`.
2. `World.add_component` — first attach (raises if component unknown).
3. `World.set_component` — update existing (promotes to add if missing).
4. `World.get_component` — returns `Some v` if present, `None` if absent. **Raises if the component name was never registered** — this is distinct from "not present on this entity". Do not use the exception for control flow.
5. `World.remove_component` — detaches from entity; raises on unregistered names.
6. `World.destroy_entity` → `remove_all_components` — safe to call without manual cleanup.

### Resource store key collisions
Services and data are keyed by `Obj.repr key` (physical identity of the variant). OCaml's `Hashtbl` resolves internal collisions with equality checks, so distinct variant keys with the same hash do **not** silently overwrite each other. Keep service keys as top-level variant constructors for best clarity.

### Query iteration
- `iter1`: iterates all entities in the component's sparse set.
- `iter2`–`iter4`: picks the smallest sparse set as the iteration base; checks membership in others. Values are passed to `f` in the order the component names were given.
- `count`: same intersection logic without a callback.

### Pipeline topo sort
**Never add phases or ordering edges after the simulation loop starts** — the topological sort cache will not re-run. The cache invalidates only on `add_phase`, `before`, or `after` calls; adding systems does not invalidate it.

## Public API Contract

- **Everything exported from `eon_ecs/eon_ecs.mli` is public and stable.**
- Internal modules not re-exported there (e.g. `Sparse_set`, `Entity_manager`, `Resource_store`, `Component_registry`) are private/unstable.
- When adding a public module: update both `eon_ecs.mli` (types + docs) and `eon_ecs.ml` (wiring).

## Commit Convention

See AGENTS.md § 10 for the full rules. Summary:

- `[eon_ecs :: <area>] <summary>` — changes only in `eon_ecs`
- `[eon_engine :: <area>] <summary>` — changes only in `eon_engine`
- `[eon_ecs, eon_engine :: <area>] <summary>` — changes spanning both
- `[eon :: <area>] <summary>` — cross-cutting (tooling, docs, dune-project)

Append `(ecs-<id>)` when a task file applies; omit when none does.

Area tokens: `docs`, `bench`, `core`, `tooling`, `ecs`, `fix`

Style: imperative mood, sentence case, no trailing period.

**Never add `Co-Authored-By` trailers to commit messages.**

## Adding a New Core Module

1. `eon_ecs/<module>.ml` + `<module>.mli`
2. Re-export from `eon_ecs.mli` if public; wire in `eon_ecs.ml`
3. Unit tests in `eon_ecs/test/test_<module>.ml`; property tests in `test_prop_<module>.ml`
4. Register suites in `eon_ecs/test/test_main.ml`
5. Benchmarks in `eon_ecs/bench/bench_<module>.ml` if perf-relevant
6. Update `AGENTS.md` and relevant `docs/design/` documents

## Testing

- Framework: `Alcotest` (unit) + `QCheck2` via `qcheck-alcotest` (property)
- Property test file naming: `test_prop_<area>.ml`
- Run a specific suite: `just test eon_ecs/test/test_main.exe`

## Benchmarking

- Framework: `Bechamel` with `Staged` benchmarks
- Config: `Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) ()`
- Metrics: `monotonic_clock`, `minor_allocated`, `major_allocated`
- Helpers in `eon_ecs/bench/benchmark_helpers.ml`

## Planning Process and Tasks

See **AGENTS.md §9** (planning process) and **AGENTS.md §12** (task management) for all rules.

Key constraints repeated here for visibility:
- **Plan first** for any complex change (new public API, multi-module change, new design decision).
- **NEVER commit or push** without explicit user permission — ask each time.
- **NEVER mark tasks DONE** unless the user explicitly asks; use REVIEW instead.
