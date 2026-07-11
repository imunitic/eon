[![Eon ECS Core CI](https://github.com/imunitic/eon/actions/workflows/ci.yml/badge.svg)](https://github.com/imunitic/eon/actions/workflows/ci.yml)
[![Coverage (Bisect)](https://github.com/imunitic/eon/actions/workflows/coverage.yml/badge.svg)](https://github.com/imunitic/eon/actions/workflows/coverage.yml)

# Eon

Eon is a minimal, deterministic, backend-agnostic game engine stack for OCaml 5.

This repo contains three packages, each with its own README:

| Package | What it is |
|---|---|
| [`eon_ecs/`](eon_ecs/README.md) (`eon-ecs`) | The ECS core: entities, typed component storage, message buses, a system scheduler, and a fixed/variable-step game loop. |
| [`eon_engine/`](eon_engine/README.md) (`eon-engine`) | The engine layer on top: capability-typed world (`ro`/`rw`), a query builder with typed views, a parallel pipeline, built-in components, input/audio/rendering backend seams, and prefab loading. |
| [`eon_edn/`](eon_edn/README.md) (`eon-edn`) | A standalone EDN reader built on OCaml 5 algebraic effects. No dependency on the other two packages; `eon-engine`'s prefab loader is its first consumer. |

## Principles

- **Minimalism** — core primitives only; no god objects or central managers.
- **Extensibility** — functorized modules and open polymorphic variant keys.
- **Purity** — systems express intent; command handlers apply effects.
- **Determinism** — fixed/hybrid progress modes provide stable simulation behavior.
- **Single-threaded by default** — concurrency (the parallel pipeline, `Executor`) is opt-in at the engine layer, never imposed by the core.

## Build and test

Use `just` (never call `opam exec` or `dune` directly):

```sh
just tasks          # list all available tasks
just build           # compile the workspace
just run-tests       # full test suite
just check           # build + test (pre-push gate)
just test <suite>    # single target, e.g. eon_ecs/test/test_main.exe
just clean
```

## Benchmarks

```sh
just bench <name>          # eon_ecs: sparse_set | entity_manager | query | world | loop
just engine-bench <name>   # eon_engine: executor | render_stream | prefab
just edn-bench <name>      # eon_edn: edn_parser
just bench-ci               # full benchmark matrix (what CI runs)
just bench-compare <name>   # run a benchmark 3x and save outputs under /tmp
```

## Documentation

- Per-package tutorials and quick starts: see each package's README above.
- Full odoc API reference (all three packages): `just docs` to build, `just open-docs` to build and open in a browser.
- Architecture and design decisions: [`docs/design/`](docs/design/index.md) — canonical, governs on conflict with any other doc. Includes [`codebase_map.md`](docs/design/codebase_map.md), a visual reference for module dependencies, functor instantiation, test coverage, and code statistics across all three packages (regenerate with `just visualizations`).

## Rendering, input, and audio: eon_ecs vs eon_engine

`eon_ecs`'s core loop is `collect → tick → drain` and carries no platform
concerns at all — rendering is just a system in a pipeline phase.
`eon_engine` adds the actual platform seams (`Platform.S` bundling
`Input_backend`, `Audio_backend`, `Rendering_backend`) so a real game
binary can plug in a concrete backend (e.g. raylib) while tests and
servers use `Platform.Headless`. See the [`eon_engine` README](eon_engine/README.md#platform) for details.

## Contributing

- Keep public API changes synchronized between each package's `.mli`, its `.ml` composition root, and its README/docs.
- For deterministic/order-sensitive changes, add or update tests before merge.
- Use commit subjects like: `[eon_ecs :: <area>] <summary>`, `[eon_engine :: <area>] <summary>`, or `[eon :: <area>] <summary>` for cross-cutting changes (including `eon_edn`, which doesn't yet have its own commit token). See `AGENTS.md` §10 for the full convention.
- `AGENTS.md` is the canonical design and rules document; `CLAUDE.md` is an operational summary for AI coding assistants — on conflict, `AGENTS.md` governs.
