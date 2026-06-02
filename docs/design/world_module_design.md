# Eon Engine — World Module Design

## Status

**DRAFT — not finished.** Earlier revisions of this document described an
archetype cache (Bitset, Archetype_index, Archetype_backend) and a `World.Make`
functor parameterised over a `TRACKING` signature. Both have been dropped as
premature optimisations. This document covers only what is worth implementing now:
the `World.S` signature, the per-world `Id_counter`, and the
`Sparse_set_backend.Make(W : World.S)` functor.

The `Archetype_backend` sections of `eon_engine_query_design.md` are superseded
by this document. The rest of that document (query builder, `Sparse_set_backend`,
`Fallback` functor) remains authoritative.

---

## What This Document Covers

Three tightly-related pieces of `eon_engine` infrastructure:

- **`World.S`** — the uniform signature that all engine code depends on.
  Backends, query builders, and game code program to this signature rather than
  to `Eon_ecs.World` directly. It wraps registration, mutation, and the component
  plane, providing a single coherent API.
- **Per-world `Id_counter`** — replaces any global `Atomic` counter in
  `Component_descriptor`. Each world allocates dense ids `0, 1, 2, …`
  independently; ids have no meaning across worlds.
- **`Sparse_set_backend.Make(W : World.S)`** — turns the backend into a functor
  so the world type is swappable without rewriting the backend. `Default =
  Make(World)` is the concrete instance everyone uses.

Everything else — a `TRACKING` signature, a `World.Make` functor, `No_tracking`,
`Dirty_flag` — is deferred. If benchmarks eventually justify a query-acceleration
cache or a debug-tooling hook, those can be added as a functor layer on top of
the concrete `World` module without changing any existing code.

---

## 1. `World.S` — Uniform World Signature

File: `eon_engine/world.mli`

```ocaml
module type S = sig
  type t

  val create               : unit -> t

  val create_entity        : t -> Entity_id.t
  val add_component        : t -> Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
  val set_component        : t -> Entity_id.t -> 'a Component_descriptor.t -> 'a -> unit
  val get_component        : t -> Entity_id.t -> 'a Component_descriptor.t -> 'a option
  val remove_component     : t -> Entity_id.t -> 'a Component_descriptor.t -> unit
  val remove_all_components: t -> Entity_id.t -> unit
  val destroy_entity       : t -> Entity_id.t -> unit
  val register             : t -> 'a Component_descriptor.t -> Component_descriptor.registration_result
  val is_registered        : t -> 'a Component_descriptor.t -> bool
  val count_entities       : t -> int
  val is_alive             : t -> Entity_id.t -> bool

  (** Data and service plane (ecs-019) *)
  val add_data    : t -> ([> ] as 'k) -> 'a -> unit
  val set_data    : t -> ([> ] as 'k) -> 'a -> unit
  val get_data    : t -> ([> ] as 'k) -> 'a option
  val count_data  : t -> int
  val add_service : t -> ([> ] as 'k) -> 'a -> unit
  val get_service : t -> ([> ] as 'k) -> 'a option
  val list_services : t -> int list

  (** Extension API for backends — not for game code. *)
  val to_raw : t -> Eon_ecs.World.t
end
```

`to_raw` exposes the underlying `Eon_ecs.World.t` so that backends
(`Sparse_set_backend`, future backends) can call `Eon_ecs.Query` directly
without the engine world needing to re-expose every query primitive. Game code
never calls this.

---

## 2. Concrete `World` Module

File: `eon_engine/world.ml`

```ocaml
type t = {
  raw                    : Eon_ecs.World.t;
  mutable[@atomic] next_id : int;   (* per-world dense component id allocator *)
}

let create () =
  { raw     = Eon_ecs.World.create ();
    next_id = 0 }

let to_raw world = world.raw

let register world comp =
  let name = Component_descriptor.name comp in
  if Component_descriptor.is_registered world.raw comp then
    Component_descriptor.Already_registered
  else begin
    let id = Atomic.Loc.fetch_and_add [%atomic.loc world.next_id] 1 in
    Eon_ecs.World.register_component world.raw ~name ~id;
    Component_descriptor.Registered
  end

(* Structural mutations *)
let add_component world entity comp value =
  Eon_ecs.World.add_component world.raw entity
    ~name:(Component_descriptor.name comp) value

let remove_component world entity comp =
  Eon_ecs.World.remove_component world.raw entity
    ~name:(Component_descriptor.name comp)

let remove_all_components world entity =
  Eon_ecs.World.remove_all_components world.raw entity

let destroy_entity world entity =
  Eon_ecs.World.destroy_entity world.raw entity

(* Value mutation — does NOT change component signature *)
let set_component world entity comp value =
  Eon_ecs.World.set_component world.raw entity
    ~name:(Component_descriptor.name comp) value

(* ... remaining delegations (get_component, create_entity, etc.) ... *)
```

`next_id` uses the OCaml 5.4 atomic record field syntax (`mutable[@atomic]`),
which stores the integer inline in the record rather than as a separate heap
object. Compared to `int Atomic.t`, this eliminates one indirection and one
allocation per world. The `[%atomic.loc world.next_id]` ppx produces an
`Atomic.Loc.t` pointing at the field, which `Atomic.Loc.fetch_and_add` then
operates on atomically. Registration is initialisation-time only, never on the
hot path, so the atomic cost is negligible in practice regardless — but the
unboxed form is the right default on 5.4+.
IDs are dense per world (`0, 1, 2, …`) and have no meaning across worlds.

`Component_descriptor` is a pure name wrapper: `component` (constructor), `name`
(accessor), `is_registered` (checks via `find_component`), and
`registration_result` (`Registered | Already_registered`). It does not generate
ids or hold mutable state — id generation lives entirely in `World.register`.

---

## 3. `Sparse_set_backend.Make(W : World.S)`

File: `eon_engine/sparse_set_backend.ml`

```ocaml
module Make (W : World.S) : Query_backend.S with type world = W.t = struct
  type world = W.t

  let iter1 world ~includes ~having ~excludes f =
    let raw = W.to_raw world in
    Eon_ecs.Query.iter1 raw ~includes ~having ~excludes f

  let iter2 world ~includes ~having ~excludes f =
    let raw = W.to_raw world in
    Eon_ecs.Query.iter2 raw ~includes ~having ~excludes f

  (* iter3, iter4, count — same pattern *)
end

module Default = Make(World)
```

`W.to_raw` is called once per query execution, not per entity. The cost is a
single record field access. Everything else delegates directly to `Eon_ecs.Query`.

The functor lets the world type change — e.g. if a `World.Make(T : TRACKING)`
functor is added later — without touching the backend at all. Existing code that
uses `Sparse_set_backend.Default` stays unaffected; code that needs a different
world applies `Make` once at the module level.

`Default` is the only instance shipped by the engine. Users who introduce a
custom world type apply `Make` themselves:

```ocaml
module My_world = Eon_engine.World.Make(My_tracking)   (* hypothetical future *)
module My_backend = Eon_engine.Sparse_set_backend.Make(My_world)
module Query = Eon_engine.Query.Make(My_backend)
```

---

## 4. Module Stack

```
World                            ← concrete, no functor
  satisfies World.S

Sparse_set_backend.Make(W : World.S)   ← backends depend on World.S
  Sparse_set_backend.Default = Sparse_set_backend.Make(World)

Query.Make(B : Query_backend.S)        ← unchanged from query design doc
  Query.Default = Query.Make(Sparse_set_backend.Default)
```

If a `TRACKING` seam is ever needed, a `World.Make(T : TRACKING)` functor can
be layered on top of the concrete `World` module. All backends already depend on
`World.S`, so the upgrade requires no changes in `Sparse_set_backend` or `Query`.

---

## 5. Mutation Signals *(out of scope)*

Independently of any dirty flag, `eon_engine.World` mutation wrappers will emit
signals on structural changes as a general extensibility hook. This is deferred
and is a separate concern from the `Id_counter`.

---

## 6. User Wiring

Default setup — nothing to configure:

```ocaml
let world = Eon_engine.World.create ()
(* Use Eon_engine.Query.Default for queries. *)
```

---

## 7. What NOT to Do

- **Do not reintroduce a global `Atomic` counter in `Component_descriptor`** —
  per-world dense ids are the design; a global counter creates cross-world id
  collisions and global mutable state.
- **Do not bypass `World.register` by calling
  `Eon_ecs.World.register_component` directly** — the per-world id counter only
  advances inside the `register` wrapper; bypassing it produces duplicate ids.
- **Do not assume component ids are globally unique** — they are dense per world;
  `"Position"` is id `0` in every world that registers it first.
- **Do not add external opam dependencies** unless strictly necessary and not
  achievable with stdlib alone.
