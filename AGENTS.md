# AGENTS — Eon ECS Guide for Automation

This file is the agent-oriented map of the repository. Keep it short, factual, and aligned with the public API.

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

Public/stable API is what is exported from:
- `eon_ecs/eon_ecs.mli`

Composition root:
- `eon_ecs/eon_ecs.ml`

Rule:
- If a module should be public, wire and document it in both files above.
- Internal modules not re-exported from `eon_ecs/eon_ecs.mli` are private.

## 3. Architecture invariants (do not break)

Bus order invariants:
1. Collect: `Signals -> Events -> Commands`
2. Tick: `Progress.tick`
3. Drain: `Signals -> Commands -> Events`
4. Render/read-only work after drains

Semantics:
- Commands: same-frame effects via handlers.
- Events: queued, become visible on the double-buffer schedule.
- Signals: transient notifications.

Component rules:
- Register component names before `add_component`/`set_component`.
- `World.get_component`, `set_component`, `remove_component` raise on unknown component names.

Pipeline:
- Topological phase order is cached and invalidated only when phases/edges change (`add_phase`, `before`, `after`).

## 4. Default stack aliases

Use the default stack unless customization is required:
- `Eon_ecs.World`
- `Eon_ecs.System.Default`
- `Eon_ecs.Pipeline.Default`
- `Eon_ecs.Progress.Default`
- `Eon_ecs.Loop.Default`
- `Eon_ecs.Signals`, `Eon_ecs.Events`, `Eon_ecs.Commands`

For custom scheduling kinds, use `System.Make_with_kinds` and `Progress.Make_with_kind`.

## 5. Build, test, benchmark

Use `just` tasks:

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

## 6. Testing and benchmark layout

Tests:
- `eon_ecs/test/`
- Entrypoint: `eon_ecs/test/test_main.ml`
- Frameworks: `Alcotest`, `QCheck2` via `qcheck-alcotest`

Benchmarks:
- `eon_ecs/bench/`
- Shared helpers: `eon_ecs/bench/benchmark_helpers.ml`
- Framework: `Bechamel` with staged tests

## 7. Contribution checklist

After code changes:
1. `just build`
2. `just run-tests`
3. Run relevant benchmarks for performance-sensitive changes.
4. Update `README.md` + `AGENTS.md` if public behavior/API changed.

When adding a new core module:
1. Add `<module>.ml` + `<module>.mli` in `eon_ecs/`.
2. Decide whether it is public; if yes, re-export in `eon_ecs/eon_ecs.mli` and wire in `eon_ecs/eon_ecs.ml`.
3. Add tests and register suites in `test_main.ml`.
4. Add a benchmark if performance-relevant.

## 8. Commit message convention

Primary format:
- `[eon :: <area>] <summary>`

Area tokens in current history:
- `docs`, `bench`, `core`, `tooling`, `ecs`, `fix`

Fallback:
- `[eon] <summary>`

Style:
- Imperative, concise, subsystem-focused subject.

## 9. Release checklist

Before tagging:
1. `just build`
2. `just run-tests`
3. Run relevant benchmark tasks.
4. Ensure docs and API wiring are in sync.
5. Confirm dune/opam metadata still resolves.
