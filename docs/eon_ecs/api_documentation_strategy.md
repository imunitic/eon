# Eon ECS API Documentation Strategy

This note captures a practical documentation strategy for Eon ECS, aimed at producing API docs that are closer to the usability of Rust and Go documentation.

## Goals

1. Keep API contracts authoritative and stable.
2. Include enough context for users to understand behavior, not just signatures.
3. Provide examples that are easy to discover and, where possible, verified.

## Where Documentation Should Live

### 1. Public `.mli` files are the source of truth

- Use `eon_ecs/src/eon_ecs.mli` as the canonical package surface.
- Use public submodule `.mli` files for detailed behavior and invariants.
- Anything not exported from `eon_ecs/src/eon_ecs.mli` is internal and can be documented more lightly.

### 2. `README.md` and `docs/*.md` for narrative guides

Use these for:

- architecture and mental models
- tutorials and onboarding
- usage patterns and workflows
- migration notes / release notes

Keep these aligned with the `.mli` contracts.

## Odoc + Examples

`odoc` supports code examples in doc comments, so include examples directly in `.mli` comments.

Example style:

```ocaml
(** Move a position component by velocity.

    {[
      let e = World.create_entity world in
      World.add_component world e ~name:"Position" (0.0, 0.0);
      World.add_component world e ~name:"Velocity" (1.0, 0.0);
      (* ... *)
    ]}
*)
val update_position : ...
```

## Important Tooling Distinction

- `odoc` renders docs and examples.
- `odoc` does not execute examples.
- `ocaml-mdx` is the tool to execute and verify documentation snippets.

Recommended practice:

1. Keep API-adjacent examples in `.mli` comments for discoverability.
2. Keep runnable tutorial examples in markdown files (`README.md`, `docs/*.md`) and validate with `mdx`.
3. For critical examples, mirror them in tests to prevent drift.

## What to Document in Public APIs

For each public module/value/type, document:

1. Purpose and scope.
2. Preconditions and postconditions.
3. Ordering/semantic guarantees (especially ECS invariants).
4. Determinism implications.
5. Performance characteristics when relevant.
6. Small usage example.

For Eon ECS specifically, always be explicit about:

- bus order (`collect` and `drain` sequencing)
- command/event/signal semantics
- fixed/hybrid vs variable timestep behavior
- when state is expected to be visible (e.g., after drains)

## Suggested Style Guide

Use this section template in `.mli` docs:

1. One-line summary.
2. Behavioral details.
3. Invariants / guarantees.
4. Example (`{[ ... ]}` block).
5. See-also links to related modules.

Keep examples short and focused on one concept each.

## Maintenance Rules

1. Any public API change in `eon_ecs/src/eon_ecs.mli` should include documentation updates in the same change.
2. Any behavior change to ECS invariants must update:
   - relevant `.mli` docs
   - `README.md` examples
   - `AGENTS.md` invariants section
3. Regularly run doc tooling to catch broken references and stale examples.

