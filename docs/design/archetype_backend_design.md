# Eon Engine — World Functor & Tracking Design

## Status

**DRAFT — not finished.** The concrete archetype cache (Bitset,
Archetype_index, Archetype_backend) described in earlier revisions of this
document has been dropped as premature. This document now covers the
extensibility spine that remains: the `World.Make` functor, the per-world
`Id_counter`, and the `TRACKING` signature.

The `Archetype_backend` sections of `eon_engine_query_design.md` are superseded
by this document. The rest of that document (query builder, `Sparse_set_backend`,
`Fallback` functor) remains authoritative.

---

## What This Document Covers

Three tightly-related pieces of `eon_engine` infrastructure:

- **`World.Make(T : TRACKING)`** — a typed world wrapper that owns registration,
  mutation delegation, and a per-world component id allocator. Game code and
  backends both use it; they never touch `Eon_ecs.World` directly.
- **`TRACKING`** — a two-method signature (`mark` / `check_and_clear`) that lets
  future backends (query-acceleration caches, debug tooling, reactive UI) hook
  into structural mutations without the world caring what they do.
- **Per-world `Id_counter`** — replaces the previous global `Atomic` counter in
  `Component_descriptor`. Each world allocates dense ids `0, 1, 2, …`
  independently; ids have no meaning across worlds.

The concrete cache (archetype index, bitset signature representation) is removed.
The extension seams above make it possible to add a cache in the future if
benchmarks justify it.

---

## The Functor Philosophy

`eon_ecs` establishes a pattern: almost everything is a functor with a sensible
`Default` instance. Users get a working setup with no configuration; advanced
users compose their own stack from the same primitives. `World.Make` and
`Sparse_set_backend.Make` both follow this pattern — every layer accepts its
dependency as a functor parameter.

This makes the whole engine stack **fully pluggable**: any world (tracking
strategy) can be paired with any backend, and any backend can be paired with any
query builder, without inventing new modules. A user who only wants a custom
`TRACKING` strategy still uses `Sparse_set_backend.Make(World.Make(My_tracking))`
directly — no need to write a custom backend.

Module stack:

```
World.Make(T : TRACKING)
  World.Default  = World.Make(No_tracking)    ← zero overhead, no flag
  World.Tracked  = World.Make(Dirty_flag)     ← dirty notification seam

Sparse_set_backend.Make(W : WORLD.S)
  Sparse_set_backend.Default = Sparse_set_backend.Make(World.Default)

Query.Make(B : Query_backend.S)               ← unchanged from query design doc
  Query.Default = Query.Make(Sparse_set_backend.Default)
```

`Sparse_set_backend.Make` delegates to `Eon_ecs.Query` via `W.to_raw` and never
calls `check_and_clear` — the tracking strategy is invisible to it. Any `WORLD.S`
world works regardless of which `TRACKING` it uses.

---

## 1. `TRACKING` Signature and Implementations

File: `eon_engine/world_tracking.ml`

```ocaml
module type TRACKING = sig
  type t
  val create : unit -> t
  val mark : t -> unit
  val check_and_clear : t -> [ `Clean | `Rebuild ]
end
```

`mark` receives no context — the dirty flag does not care which entity was
mutated or what kind of mutation occurred. Only the fact that a structural
change happened matters.

### `No_tracking` — default, zero overhead

```ocaml
module No_tracking : TRACKING = struct
  type t = unit
  let create () = ()
  let mark _ = ()
  let check_and_clear _ = `Clean
end
```

`mark` is a no-op. The native compiler inlines and dead-code-eliminates it at
every call site.

### `Dirty_flag` — backend extension seam

```ocaml
module Dirty_flag : TRACKING = struct
  type t = bool Atomic.t
  let create () = Atomic.make true
  let mark t = Atomic.set t true
  let check_and_clear t =
    if Atomic.compare_and_set t true false then `Rebuild else `Clean
end
```

`Atomic.bool` provides lock-free dirty flag management. `compare_and_set`
prevents the lost-update race: if a mutation arrives during `check_and_clear`,
the flag stays `true` and the next query triggers a rebuild.

The flag is initialised to `true` so the first `check_and_clear` always returns
`` `Rebuild ``. Any backend that calls it on a freshly created world correctly
sees a dirty state from the start.

---

## 2. `World.Make` Functor

File: `eon_engine/world.ml`

```ocaml
module Make (T : TRACKING) = struct
  type t = {
    raw      : Eon_ecs.World.t;
    tracking : T.t;
    next_id  : int Atomic.t;   (* per-world dense component id allocator *)
  }

  let create () =
    { raw      = Eon_ecs.World.create ();
      tracking = T.create ();
      next_id  = Atomic.make 0 }

  let register world comp =
    let name = Component_descriptor.name comp in
    if Component_descriptor.is_registered world.raw comp then
      Component_descriptor.Already_registered
    else begin
      let id = Atomic.fetch_and_add world.next_id 1 in
      Eon_ecs.World.register_component world.raw ~name ~id;
      Component_descriptor.Registered
    end

  (* Structural mutations — change the entity's component signature *)
  let add_component world entity comp value =
    Eon_ecs.World.add_component world.raw entity
      ~name:(Component_descriptor.name comp) value;
    T.mark world.tracking

  let remove_component world entity comp =
    Eon_ecs.World.remove_component world.raw entity
      ~name:(Component_descriptor.name comp);
    T.mark world.tracking

  let remove_all_components world entity =
    Eon_ecs.World.remove_all_components world.raw entity;
    T.mark world.tracking

  let destroy_entity world entity =
    Eon_ecs.World.destroy_entity world.raw entity;
    T.mark world.tracking

  (* Value mutation — does NOT change component signature, no mark needed *)
  let set_component world entity comp value =
    Eon_ecs.World.set_component world.raw entity
      ~name:(Component_descriptor.name comp) value

  (* Extension API for backends *)
  let to_raw world = world.raw
  let check_and_clear world = T.check_and_clear world.tracking

  (* ... remaining delegations (get_component, create_entity, etc.) ... *)
end

module Default = Make(No_tracking)
module Tracked  = Make(Dirty_flag)
```

`set_component` does **not** mark dirty. It changes a component's value but not
which components the entity owns — the entity's structural signature is unchanged.

`next_id` is an `Atomic.t` (OCaml 5). Registration is initialisation-time only,
never on the hot path, so the atomic fetch-and-add costs nothing in practice.
The Atomic gives safe handling of concurrent world setup at no framework cost.
IDs are dense per world (`0, 1, 2, …`) and have no meaning across worlds.

`Component_descriptor` is a pure name wrapper: `component` (constructor), `name`
(accessor), `is_registered` (checks via `find_component`), and
`registration_result` (`Registered | Already_registered`). It does not generate
ids or hold mutable state — id generation lives entirely in `World.Make.register`.

---

## 3. `WORLD.S` — Uniform World Signature

Both `World.Default` and `World.Tracked` satisfy `WORLD.S`. Backends depend only
on `WORLD.S`; they do not care which tracking strategy is active.

```ocaml
module type S = sig
  type t

  val create               : unit -> t
  val to_raw               : t -> Eon_ecs.World.t  (** extension API *)

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
  val add_data    : t -> [> ] -> 'a -> unit
  val set_data    : t -> [> ] -> 'a -> unit
  val get_data    : t -> [> ] -> 'a option
  val count_data  : t -> int
  val add_service : t -> [> ] -> 'a -> unit
  val get_service : t -> [> ] -> 'a option
  val list_services : t -> int list

  (** Extension API for backends only — not for game code.
      Returns [`Clean] unconditionally for [No_tracking] worlds. *)
  val check_and_clear : t -> [ `Clean | `Rebuild ]
end
```

`check_and_clear` is the bridge between `TRACKING` and a backend. A backend
calls it at the start of each query to decide whether its internal state needs
rebuilding. `No_tracking` worlds always return `` `Clean `` with zero overhead.
Game code never calls this directly.

---

## 4. Mutation Signals *(out of scope)*

Independently of the dirty flag, `eon_engine.World` mutation wrappers will emit
signals on structural changes as a general extensibility hook. This is a separate
concern from the tracking flag and is deferred.

Other interested parties (reactive UI, debug tooling, editor inspectors) can
subscribe to these signals without depending on any particular backend.

---

## 5. User Wiring

### Default — sparse sets, no tracking overhead

```ocaml
module World = Eon_engine.World.Default
module Query = Eon_engine.Query.Default

let world = World.create ()
(* No further setup. *)
```

### Custom tracking strategy, standard backend

A custom `TRACKING` strategy slots into the world functor; the standard
`Sparse_set_backend` plugs in unchanged — no custom backend needed:

```ocaml
module My_tracking : Eon_engine.World.TRACKING = struct
  type t = ...
  let create () = ...
  let mark t = ...
  let check_and_clear t = ...
end

module World   = Eon_engine.World.Make(My_tracking)
module Backend = Eon_engine.Sparse_set_backend.Make(World)
module Query   = Eon_engine.Query.Make(Backend)
```

### Custom backend, custom tracking

Only when the backend itself needs to change do you implement `Query_backend.S`:

```ocaml
module World   = Eon_engine.World.Make(My_tracking)
module Backend = My_backend.Make(World)
module Query   = Eon_engine.Query.Make(Backend)
```

---

## 6. What NOT to Do

- **Do not mark dirty from `set_component`** — value changes leave the component
  signature unchanged; marking would cause spurious rebuilds for any backend that
  hooks into `check_and_clear`.
- **Do not reintroduce a global `Atomic` counter in `Component_descriptor`** —
  per-world dense ids are the design; a global counter creates cross-world id
  collisions and global mutable state.
- **Do not bypass `World.Make.register` by calling
  `Eon_ecs.World.register_component` directly** — the per-world id counter only
  advances inside the `register` wrapper; bypassing it produces duplicate ids.
- **Do not assume component ids are globally unique** — they are dense per world;
  `"Position"` is id `0` in every world that registers it first.
- **Do not add external opam dependencies** unless strictly necessary and not
  achievable with stdlib alone.
