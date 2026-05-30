# Eon Engine — Archetype Backend Design (v2)

## Context

This document covers the design of `Archetype_backend` (ecs-016) and the `World`
tracking functor pattern that makes it work without boilerplate.

The `Archetype_backend` sections of `eon_engine_query_design.md` are superseded
by this document. The rest of that document (query builder, `Sparse_set_backend`,
`Fallback` functor) remains authoritative.

**v2 changes:** Bitmask signatures (`Int64.t array`), per-world dense bit
position and component ID assignment, `Component_descriptor` simplified to pure
name wrapper, simplified `TRACKING.mark` (unit, no mutation context), optional
`install`, thread safety as documented user responsibility.

---

## What the Archetype Backend Is (and Is Not)

`Archetype_backend` is a **query acceleration cache** layered on top of the
existing sparse set storage. Sparse sets remain the authoritative component
store. The archetype index groups entities by their component signature (a
bitmask of component bit positions), allowing queries with `excludes` and
`having` filters to skip entire groups of non-matching entities rather than
checking every entity individually.

This is **not** a full archetype storage backend. `eon_ecs` is frozen; its
sparse set storage will not change.

---

## The Functor Philosophy

`eon_ecs` establishes a pattern: almost everything is a functor with a sensible
`Default` instance. Users get a working setup with no configuration; advanced
users compose their own stack from the same primitives. The World tracking
mechanism follows this pattern rather than introducing a special case.

Full module stack:

```
World.Make(T : TRACKING)
  World.Default  = World.Make(No_tracking)    ← zero overhead, no flag
  World.Tracked  = World.Make(Dirty_flag)     ← Atomic.bool, archetype users

Sparse_set_backend.Make(W : WORLD.S)
  Sparse_set_backend.Default = Sparse_set_backend.Make(World.Default)

Archetype_backend.Make(W : WORLD.S)
  Archetype_backend.Default  = Archetype_backend.Make(World.Tracked)

Query.Make(B : Query_backend.S)               ← unchanged from query design doc
  Query.Default   = Query.Make(Sparse_set_backend.Default)
  Query.Archetype = Query.Make(Archetype_backend.Default)
```

---

## 1. Bitset — Signature Representation

File: `eon_engine/bitset.ml`

Component signatures are represented as bitmasks using a dynamic `Int64.t array`.
Each component type gets a unique bit position (assigned per-world during
registration). Set operations become bitwise — `includes ⊆ signature` is a
single AND+compare.

```ocaml
type t = Int64.t array

val empty : t
val set : t -> int -> t               (* grow if pos >= length * 64 *)
val test : t -> int -> bool
val subset : of_:t -> t -> bool       (* (of_ & mask) = mask *)
val disjoint : t -> t -> bool         (* (a & b) = 0 *)
val of_list : int list -> t
```

Bit `n` lives in word `n / 64`, bit position `n mod 64`. No hard cap on
component count. `set` is pure — returns a new array, growing if needed.

For worlds with ≤64 components (the common case), this degenerates to a
single-word operation with identical performance to a bare `Int64.t`.

---

## 2. `TRACKING` Signature and Implementations

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

### `Dirty_flag` — archetype users

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

The flag is initialised to `true` so the first query always performs a full
rebuild. This handles the pre-loop setup gap — entities created before the loop
starts emit no signals and would otherwise be invisible to a freshly initialised
empty index.

---

## 3. `World.Make` Functor

File: `eon_engine/world.ml`

```ocaml
module Make (T : TRACKING) = struct
  type t = {
    raw        : Eon_ecs.World.t;
    tracking   : T.t;
    mutable components : (string * int) list;  (* (name, id) — registration order; id = bit position *)
    mutable next_id    : int;                   (* next per-world component ID / bit position *)
  }

  let create () =
    { raw = Eon_ecs.World.create ();
      tracking = T.create ();
      components = [];
      next_id = 0 }

  let register world comp =
    let name = Component_descriptor.name comp in
    if Component_descriptor.is_registered world.raw comp then
      Component_descriptor.Already_registered
    else begin
      let id = world.next_id in
      world.next_id <- id + 1;
      let _ = Eon_ecs.World.register_component world.raw ~name ~id in
      world.components <- (name, id) :: world.components;
      Component_descriptor.Registered
    end

  (* Structural mutations — change the entity's component signature *)
  let add_component world entity comp value =
    let name = Component_descriptor.name comp in
    Eon_ecs.World.add_component world.raw entity ~name value;
    T.mark world.tracking

  let remove_component world entity comp =
    let name = Component_descriptor.name comp in
    Eon_ecs.World.remove_component world.raw entity ~name;
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
  let registered_components world = world.components

  (* ... remaining delegations (get_component, create_entity, etc.) ... *)
end

module Default = Make(No_tracking)
module Tracked  = Make(Dirty_flag)
```

`set_component` does **not** mark dirty. It changes a component's value but not
which components the entity owns — its archetype signature is unchanged.

`register` owns the full component registration lifecycle. The per-world ID
doubles as the bit position — both are the same dense 0, 1, 2, … sequence. The
`Id_counter` module previously lived in `Component_descriptor` as a global
`Atomic` counter; it is now a simple mutable field in the world record. Each
world gets its own dense sequence regardless of how many components exist in
other worlds.

`Component_descriptor` is a pure name wrapper after this change: `component`
(constructor), `name` (accessor), `is_registered` (checks via `find_component`),
and the `registration_result` type (`Registered | Already_registered`, returned
by `register`). It does not generate IDs or hold mutable state.

`registered_components` returns the `(name, id)` pairs in registration order,
where `id` is both the eon_ecs component ID and the archetype bit position.

---

## 4. `WORLD.S` — Uniform World Signature

Both `World.Default` and `World.Tracked` satisfy this signature. Backends
depend only on `WORLD.S`; they do not care which tracking strategy is active.

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

  (** Extension API for backends only — not for game code *)
  val check_and_clear : t -> [ `Clean | `Rebuild ]

  (** Component names and their per-world IDs (which double as bit positions),
      in registration order. Used by [Archetype_index] to build bitsets.
      Each world maintains its own dense 0, 1, 2, … sequence. *)
  val registered_components : t -> (string * int) list
end
```

`check_and_clear` returns `` `Clean `` unconditionally for `No_tracking` worlds.
`Sparse_set_backend` never calls it. `Archetype_backend` calls it on every
`iter*`/`count` invocation.

### Why `WORLD.S` is not split

`WORLD.S` is unified — it includes both core entity/component operations and the
data/service plane from ecs-019. This is intentional: `Archetype_backend` is the
primary consumer of `WORLD.S`, and it explicitly needs `get_service`/`add_service`
to lazily create and retrieve the `Archetypes` index. A split into `WORLD.Core`
and `WORLD.Extended` would require every backend that touches the service plane
(i.e. any non-trivial backend) to depend on the extended signature anyway.

Game code does not use `WORLD.S` directly — it uses the concrete
`World.Default.t` or `World.Tracked.t`. The signature exists for backends.
Backends need the full interface.

---

## 5. Archetype Index

File: `eon_engine/archetype_index.ml`

The index stores an immutable snapshot of entities grouped by their bitmask
signature. The snapshot is held in an `Atomic.t` for safe swap-on-rebuild.

### Data types

```ocaml
type entry = { signature : Bitset.t; entities : Entity_id.t list }
type snapshot = entry list

type t = {
  name_to_pos : (string, int) Hashtbl.t;  (* component name → bit position *)
  index       : snapshot Atomic.t;
}
```

### Component iteration callback

`Archetype_index` does not know how to discover registered components — that is
the world's responsibility. Instead, `rebuild` accepts a callback:

```ocaml
type component_iter =
  (name:string -> pos:int -> entity_ids:((int -> unit) -> unit) -> unit) -> unit
```

The callback is called by `rebuild` with a consumer function. For each
registered component, the caller provides:
- `name` — the component name (used for `name_to_pos` and query mask building).
- `pos` — the dense bit position assigned by the world (0, 1, 2, …).
- `entity_ids` — a function that, given a callback `f`, calls `f` with each
  entity ID that owns this component (typically via `Eon_ecs.Query.iter1`).

### Rebuild

`rebuild t (iter : component_iter)` performs a full scan:

1. Clear `name_to_pos`.
2. Call `iter` with a consumer that, for each component:
   - Stores `name → pos` in `name_to_pos` (the dense ordinal comes from the
     world's `registered_components`).
   - Calls the `entity_ids` function to enumerate entities that own this
     component, accumulating `Bitset.set` per entity.
3. Group entities by signature into `entry list`.
4. `Atomic.set t.index new_snapshot` — atomic swap. Readers see either the old
   or the new snapshot, never a partial state.

### Query

`query t raw_world ~includes ~having ~excludes callback`:

1. Look up bit positions from `name_to_pos`. Build `includes_mask`, `having_mask`,
   `excludes_mask` via `Bitset.of_list`.
2. `Atomic.get t.index` — get current snapshot.
3. For each entry: check
   `Bitset.subset ~of_:entry.signature includes_mask`
   `Bitset.disjoint entry.signature excludes_mask`
   `Bitset.subset ~of_:entry.signature having_mask`
4. For matching entries, iterate `entry.entities`. Read component values via
   `Eon_ecs.World.get_component`. Call `callback` with each entity.

### Stale entries

If the index is slightly behind (an entity moved to a different archetype since
the last rebuild), `get_component` returns `None` and the backend skips that
entity. Correctness is always guaranteed by the component store; the index only
affects performance.

### Rebuild cadence

`ensure_current` is called once per `iter*`/`count` invocation. The rebuild
runs at most once per dirty cycle — the flag is cleared before
`Archetype_index.rebuild` returns, so subsequent queries in the same frame find
it `` `Clean `` and skip the rebuild immediately.

When `install` is used, `ensure_current` runs once in the dedicated phase before
tick begins. All `iter*` calls during tick find the flag `` `Clean `` and return
immediately — the check becomes a single branch with no rebuild work.

---

## 6. `Archetype_backend.Make`

File: `eon_engine/archetype_backend.ml`

```ocaml
module Make (W : World.S) : Query_backend.S with type world = W.t = struct
  type world = W.t

  let get_or_create_arch world =
    match W.get_service world `Archetypes with
    | Some a -> a
    | None   ->
      let a = Archetype_index.create () in
      W.add_service world `Archetypes a;
      a

  let ensure_current world =
    match W.check_and_clear world with
    | `Clean   -> ()
    | `Rebuild ->
      let arch = get_or_create_arch world in
      let raw = W.to_raw world in
      Archetype_index.rebuild arch (fun consumer ->
        List.iter (fun (name, pos) ->
          consumer ~name ~pos ~entity_ids:(fun f ->
            Eon_ecs.Query.iter1 raw name (fun eid _ -> f eid)))
          (W.registered_components world))

  let get_arch world =
    match W.get_service world `Archetypes with
    | Some a -> a
    | None   ->
      (* Index absent after ensure_current returned `Clean — world uses No_tracking.
         Archetype_backend requires World.Tracked or World.Make(Dirty_flag). *)
      invalid_arg
        "Archetype_backend: archetype index was never built. \
         Use World.Tracked (or World.Make(Dirty_flag)) instead of World.Default."

  let iter1 world ~includes ~having ~excludes f =
    ensure_current world;
    let arch = get_arch world in
    Archetype_index.query arch (W.to_raw world) ~includes ~having ~excludes
      (fun eid -> (* read values via get_component, call f *) ...)

  (* iter2, iter3, iter4, count follow the same pattern *)
end

module Default = Make(World.Tracked)
```

### `install` — optional helper for parallel games

```ocaml
(** Register a dedicated [Archetype_rebuild] phase in [pipeline] that runs
    before all other phases. The phase contains one system that calls
    [ensure_current] once per frame, guaranteeing the index is current before
    any parallel tick phase begins.

    Optional — single-threaded games can rely on the lazy rebuild inside
    [iter*] instead. *)
val install : W.t -> Pipeline.t -> unit
```

### Lazy service initialisation

The `Archetypes` service is created on the first `ensure_current` call that
finds it absent — whether that call comes from inside `iter*` (lazy path) or
from the dedicated rebuild phase (via `install`). No explicit registration is
required in either case.

---

## 7. Component Discovery

No changes to `eon_ecs` are needed. Component discovery uses two existing
surfaces:

1. **`WORLD.S.registered_components`** (§4) — returns `(name, id)` pairs in
   registration order, where `id` is both the eon_ecs component ID and the
   archetype bit position. Each `World.Make` instance tracks its own dense
   0, 1, 2, … sequence, assigned in the `register` wrapper (§3).

2. **`Eon_ecs.Query.iter1`** — iterates all entities that own a named component,
   yielding each entity ID and component value to a callback. Used during
   rebuild to enumerate entity IDs per component.

The `component_iter` callback (§5) bridges these two surfaces: the backend
calls `registered_components` to get the name/position pairs, then
`Query.iter1` to enumerate entity IDs, and yields `(name, pos, entity_ids)`
triples to `Archetype_index.rebuild`.

### `Component_descriptor` — pure name wrapper

After the per-world `Id_counter` migration (§3), `Component_descriptor` contains
only:

- `component : string -> 'a t` — constructor (phantom-typed string).
- `name : 'a t -> string` — accessor.
- `is_registered : Eon_ecs.World.t -> 'a t -> bool` — checks via
  `find_component`.
- `type registration_result = Registered | Already_registered` — returned by
  `World.Make.register` (§3).

It does not generate component IDs or hold mutable state. Registration and ID
generation live in `World.Make.register` (§3).

---

## 8. Mutation Signals *(out of scope for ecs-016)*

Independently of the dirty flag, `eon_engine.World` mutation wrappers will
emit signals on structural changes as a general extensibility hook. This is
a separate concern from the archetype backend and is deferred.

Other interested parties (reactive UI, debug tooling, editor inspectors) can
subscribe to these signals without depending on the archetype backend.

---

## 9. User Wiring

### Default — sparse sets, no archetype acceleration

```ocaml
module World = Eon_engine.World.Default
module Query = Eon_engine.Query.Default

let world = World.create ()
(* No further setup. *)
```

### Archetype acceleration — two module swaps

```ocaml
module World = Eon_engine.World.Tracked
module Query = Eon_engine.Query.Archetype

let world = World.create ()
(* No further setup. Archetypes service created lazily on first query. *)
```

### Archetype acceleration with parallel tick — optional install

For games that run systems in parallel within a phase, call `install` once after
creating the world and pipeline. This registers an `Archetype_rebuild` phase
ordered before all other phases:

```ocaml
module World = Eon_engine.World.Tracked
module Query = Eon_engine.Query.Archetype

let world    = World.create ()
let pipeline = Pipeline.Default.create ()

(* Optional — registers a dedicated rebuild phase before all others *)
Eon_engine.Archetype_backend.install world pipeline

(* Systems added to any phase after this point are safe to run in parallel —
   the index is guaranteed current before tick begins each frame. *)
```

Without `install`, the lazy rebuild inside `iter*` is still correct for
single-threaded use.

### Custom tracking strategy

```ocaml
module My_tracking : Eon_engine.World.TRACKING = struct
  type t = ...
  let create () = ...
  let mark t = ...              (* just set dirty *)
  let check_and_clear t = ...   (* return `Clean | `Rebuild *)
end

module World   = Eon_engine.World.Make(My_tracking)
module Backend = Eon_engine.Archetype_backend.Make(World)
module Query   = Eon_engine.Query.Make(Backend)
```

---

## 10. Thread Safety Contract

### Pipeline execution model

`Pipeline.t` runs phases sequentially via topological sort and `List.fold_left`.
Systems within a phase also run sequentially today. This will not change in
`eon_ecs` — the pipeline remains a sequential execution engine.

A future engine-level design will introduce read/write phase markers and
intra-phase parallelism (parallel readers within a phase, never readers and
writers mixed). That design will be documented separately in `docs/design/` and
will reference this document for the archetype index's atomic guarantees.

### Archetype index guarantees

The archetype index is safe for concurrent reads:

- The snapshot is held in an `Atomic.t`. `Atomic.set` and `Atomic.get` ensure
  readers see a consistent snapshot (old or new, never partial).
- `ensure_current` uses `Atomic.compare_and_set` on the dirty flag — at most
  one system triggers a rebuild per dirty cycle.
- During rebuild, the old snapshot remains immutable and readable. The new
  snapshot is published via a single `Atomic.set`.

The first lazy `ensure_current` is a structural writer — it calls
`get_or_create_arch`, which invokes `add_service` on the world to create the
`Archetypes` service. In the no-install parallel path, the loser of the CAS
races against this write. Use `install` for parallel games to front-load this
write into a single-threaded phase.

### `install` is optional

`install` registers a dedicated `Archetype_rebuild` phase before all other
phases. This avoids redundant `check_and_clear` calls when multiple systems
query in the same frame. It is an optimisation, not a correctness requirement.

Without `install`, the lazy rebuild inside `iter*` is correct for sequential
execution and for future parallel readers within a phase.

### User contract

When intra-phase parallelism is added in the future:

- Readers within a phase can run in parallel safely (the index handles this).
- Do not mix readers and writers in the same phase — this is the user's
  responsibility to enforce via phase design.

---

## 11. What NOT to Do

- **Do not mark dirty from `set_component`** — value changes leave the component
  signature unchanged; marking would cause unnecessary rebuilds every frame for
  any world that uses `set_component`.
- **Do not raise when the `Archetypes` service is absent** — it is created
  lazily by the backend. Raising forces boilerplate on the user.
- **Do not rebuild more than once per dirty cycle** — `check_and_clear` atomically
  clears the flag before the rebuild begins; all subsequent queries in the frame
  skip the rebuild.
- **Do not make `World.Default` carry `Dirty_flag`** — sparse set users pay zero
  for a feature they did not opt into.
- **Do not silently return empty results when the index is absent** — if
  `World.Default` (or any `No_tracking` world) is passed to
  `Archetype_backend.Make`, `check_and_clear` always returns `` `Clean ``,
  `ensure_current` never creates the `Archetypes` service, and the index
  stays absent. `get_arch` detects this and raises `Invalid_argument` with
  an actionable message on the first query. Silent empty results are worse than
  a clear error. Do not add fallback logic to mask this misconfiguration.
- **Do not add external opam dependencies** unless strictly necessary and not
  achievable with stdlib alone.
