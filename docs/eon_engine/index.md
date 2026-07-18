# eon_engine — Notes & Design Sketches

Notes and design sketches for the `eon_engine` layer built on top of `eon_ecs`.

- Rendering — see `eon_engine/doc/rendering.mld` (odoc guide, `just docs` to render) for the current rendering architecture: `Render_stream`, `Render_stream_collector`, `Render_system`, `Rendering_backend`, command vocabulary, phase-ordered collection, multi-camera setup, backend wiring, and complete loop integration.
- Audio — see `eon_engine/doc/audio.mld` for `Audio_backend`, `Audio_command`, `Audio_command_buffer`: the command vocabulary, the shared per-frame buffer, voice budget prioritization, and a worked spatial-audio example.
- [parser_combinators_tutorial.md](parser_combinators_tutorial.md) — Introductory guide to parser combinators in OCaml using Angstrom. Builds intuition from scratch — useful background before reading the EDN parser docs.

The real, current EDN parser tutorial (OCaml 5 algebraic effects, not Angstrom) is `eon_edn/doc/index.mld`; `eon_engine/doc/prefab.mld` covers consumer-side EDN usage from the engine layer (prefab loading). See also `docs/design/eon_edn_parser.md` for the underlying design.
