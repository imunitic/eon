# eon_ecs — Notes & Tutorials

Reference notes and tutorials for working with the `eon_ecs` library.

- [eon_ecs_usage_tutorial.md](eon_ecs_usage_tutorial.md) — End-to-end walkthrough of the default stack: setting up a world, registering components, wiring buses, and tracing one full frame through collect → tick → drain → render.
- [api_documentation_strategy.md](api_documentation_strategy.md) — Strategy for writing odoc documentation for `eon_ecs`: goals, structure, and patterns for producing API docs close in quality to Rust/Go docs.
- [docs_benchmarks.md](docs_benchmarks.md) — Benchmark patterns using Bechamel: how to structure `Staged` benchmarks, configure quota/limits, and read `monotonic_clock` / allocation metrics.
- [qcheck_property_testing_tutorial.md](qcheck_property_testing_tutorial.md) — Two styles of property testing with QCheck2: simple generators and stateful model-based tests, with examples from the `eon_ecs` test suite.
