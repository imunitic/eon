# Query View Design — Unified `iter` + Typed View

## Status

**IMPLEMENTED** (ecs-020). Supersedes the `iterN` terminator design in
[eon_engine_query_design.md](eon_engine_query_design.md) (§3 execution
functions, §6 three-list/arity semantics, and the §7 "write your own iter5"
rule). Composes cleanly with [world_module_design.md](world_module_design.md)
— see §8.

---

## 1. Problem

The current query layer terminates in arity-bound functions:

```ocaml
val iter1 : (Entity_id.t -> 'a -> unit)                   -> query -> unit
val iter2 : (Entity_id.t -> 'a -> 'b -> unit)             -> query -> unit
val iter3 : (Entity_id.t -> 'a -> 'b -> 'c -> unit)       -> query -> unit
val iter4 : (Entity_id.t -> 'a -> 'b -> 'c -> 'd -> unit) -> query -> unit
```

Three problems:

1. **Per-arity boilerplate.** Queries over five or more components aren't
   *impossible* — you can hand-write an `iter5`/`iter6` engine-layer helper that
   iterates the matched entities and pulls each value via `World.get_component`,
   touching neither `eon_ecs` core nor `Query_backend.S`. But every arity is a
   separate hand-written, hand-maintained function, and the built-in `iter1`..
   `iter4` instead push the duplication down into both `eon_ecs` core and every
   `Query_backend.S` implementation. Either way, each new arity costs a new
   copy-pasted function. That recurring boilerplate is the real cost — exactly
   what a single `iter` + view eliminates.
2. **Runtime arity check.** The builder accumulates an untyped `includes : string
   list`, so `iterN` must `invalid_arg` when the list length ≠ N. The compiler
   cannot help.
3. **No optional reads.** `iterN` requires every fetched component to be present
   for *every* matched entity. "Read `Velocity` if the entity happens to have it"
   is inexpressible.

The root cause: `iterN` delivers component values **positionally** (`'a -> 'b ->
…`), and positional typing is exactly what forces one function per arity. You
cannot vary the count of statically-typed positional arguments without
type-level lists.

The fix is to **stop delivering values positionally**. Filtering stays
string-based (modder-friendly); value access moves to a typed *view* the
callback pulls from on demand.

---

## 2. Core Idea

One terminator, a typed view:

```ocaml
Query.from world
|> Query.having_all [Position.name; Velocity.name]
|> Query.not_having Frozen.name
|> Query.iter (fun view ->
     let pos = View.get view (module Position) in
     let vel = View.get view (module Velocity) in
     ...)
```

- **Filtering** (`having` / `having_all` / `not_having` / `not_having_any`) stays
  string-keyed, so EDN-driven and modder systems drive membership exactly as before.
- **Value access** is via `View.get`, using OCaml 5.5 module-dependent function
  syntax — `View.get view (module Position) : Position.t` with no `Obj.magic` at
  the call site. The module IS the type witness; no separate descriptor argument.
- **Arbitrary arity**, one function. No `iterN`, no cap, no runtime arity check.
- **Optional reads** fall out for free (`View.get_opt`).

### The `COMPONENT` interplay

Per [component.mli](../../eon_engine/component.mli), every component is a module
conforming to `COMPONENT`:

```ocaml
module type S = sig
  type t
  val component : t Component_descriptor.t   (* typed descriptor *)
  val name      : string                     (* the registry key *)
end
```

So at the engine layer you never write a string literal:

- **Filters** use `Position.name` — the string key (modder-compatible).
- **Typed reads** use `(module Position)` — the module itself, via the MDF signature.

Both come from the same module, so a filtered component and its typed read can
never drift apart by a typo.

---

## 3. `eon_ecs` Addition: `iter_entities`

The engine cannot pick the smallest sparse set to iterate (sparse sets are not
part of the public `eon_ecs` surface), so the smallest-set-first iteration must
live in core. This is the **one** `eon_ecs` change, and it is a direct
generalization of the existing `Query.count`:

```ocaml
(** Iterate every alive entity that has all of the named components, choosing
    the smallest sparse set as the iteration base. Yields only the entity id —
    typed values are read via [World.get_component].

    Raises if any name was never registered (consistent with
    [World.get_component] / [add_component]). *)
val iter_entities : t -> string list -> (Entity_id.t -> unit) -> unit
```

Implementation is `Query.count`'s intersection body
([query.ml:122](../../eon_ecs/query.ml)) with the counter replaced by the
callback — pick smallest base set, iterate, keep entities present in all others,
call `f (eid_of world id)`.

### Semantics follow eon_ecs principles, not a new rule

`iter_entities` does **not** invent a "missing component ⇒ empty result" rule.
It follows the registered-vs-present distinction that already governs the whole
`World` component API:

| Input | Behaviour |
|---|---|
| name never registered | **raises** (programmer error — same as `get_component`) |
| registered, not on this entity | normal intersection miss — entity excluded, no raise |

### `count` alignment (contract fix)

`Query.count` today builds its set list with `List.filter_map (storage world)`,
which **silently drops** an unregistered name instead of raising — so `count
[Position.name; "never_registered"]` returns the `Position` count rather than
raising. That is inconsistent with `get_component` and with the new
`iter_entities`. This refactor brings `count` in line: an unregistered name
raises. After this change `count` and `iter_entities` agree, and both follow the
single eon_ecs convention.

---

## 4. Engine Layer: `View`

```ocaml
module View : sig
  type t

  val entity : t -> Eon_ecs.Entity_id.t
  (** The entity this view points at. *)

  val get : t -> (module C : Component.S) -> C.t
  (** Typed read using OCaml 5.5 module-dependent function syntax. Intended for
      components the query filtered for (guaranteed present). Raises if the
      component is absent on this entity — treat a raise as a programmer error
      (you read a component you did not require). *)

  val get_opt : t -> (module C : Component.S) -> C.t option
  (** Typed read for components the query did NOT require — [None] if absent. *)
end
```

A `View.t` is just `(world, entity)`. `get` calls `World.get_component` with
`M.component` and unwraps the result; the MDF return type `C.t` is statically
enforced by the compiler — no `Obj.magic` leaks to the user. `get` raises on
absence; `get_opt` returns the option directly.

---

## 5. Engine Layer: `Query` Builder

The filter-building half of the builder is unchanged. Only the terminators
change.

```ocaml
module Make (B : Query_backend.S) : sig
  type query

  val from : B.world -> query

  (* -- filters (string-keyed) -- *)
  val having         : string -> query -> query
  val having_all     : string list -> query -> query
  val not_having     : string -> query -> query
  val not_having_any : string list -> query -> query

  (* -- execution -- *)
  val iter  : (View.t -> unit) -> query -> unit
  val count : query -> int
end
```

`iter` replaces `iter1`..`iter4` entirely. The callback receives the per-entity
`View.t`; it pulls whatever typed values it needs. `View.entity view` gives the
entity id.

`with_component` and `with_components` are **removed**. Under the view model
there is no arity and values are pulled lazily — "must be present to read" and
"must be present as a marker" are mechanically identical. `having` / `having_all`
cover both roles honestly. The filter vocabulary is now two symmetric pairs:
**`having` / `having_all`** (required present) and
**`not_having` / `not_having_any`** (required absent).

---

## 6. Backend Contract Simplification

`Query_backend.S` loses `iter1`..`iter4` and gains a single entity-yielding
iterator:

```ocaml
module type S = sig
  type world

  val iter_entities :
    world ->
    required:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> unit) ->
    unit

  val count :
    world ->
    required:string list ->
    excludes:string list ->
    int
end
```

The backend's job collapses to **"yield matching entity ids."** It never touches
component values — value extraction lives entirely in `View`. The `includes` /
`having` split disappears at the backend boundary: the builder merges both into
one `required` list before dispatch. This is both simpler and a cleaner seam for
the archetype backend (§8).

### `Sparse_set_backend`

- Pass `required` directly to `W.iter_entities world required`.
- Inside the callback, apply `excludes` as a per-entity post-filter via
  `W.has_component world entity name` — returns `false` for unregistered or
  absent components, so no raise risk on excluded names.

This needs only the `World.S` surface — `iter_entities` + `has_component`.
No reference to `Eon_ecs.World.t` or `Eon_ecs.Query` anywhere in the backend.

---

## 7. Usage Examples

```ocaml
(* Two components + exclusion *)
Query.from world
|> Query.having_all [Position.name; Velocity.name]
|> Query.not_having Frozen.name
|> Query.iter (fun view ->
     let pos = View.get view (module Position) in
     let vel = View.get view (module Velocity) in
     ...)

(* Five components — impossible before, trivial now *)
Query.from world
|> Query.having_all [A.name; B.name; C.name; D.name; E.name]
|> Query.iter (fun view ->
     let a = View.get view (module A) in
     (* ... e *) ())

(* Marker filter — Frozen required but not read; Position read *)
Query.from world
|> Query.having Position.name
|> Query.having Frozen.name
|> Query.iter (fun view ->
     let pos = View.get view (module Position) in ...)

(* Optional read — Velocity if present *)
Query.from world
|> Query.having Position.name
|> Query.iter (fun view ->
     let pos = View.get view (module Position) in
     match View.get_opt view (module Velocity) with
     | Some vel -> ...
     | None -> ...)

(* EDN-driven / dynamic — filter list from data *)
Query.from world
|> Query.having_all required_names
|> Query.not_having_any excluded_names
|> Query.count
```

---

## 8. Relationship to the Archetype Backend

This aligns with the direction already settled in
[world_module_design.md](world_module_design.md): the archetype
backend's job is to answer **"which entities match,"** never **"hand me the
values"** (values always come from the authoritative sparse sets via
`get_component`). The new `iter_entities` backend method *is* that contract.
`Archetype_backend` implements `iter_entities` by walking its index; the view
reads values exactly as the sparse-set backend's view does. No new coupling.

---

## 9. Migration

Breaking change at the `eon_engine` layer. Every `iterN` call site rewrites to a
single `iter` with `View.get` reads:

```ocaml
(* before *)
|> Query.with_component Position.name
|> Query.with_component Velocity.name
|> Query.iter2 (fun e pos vel -> ...)

(* after *)
|> Query.having Position.name
|> Query.having Velocity.name
|> Query.iter (fun view ->
     let pos = View.get view (module Position) in
     let vel = View.get view (module Velocity) in
     ...)
```

`eon_ecs` change is additive (`iter_entities`) plus one contract fix
(`count` raises on unregistered). No existing `eon_ecs` signature changes.

---

## 10. Key Representation Rationale

Why filtering is **string-keyed** and value access is **module-keyed**,
and why two tempting alternatives were rejected.

### Strings for filtering, modules for reads

A query filters over several *different* component types at once, so the filter
list is inherently heterogeneous: a typed filter list would have elements of type
`Position.t Component_descriptor.t` and `Velocity.t Component_descriptor.t`,
which do not unify and cannot share a list without erasure. The erased form of
`'a Component_descriptor.t` *is* the string (`type 'a t = string`). So
"filter by descriptors" collapses back to strings the moment more than one
component is in the list — string-keyed filtering is the natural type-erased
shape of a multi-component set filter, not a concession.

Typed value access is the opposite case: `View.get view (module Position)`
involves **one** statically-known module at the call site. OCaml 5.5
module-dependent functions (MDFs) make the return type `C.t` depend on the
module argument `C`, so `View.get view (module Position) : Position.t` with no
`Obj.magic` at the call site. The module IS the type witness — `Component.S`
bundles the descriptor (`val component`) and the data type (`type t`) in one
place, leaving no gap between "which component" and "what type it holds".

### Could the EDN parser resolve strings → types and drop strings entirely?

No. The parser can map `"Position"` to an existential `Pack : 'a
Component_descriptor.t -> packed`, but typed value access only yields a usable
`Position.t` when the `Position` module is statically in scope at the call site.
Dynamically-resolved components never have that, so the dynamic path is
inherently erased regardless of what the parser does. The parser can *validate
existence* at parse time; it cannot hand dynamic code a statically-typed value.
The same constraint applies to MDF: `View.get view (module X)` requires `X` to
be a compile-time-known module — you cannot pass a first-class module computed at
runtime.

### Why not open polymorphic variant keys (like the data/service plane)?

The data/service plane keys by open variant tags (`add_data : t -> [> ] -> 'a ->
unit`). Tempting to reuse here — and tags do have one edge: `[`Position;
`Velocity]` unifies to a clean homogeneous `[> ... ] list`, dodging the erasure
above. But variants are a poorer fit for *components* for two reasons:

1. **No value type.** A tag `` `Position `` is just its runtime hash; it carries
   nothing about `Position.t`. That is why `get_data : t -> [> ] -> 'a option`
   has a caller-chosen `'a` with `Obj.magic` underneath — acceptable when you
   fetch one service whose type you already know, but it throws away the typed
   `View.get` that this whole design exists to provide. Keying components by
   variants puts bulk component reads back on caller-asserted `Obj.magic`.
2. **Compile-time-only and one-way, but components cross the runtime-string
   boundary.** You cannot build a polymorphic variant tag from a runtime string
   (the tag set is static), nor recover `"Position"` from `` `Position `` (the
   hash is one-way). EDN files literally contain `"Position"`, the core registry
   keys by `name:string`, and debugging wants printable names. The data/service
   plane escapes this only because its keys are always written in OCaml code,
   never parsed from data and never needing a name. Components do not have that
   luxury, so a variant key is a redundant third representation that *also* can't
   survive the EDN path.

Conclusion: open variants shine when every key is statically known in code
(data/services); components straddle the static/dynamic line, so strings (for
filtering, the EDN/registry/debug common currency) + modules via MDF (for
one-at-a-time typed reads) remain the right split.

### Prior art

The per-entity typed-cursor shape is EnTT's `view` (`view.get<Position>(entity)`).
The divergence here: EnTT keys *both* filter and access by compile-time type;
this design keys filtering by runtime string (for EDN/modder parity) and access
by typed descriptor — a deliberate hybrid driven by the EDN requirement.

---

## 11. What NOT to Do

- **Do not type the filter lists.** Filters stay `string` (via `Component.name`)
  so EDN/modder systems and OCaml game code share one path. Typing the value
  *read* (via the descriptor) is enough.
- **Do not pass values through the backend.** The backend yields entity ids
  only. Any backend that fetches and forwards typed values reintroduces the
  arity problem and `Obj.magic` in the backend.
- **Do not add `iterN` back as "convenience."** A single `iter` + `View.get`
  covers every arity; convenience wrappers would re-fork the API.
- **Do not let `View.get` silently return a default on absence.** Absence of a
  *required* component is a programmer error → raise. Optional access is the
  explicit `get_opt`.

---

## 12. Decisions

1. **Callback shape** — `iter (fun view -> ...)`. The view is the cursor; passing
   entity separately would be redundant (`View.entity view` is explicit enough).
   `iter (fun entity view -> ...)` is legacy thinking from the positional `iterN`
   model.

2. **`with_component` vs `having`** — `with_component` / `with_components` are
   **removed**. `having` / `having_all` / `not_having` / `not_having_any` are the
   complete filter vocabulary. `having` is honest regardless of whether you read
   the value; the symmetric pair with `not_having` is cleaner than mixing two
   names for the same concept.

3. **`count` alignment scope** — fix `count` to raise on unregistered in the same
   change as `iter_entities` (ecs-020). Keeping the two primitives consistent
   matters more than minimising the `eon_ecs` diff.
