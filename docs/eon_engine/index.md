# eon_engine — Notes & Design Sketches

Notes and design sketches for the `eon_engine` layer built on top of `eon_ecs`.

- [engine_render_graph.md](engine_render_graph.md) — Concise summary of the rendering architecture: RenderGraph (flat command collection), RenderPipeline (phase-based collectors), RenderingBackend (sole owner of render logic), and how they integrate with the ECS loop.
- [edn_parser.md](edn_parser.md) — EDN parser implementation using the Angstrom combinator library. Covers primitives, collections, and extension points for loading prefabs and config data.
- [parser_combinators_tutorial.md](parser_combinators_tutorial.md) — Introductory guide to parser combinators in OCaml using Angstrom. Builds intuition from scratch — useful background before reading the EDN parser docs.

See also `docs/design/eon_edn_parser.md` — alternative EDN parser design using OCaml 5 algebraic effects, moved to `docs/design/` as the basis for the standalone `eon_edn` project.
