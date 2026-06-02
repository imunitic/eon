# Query View Design — Unified `iter` + Typed View

## Status

**DRAFT — not finished.** Proposed. Supersedes the `iterN` terminator design in
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
|> Query.with_components [Position.name; Velocity.name]
|> Query.not_having Frozen.name
|> Query.iter (fun view ->
     let pos = View.get view Position.component in
     let vel = View.get view Velocity.component in
     ...)
```

- **Filtering** (`with_component` / `having` / `not_having`) stays string-keyed,
  so EDN-driven and modder systems drive membership exactly as before.
- **Value access** is via `View.get`, typed by the component *descriptor*'s
  phantom type — `'a Component_descriptor.t` is a `string` tagged with `'a`, so
  `View.get view Position.component : Position.t` with no `Obj.magic` at the
  call site.
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
- **Typed reads** use `Position.component` — the phantom-typed descriptor.

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

  val get : t -> 'a Component_descriptor.t -> 'a
  (** Typed read. Intended for components the query filtered for (guaranteed
      present). Raises if the component is absent on this entity — treat a raise
      as a programmer error (you read a component you did not require). *)

  val get_opt : t -> 'a Component_descriptor.t -> 'a option
  (** Typed read for components the query did NOT require — [None] if absent. *)
end
```

A `View.t` is just `(world, entity)`. `get` is `World.get_component` followed by
the existing unwrap; the phantom type on the descriptor carries the result type,
so no `Obj.magic` leaks to the user. `get` raises on absence; `get_opt` returns
the option directly.

---

## 5. Engine Layer: `Query` Builder

The filter-building half of the builder is unchanged. Only the terminators
change.

```ocaml
module Make (B : Query_backend.S) : sig
  type query

  val from : B.world -> query

  (* -- filters (string-keyed, unchanged) -- *)
  val with_component  : string -> query -> query
  val with_components : string list -> query -> query
  val having          : string -> query -> query
  val having_all      : string list -> query -> query
  val not_having      : string -> query -> query
  val not_having_any  : string list -> query -> query

  (* -- execution -- *)
  val iter  : (View.t -> unit) -> query -> unit
  val count : query -> int
end
```

`iter` replaces `iter1`..`iter4` entirely. The callback receives the per-entity
`View.t`; it pulls whatever typed values it needs. `View.entity view` gives the
entity id.

### `with_component` and `having` now collapse mechanically

Under `iterN`, `with_component` (fetched, contributes arity) and `having`
(presence only, no arity) were genuinely different. Under the view model there
is **no arity**, and values are pulled lazily — so both mean exactly "must be
present." Mechanically the backend receives one combined *required* set.

We keep both names as **intent-revealing API sugar**: `with_component` reads as
"I will read this value," `having` reads as "just filter." But they compile to
the same required list, and a component filtered by either can be read via
`View.get`. The three-list model is now effectively two: **required (present)**
and **excluded (absent)**.

---

## 6. Backend Contract Simplification

`Query_backend.S` loses `iter1`..`iter4` and gains a single entity-yielding
iterator:

```ocaml
module type S = sig
  type world

  val iter_entities :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> unit) ->
    unit

  val count :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    int
end
```

The backend's job collapses to **"yield matching entity ids."** It never touches
component values — value extraction lives entirely in `View`. This is both
simpler and a cleaner seam for the archetype backend (§8).

### `Sparse_set_backend`

- Combine `includes @ having` into the required AND-set.
- Call `Eon_ecs.Query.iter_entities raw required`.
- Inside the callback, apply `excludes` as a per-entity post-filter: skip the
  entity if `World.get_component world e ~name:x` is `Some _` for any `x` in
  `excludes`. (Excluded components are real registered `COMPONENT` modules, so
  `get_component` will not raise; `Some` ⇒ present ⇒ skip.)

This needs only the public `eon_ecs` surface — `iter_entities` + `get_component`.

---

## 7. Usage Examples

```ocaml
(* Two components + exclusion *)
Query.from world
|> Query.with_components [Position.name; Velocity.name]
|> Query.not_having Frozen.name
|> Query.iter (fun view ->
     let pos = View.get view Position.component in
     let vel = View.get view Velocity.component in
     ...)

(* Five components — impossible before, trivial now *)
Query.from world
|> Query.with_components
     [A.name; B.name; C.name; D.name; E.name]
|> Query.iter (fun view ->
     let a = View.get view A.component in
     (* ... e *) ())

(* Marker filter — Frozen required but never read *)
Query.from world
|> Query.with_component Position.name
|> Query.having Frozen.name
|> Query.iter (fun view ->
     let pos = View.get view Position.component in ...)

(* Optional read — Velocity if present *)
Query.from world
|> Query.with_component Position.name
|> Query.iter (fun view ->
     let pos = View.get view Position.component in
     match View.get_opt view Velocity.component with
     | Some vel -> ...
     | None -> ...)

(* EDN-driven / dynamic — filter list from data *)
Query.from world
|> Query.with_components required_names
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
|> Query.iter2 (fun e pos vel -> ...)

(* after *)
|> Query.iter (fun view ->
     let e   = View.entity view in
     let pos = View.get view Position.component in
     let vel = View.get view Velocity.component in
     ...)
```

`eon_ecs` change is additive (`iter_entities`) plus one contract fix
(`count` raises on unregistered). No existing `eon_ecs` signature changes.

---

## 10. Key Representation Rationale

Why filtering is **string-keyed** and value access is **typed-descriptor-keyed**,
and why two tempting alternatives were rejected.

### Strings for filtering, descriptors for reads

A query filters over several *different* component types at once, so the filter
list is inherently heterogeneous: `[Position.component; Velocity.component]` has
element types `Position.t Component_descriptor.t` and `Velocity.t
Component_descriptor.t`, which do not unify and cannot share a list without
erasure. The erased form of `'a Component_descriptor.t` *is* the string
(`type 'a t = string`). So "filter by descriptors" collapses back to strings the
moment more than one component is in the list — string-keyed filtering is the
natural type-erased shape of a multi-component set filter, not a concession.

Typed value access is the opposite case: `View.get view Position.component`
unifies **one** concrete type at the call site, so the descriptor's phantom is
useful and `Obj.magic` stays hidden. One-at-a-time typed reads work; a typed
*list* does not.

### Could the EDN parser resolve strings → types and drop strings entirely?

No. The parser can map `"Position"` to an existential `Pack : 'a
Component_descriptor.t -> packed`, but typed value access (`'a t -> 'a`) only
yields a usable `Position.t` when `'a` is statically known *at the call site* —
i.e. a concrete `Position` module in scope. Dynamically-resolved mod components
never have that, so the dynamic path is inherently erased regardless of what the
parser does. The parser can *validate existence* at parse time; it cannot hand
dynamic code a statically-typed value.

A real (optional) win does exist on the **engine-code** side: make `type 'a t`
**abstract** (today [component_descriptor.mli:18](../../eon_engine/component_descriptor.mli)
exposes it transparently, so the phantom is decorative — any string is a
descriptor at any type), then accept typed descriptors **per builder call**
(`with_component : 'a Component_descriptor.t -> query -> query`, erased internally
via `Component_descriptor.name`). Each call has one concrete type, so it checks
you passed a real registered component, not an arbitrary string. Keep
`with_components : string list` as the dynamic/EDN escape hatch. This is a
surface choice layered on top; the underlying key stays the string either way.

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
filtering, the EDN/registry/debug common currency) + typed descriptors (for
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

## 12. Open Decisions

1. **Callback shape.** `iter (fun view -> ...)` (entity via `View.entity`) vs.
   `iter (fun entity view -> ...)` (entity passed explicitly, matching the old
   `iterN` first-arg convention). Leaning toward view-only for a single uniform
   cursor; explicit-entity is slightly more ergonomic for the common
   despawn/relation case. Pick one.
2. **Keep `with_component` vs `having` as distinct names?** They are now
   mechanically identical (both "required present"). Keep both as intent sugar,
   or collapse to one (`require` / `with_component`) and drop `having`?
3. **`count` alignment scope.** Fix `count` to raise on unregistered in this same
   change (recommended, keeps the two primitives consistent), or land
   `iter_entities` first and align `count` separately?
