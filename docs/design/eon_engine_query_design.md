# Eon Engine — Query Layer Design

> **PARTIALLY SUPERSEDED.** The `Query_backend.S` signature (§1), the
> `Sparse_set_backend` (§2), and the `Query.Make` builder (§3) have been
> implemented but with a different API than described here:
>
> - `Query_backend.S` has only `iter_entities` + `count` (not `iter1..iter4`).
>   See the actual `eon_engine/query_backend.mli`.
> - `iter1..iter4` terminators and `with_component` are replaced by a single
>   `iter` + `View.get`. See [query_view_design.md](query_view_design.md).
> - `Archetype_backend` and the `Fallback` functor were **dropped** as premature.
>   See [world_module_design.md](world_module_design.md).
> - `eon_ecs` core received `iter_entities` (ecs-020) and will receive
>   `Dependency_graph` (ecs-021) — the "frozen at 1.0" framing in §9 is stale.
>
> This document is retained as historical context for the design evolution.

## Context

`eon_ecs` core ships a minimal `Query` module with `iter1`/`iter2`/`iter3`/`iter4` functions
keyed by strings. This is stable and will not change.

`eon_engine` builds a richer query layer **on top** of the core without touching it.
This document describes what needs to be implemented in `eon_engine`.

---

## Layer Overview

```
game code
    ↓
Query.Make(B)          ← builder API (eon_engine)
    ↓
Query_backend.S        ← pluggable backend signature (eon_engine)
    ↓
Eon_ecs.Query          ← core primitives (eon_ecs, unchanged)
```

---

## 1. `Query_backend.S` — Backend Signature

File: `eon_engine/query_backend.mli`

```ocaml
module type S = sig
  type world
  (** Abstract world type — decouples backend from Eon_ecs.World.t.
      Sparse_set_backend sets this to Eon_ecs.World.t.
      A future full archetype storage backend sets it to its own world type. *)

  val iter1 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> unit) ->
    unit

  val iter2 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> 'b -> unit) ->
    unit

  val iter3 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> 'b -> 'c -> unit) ->
    unit

  val iter4 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> 'b -> 'c -> 'd -> unit) ->
    unit

  val count :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    int
end
```

**Key design decision**: `type world` is abstract. This future-proofs the signature for
a `Storage_backend.S` / `World.Make` story where the world type itself is pluggable.

---

## 2. Shipped Backends

### `Sparse_set_backend` *(implemented — ecs-016 complete)*

Files: `eon_engine/sparse_set_backend.ml` / `sparse_set_backend.mli`

- `type world = W.t` where `W : World.S` — the backend is a functor `Make(W : World.S)`
- Delegates to `W.iter_entities` for smallest-set-first entity iteration
- Applies `excludes` as a per-entity post-filter via `W.has_component`
- No reference to `Eon_ecs.World.t` or `Eon_ecs.Query` — works entirely through `World.S`
- This is the **default backend** — thin wrapper, no new storage logic

### `Archetype_backend` *(DROPPED — premature optimisation; see world_module_design.md)*

> **See [world_module_design.md](world_module_design.md) for the authoritative design.**
> The summary below is kept for orientation only.

- `type world = Eon_engine.World.Tracked.t` (post ecs-019 consolidation)
- Uses a dirty-flag tracking functor (`World.Make(Dirty_flag)`) to know when to rebuild the index
- Archetype service is lazily initialised on first query — no explicit registration needed
- Uses the index to skip entity groups that cannot match includes/excludes
- Falls back to sparse set reads for component values (archetypes are a **query
  acceleration cache**, NOT a replacement storage — sparse sets remain authoritative)

### `Fallback` functor *(DROPPED — premature; no archetype backend to fall back from)*

File: `eon_engine/query_backend_fallback.ml`

```ocaml
module Make (Primary : Query_backend.S) (Secondary : Query_backend.S)
  : Query_backend.S
```

- Tries `Primary` first; falls back to `Secondary` on failure
- **Explicit opt-in** — the engine never uses this automatically
- Users who want archetype-with-sparse-fallback compose it themselves:

```ocaml
module My_backend = Query_backend_fallback.Make
  (Query_backend_archetype)
  (Query_backend_sparse)
```

**No hidden fallbacks anywhere. Users declare their choice at compile time.**

---

## 3. `Query.Make(B)` — The Builder Functor

File: `eon_engine/query.ml`

```ocaml
module Make (B : Query_backend.S) : sig

  type query
  (** Accumulated query constraints. Not resolved until iter/count is called. *)

  val from : B.world -> query
  (** Entry point. Captures the world, starts an empty query. *)

  (** -- Component value fetching --
      These contribute to callback arity. Order defines callback argument order. *)
  val with_component  : string -> query -> query
  val with_components : string list -> query -> query

  (** -- Presence filters (markers) --
      Must be present but value is NOT fetched. Do NOT contribute to arity.
      Use case: `having "Frozen"` filters to frozen entities without pulling
      the Frozen value into the callback. *)
  val having      : string -> query -> query
  val having_all  : string list -> query -> query

  (** -- Exclusion filters --
      Must be absent. Do NOT contribute to arity. *)
  val not_having     : string -> query -> query
  val not_having_any : string list -> query -> query

  (** -- Execution --
      Callback argument order matches with_component call order.
      iter1 expects exactly 1 with_component, iter2 expects exactly 2, etc.
      Raises invalid_arg if arity does not match. *)
  val iter1 : (Entity_id.t -> 'a -> unit)                      -> query -> unit
  val iter2 : (Entity_id.t -> 'a -> 'b -> unit)                -> query -> unit
  val iter3 : (Entity_id.t -> 'a -> 'b -> 'c -> unit)          -> query -> unit
  val iter4 : (Entity_id.t -> 'a -> 'b -> 'c -> 'd -> unit)    -> query -> unit

  val count : query -> int

end
```

### Internal query record

```ocaml
type query = {
  world    : B.world;
  includes : string list;  (* with_component/with_components — fetched, count toward arity *)
  having   : string list;  (* having/having_all — presence check only, no value, no arity *)
  excludes : string list;  (* not_having/not_having_any — must be absent *)
}
```

The backend receives all three lists. What it does with them:
- `includes` → fetch values, pass to callback
- `having` → check presence, skip entity if absent
- `excludes` → check presence, skip entity if present

---

## 4. User Wiring (Compile Time)

Users choose their backend **once** via functor application. No runtime switching.

```ocaml
(* Default — sparse sets, no overhead *)
module World = Eon_engine.World.Default
module Query = Eon_engine.Query.Default

(* With archetype acceleration cache — one module swap *)
module World = Eon_engine.World.Tracked
module Query = Eon_engine.Query.Archetype

(* Explicit fallback — user's choice, user's responsibility *)
module World = Eon_engine.World.Tracked
module Query = Eon_engine.Query.Make(
  Eon_engine.Query_backend_fallback.Make
    (Eon_engine.Archetype_backend.Default)
    (Eon_engine.Sparse_set_backend.Default)
)

(* Roll your own backend *)
module My_backend : Eon_engine.Query_backend.S = struct
  type world = Eon_engine.World.Default.t
  ...
end
module Query = Eon_engine.Query.Make(My_backend)
```

---

## 5. Usage — Final API Shape

```ocaml
(* Static game code *)
Query.from world
|> Query.with_component "Position"
|> Query.with_component "Velocity"
|> Query.not_having "Frozen"
|> Query.iter2 (fun entity pos vel -> ...)

(* Marker filter — Frozen present but not in callback *)
Query.from world
|> Query.with_component "Position"
|> Query.having "Frozen"
|> Query.iter1 (fun entity pos -> ...)

(* EDN-driven / dynamic component lists *)
Query.from world
|> Query.with_components required_components
|> Query.having_all required_markers
|> Query.not_having_any excluded_components
|> Query.count

(* Mixed static and dynamic *)
Query.from world
|> Query.with_component "Position"
|> Query.with_components extra_components
|> Query.not_having "Dead"
|> Query.iter1 (fun entity pos -> ...)
```

String keys throughout. Same API for OCaml game code and EDN-driven systems.
No special cases, no two paths, modder friendly.

---

## 6. Three-List Semantics Summary

| Method | List | Backend behaviour |
|---|---|---|
| `with_component` / `with_components` | `includes` | Fetch value, pass to callback, counts toward arity |
| `having` / `having_all` | `having` | Check presence only, skip if absent, no arity contribution |
| `not_having` / `not_having_any` | `excludes` | Check presence only, skip if present, no arity contribution |

---

## 7. What NOT to Do

- **Do not add hidden fallback logic** anywhere. If the archetype service is missing,
  `Archetype_backend` raises. Users who want fallback use `Fallback` explicitly.
- **Do not use open variants or COMPONENT modules** in this layer. String keys are
  the universal runtime key — modder EDN files, the core registry, and this API
  all speak strings.
- **Do not add a `fold` primitive** to `Query_backend.S` — it cannot implement
  typed iterN functions without `Obj.magic` and provides no clean escape hatch.
  If a user needs `iter5` they write it the same way `iter4` is written.
- **Do not touch `eon_ecs` core** — it is stable and will not change.

---

## 8. Component ID Generation (Engine Layer)

When the engine registers components it auto-generates IDs. Users never see or
manage IDs. The core `register_component ~id:int` still exists but the engine
wraps it:

```ocaml
(* eon_engine/component_id.ml *)
let counter = Atomic.make 0
let next () = Atomic.fetch_and_add counter 1

(* eon_engine — wraps core registration *)
let register_component world name =
  let id = Component_id.next () in
  World.register_component world ~name ~id
```

IDs are unique integers. Nothing in the engine or game layer uses them for
computation — they exist only to satisfy the core's `register_component` signature.

---

## 9. Relationship to `eon_ecs` Core

`eon_ecs` core is frozen at 1.0. Nothing in this design requires changing it:

| Core module | Engine usage |
|---|---|
| `World.t` | Stored as `world.core` inside `Eon_engine.World.t`; accessed only through `World.S` delegation |
| `World.iter_entities` | Called by `Eon_engine.World` to satisfy `World.S`; in turn called by `Sparse_set_backend` |
| `World.register_component` | Called by engine's `register_component` wrapper |
| `World.get_service` | Used by `Archetype_backend` to locate the lazily-created archetype index |
| `Component.component` | Unchanged, core concern only |
