# Design Documents

Authoritative architecture and design decision documents. These govern implementation; when in conflict with other docs, these win.

- [eon_engine_design.md](eon_engine_design.md) — Top-level design document for `eon_engine`: core philosophy, principles, module structure, and how the engine layer relates to `eon_ecs`.
- [eon_engine_query_design.md](eon_engine_query_design.md) — Design for the `eon_engine` query builder and backend abstraction. Covers the fluent `Query.from |> with_component |> iter2` API, `not_having` post-filtering, and the `Query_backend.S` signature.
- [rendering_layer_design.md](rendering_layer_design.md) — Full specification of the rendering layer: RenderGraph, RenderPipeline, RenderSystem, RenderingBackend, polymorphic variant command extension, frame flow, and the implementation roadmap (ecs-021 through ecs-026).
