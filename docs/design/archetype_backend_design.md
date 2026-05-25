# Eon Engine — Archetype Backend Design

## Context

This document covers the design of `Archetype_backend` (ecs-016) and the `World`
tracking functor pattern that makes it work without boilerplate.

The `Archetype_backend` sections of `eon_engine_query_design.md` are superseded
by this document. The rest of that document (query builder, `Sparse_set_backend`,
`Fallback` functor) remains authoritative.

---

## What the Archetype Backend Is (and Is Not)

`Archetype_backend` is a **query acceleration cache** layered on top of the
existing sparse set storage. Sparse sets remain the authoritative component
store. The archetype index groups entities by their component signature (the set
of components they own), allowing queries with `excludes` and `having` filters
to skip entire groups of non-matching entities rather than checking every entity
individually.

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

## 1. `TRACKING` Signature and Implementations

File: `eon_engine/world_tracking.ml`

```ocaml
type mutation_kind =
  | Add     of string  (** component name added to entity *)
  | Remove  of string  (** component name removed from entity *)
  | Destroy            (** entity destroyed — all components implicitly removed *)

module type TRACKING = sig
  type t
  val create : unit -> t

  (** Called on every structural world mutation.
      Receives the entity and full mutation context so that implementations
      can choose between recording a delta or simply setting a dirty flag.
      [No_tracking] and [Dirty_flag] ignore [entity] and [kind]. *)
  val mark : t -> Entity_id.t -> mutation_kind -> unit

  (** Called by the backend before each query.
      [`Clean]   — index is current, no action needed.
      [`Rebuild] — index is stale, perform a full O(E) scan.
      [`Delta]   — index is stale, apply the provided mutation log O(M). *)
  val check_and_clear : t -> [ `Clean | `Rebuild | `Delta of (Entity_id.t * mutation_kind) list ]
end
```

`mark` always receives the full mutation context. Implementations that do not
need it (the common case) simply ignore the extra arguments — the native
compiler eliminates the dead parameter passing entirely.

### `No_tracking` — default, zero overhead

```ocaml
module No_tracking : TRACKING = struct
  type t = unit
  let create () = ()
  let mark _ _ _ = ()
  let check_and_clear _ = `Clean
end
```

`mark` is a no-op. The native compiler inlines and dead-code-eliminates it at
every call site. `t = unit` occupies one word in the record; the cost ends there.

### `Dirty_flag` — archetype users

```ocaml
module Dirty_flag : TRACKING = struct
  type t = bool Atomic.t
  let create () = Atomic.make true
  let mark t _ _ = Atomic.set t true
  let check_and_clear t =
    if Atomic.compare_and_set t true false then `Rebuild else `Clean
end
```

`Atomic.bool` is consistent with the existing `Atomic` usage in `Component_id`.
`compare_and_set` prevents the lost-update race: if a mutation arrives during
`check_and_clear`, the flag stays `true` and the next query triggers a rebuild.

The flag is initialised to `true` so the first query always performs a full
rebuild. This handles the pre-loop setup gap — entities created before the loop
starts emit no signals and would otherwise be invisible to a freshly initialised
empty index.

---

## 2. `World.Make` Functor

File: `eon_engine/world.ml`

```ocaml
module Make (T : TRACKING) = struct
  type t = {
    raw      : Eon_ecs.World.t;
    tracking : T.t;
  }

  let create () =
    { raw = Eon_ecs.World.create (); tracking = T.create () }

  (* Structural mutations — change the entity's component signature *)
  let add_component world entity comp value =
    let name = Component_descriptor.name comp in
    Eon_ecs.World.add_component world.raw entity ~name value;
    T.mark world.tracking entity (Add name)

  let remove_component world entity comp =
    let name = Component_descriptor.name comp in
    Eon_ecs.World.remove_component world.raw entity ~name;
    T.mark world.tracking entity (Remove name)

  let remove_all_components world entity =
    Eon_ecs.World.remove_all_components world.raw entity;
    T.mark world.tracking entity Destroy

  let destroy_entity world entity =
    Eon_ecs.World.destroy_entity world.raw entity;
    T.mark world.tracking entity Destroy

  (* Value mutation — does NOT change component signature, no mark needed *)
  let set_component world entity comp value =
    Eon_ecs.World.set_component world.raw entity
      ~name:(Component_descriptor.name comp) value

  (* Extension API for backends *)
  let check_and_clear world = T.check_and_clear world.tracking

  (* ... remaining delegations (get_component, create_entity, etc.) ... *)
end

module Default = Make(No_tracking)
module Tracked  = Make(Dirty_flag)
```

`set_component` does **not** mark dirty. It changes a component's value but not
which components the entity owns — its archetype signature is unchanged.

---

## 3. `WORLD.S` — Uniform World Signature

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
  val check_and_clear : t -> [ `Clean | `Rebuild | `Delta of (Entity_id.t * mutation_kind) list ]
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

## 4. `Archetype_backend.Make`

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
    | `Clean        -> ()
    | `Rebuild      -> Archetype_index.rebuild      (get_or_create_arch world) world
    | `Delta log    -> Archetype_index.apply_delta  (get_or_create_arch world) log

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
    (* use arch to find candidates, read values from sparse sets *)
    ...

  (* iter2, iter3, iter4, count follow the same pattern *)
end

module Default = Make(World.Tracked)
```

`Archetype_backend` also exposes an `install` function for games that want a
dedicated rebuild phase (see section 7 and section 8):

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

### Rebuild cadence

`ensure_current` is called once per `iter*`/`count` invocation. The rebuild
runs at most once per dirty cycle — the flag is cleared before
`Archetype_index.rebuild` returns, so subsequent queries in the same frame find
it `` `Clean `` and skip the rebuild immediately.

When `install` is used, `ensure_current` runs once in the dedicated phase before
tick begins. All `iter*` calls during tick find the flag `` `Clean `` and return
immediately — the check becomes a single branch with no rebuild work.

---

## 5. Archetype Index

The index is an internal concern of `Archetype_index`. It maintains:

- A forward map: component signature (sorted `string list`) → entity list
- An inverted map: component name → set of signatures containing it

For a query `includes=["Position","Velocity"] excludes=["Frozen"]`:

1. Use the inverted map to find signatures containing both `Position` and `Velocity`
2. Discard signatures that also contain `Frozen`
3. Iterate the entity lists of surviving signatures
4. Read component values from sparse sets (authoritative)

### Signature representation and sorting overhead

Component signatures are sorted `string list` values — sorted so that
`["Position"; "Velocity"]` and `["Velocity"; "Position"]` hash to the same key.
Sorting is O(K log K) per entity where K is the number of components that entity
owns. This cost is paid during `rebuild` and `apply_delta`, not during queries.

For typical entities with 5–20 components this is negligible. If profiling shows
signature computation is a bottleneck (large worlds with many components per
entity), the natural upgrade is a **bitmask representation**: assign each
registered component a stable bit position (already available via the engine's
`Component_id` counter); an entity's signature is an integer bitmask, union is
bitwise OR, intersection is AND, comparison is integer equality — no sorting,
O(1) operations. This is a localised change to `Archetype_index` internals and does
not affect the `TRACKING` signature or `World.Make`.

**Stale entries are handled gracefully.** If the index is slightly behind (an
entity moved to a different archetype since the last rebuild), the sparse set
read returns `None` and the backend skips that entity. Correctness is always
guaranteed by the sparse sets; the index only affects performance.

**Expected staleness window:** `check_and_clear` is called on every `iter*`/`count`
invocation. In a normal game loop with at least one query per frame, the index
is rebuilt at the start of that frame and is at most one frame stale. "Severely
out of sync" only occurs if no queries run for many frames — in which case the
archetype backend provides no benefit anyway, and the staleness is irrelevant.
If a system runs queries only occasionally (e.g. every N frames), the index may
be up to N frames stale between those queries; stale entries are still handled
correctly via sparse set fallback, just with reduced acceleration until the next
rebuild.

### Rebuild cost and upgrade path

`Archetype_index.rebuild` is a full scan of all entities. It is O(E) where E is the
number of entities, and runs at most once per dirty cycle — amortised across all
queries in that frame.

**This is acceptable when** structural mutations are infrequent or the world is
small-to-medium (up to ~50K entities). **It becomes a bottleneck when** entities
gain or lose components every frame at high volume (e.g. status effects, AI state
transitions in a large world with 100K+ entities).

**When not to worry:** `set_component` never marks dirty. Worlds that mutate
component *values* but rarely change component *signatures* pay zero rebuild cost
regardless of entity count.

**The upgrade path is `Incremental_tracking`.** The `TRACKING` functor is the
exact extension point. Because `mark` already receives the full mutation context
(entity id and `mutation_kind`), an incremental implementation requires no
changes to `World.Make`, backends, query layer, or game code:

```ocaml
(* When the log exceeds this threshold, fall back to a full rebuild rather than
   applying a large delta — avoids unbounded memory growth and keeps apply_delta
   fast. Tune based on profiling. *)
let max_delta_size = 1024

module Incremental_tracking : TRACKING = struct
  type t = {
    mutable dirty : bool;
    mutable log   : (Entity_id.t * mutation_kind) list;
    mutable size  : int;
  }
  let create () = { dirty = true; log = []; size = 0 }
  let mark t entity kind =
    t.dirty <- true;
    t.log  <- (entity, kind) :: t.log;
    t.size <- t.size + 1
  let check_and_clear t =
    if not t.dirty then `Clean
    else begin
      let log = t.log and size = t.size in
      t.dirty <- false; t.log <- []; t.size <- 0;
      if size > max_delta_size
      then `Rebuild        (* delta too large — full rebuild is cheaper *)
      else `Delta log
    end
end

(* One module swap — everything else unchanged *)
module World   = Eon_engine.World.Make(Incremental_tracking)
module Query   = Eon_engine.Query.Make(Eon_engine.Archetype_backend.Make(World))
```

**Memory bound:** the log is capped at `max_delta_size` entries. Once exceeded,
`check_and_clear` discards the log and returns `` `Rebuild ``, degrading gracefully
to full-rebuild semantics. This bounds memory use to O(max_delta_size) regardless
of how many frames pass without a query.

`Archetype_index.apply_delta` (the O(M) counterpart to `Archetype_index.rebuild`) is **not
implemented yet**. Do not implement it prematurely — profile first. The signature
enrichment already in place means the implementation can be added without touching
any other module when the time comes.

---

## 6. Mutation Signals *(out of scope for ecs-016)*

Independently of the dirty flag, `eon_engine.World` mutation wrappers emit
signals on structural changes as a general extensibility hook:

```ocaml
type mutation_event =
  | Component_added    of Entity_id.t * string
  | Component_removed  of Entity_id.t * string
  | Entity_destroyed   of Entity_id.t
```

Emission is best-effort: skipped if the Signals bus is not registered in the
service plane. All world variants (`Default`, `Tracked`, custom) emit the same
signals — this is independent of tracking strategy.

Other interested parties (reactive UI, debug tooling, editor inspectors) can
subscribe to these signals without depending on the archetype backend. The dirty
flag and mutation signals are separate concerns that happen to be set at the
same call sites.

---

## 7. User Wiring

### Default — sparse sets, no archetype acceleration

```ocaml
module World = Eon_engine.World.Default
module Query = Eon_engine.Query.Default

let world = World.create ()
(* No further setup. *)
```

### Archetype acceleration — one module swap

```ocaml
module World = Eon_engine.World.Tracked
module Query = Eon_engine.Query.Archetype

let world = World.create ()
(* No further setup. Archetypes service created lazily on first query. *)
```

### Archetype acceleration with parallel tick — dedicated rebuild phase

For games that run systems in parallel within a phase, call `install` once after
creating the world and pipeline. This registers an `Archetype_rebuild` phase
ordered before all other phases, eliminating Race 2 (see section 8):

```ocaml
module World = Eon_engine.World.Tracked
module Query = Eon_engine.Query.Archetype

let world    = World.create ()
let pipeline = Pipeline.Default.create ()

(* Register the rebuild phase — must be called before the loop starts *)
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
  let mark t entity kind = ...   (* entity and kind available for incremental use *)
  let check_and_clear t = ...    (* return `Clean | `Rebuild | `Delta log *)
end

module World   = Eon_engine.World.Make(My_tracking)
module Backend = Eon_engine.Archetype_backend.Make(World)
module Query   = Eon_engine.Query.Make(Backend)
```

---

## 8. Parallelism Contract

The engine does not enforce isolation between parallel pipeline phases. This
applies to all shared world state — components, resources, services, the
archetype index — not just the dirty flag.

**The contract:** phases that execute concurrently must not share mutable state.
A phase that reads components and a phase that writes the same components must
not run in parallel. Violation is undefined behaviour; the engine provides no
detection or recovery.

`Dirty_flag` uses `Atomic.bool` because it is engine infrastructure that is
shared by construction. Game-level shared state is the user's responsibility.
This boundary — engine infrastructure is safe, game state is your problem —
should be documented clearly wherever parallelism is mentioned.

### The archetype index is not thread-safe

The `Atomic.bool` in `Dirty_flag` protects only the flag itself.
The `Archetype_index` (stored in the service plane under `` `Archetypes ``) is a
mutable structure with no internal synchronisation. `compare_and_set` ensures
that at most one thread wins the rebuild race, but the winning thread mutates
the index while other threads may be reading it — a data race.

**Two phases that both use `Archetype_backend` are sharing the archetype index
via the service plane.** They are therefore NOT independent and must not execute
concurrently. This is a specific application of the general independence contract,
not an additional constraint.

### Two distinct races

It is worth distinguishing the two parallel hazards, as they have different
remedies:

**Race 1 — concurrent mutation and query.** One thread writes component data
while another reads it. This occurs in a non-reactive game where mutations and
queries both happen during tick. Phase separation (reactive style: mutations in
drain, queries in tick) eliminates this race entirely — the two phases are
sequential.

**Race 2 — rebuild during parallel tick.** The rebuild is triggered lazily
inside each `iter*` call via `ensure_current`. If two systems in the same tick
phase run in parallel, both call `ensure_current`: one wins the `compare_and_set`
and starts rebuilding (writing the index) while the other already received
`` `Clean `` and starts reading it. This race exists even in the reactive style,
because phase separation only isolates mutations from queries — it does not
prevent two query-only systems from racing on the rebuild.

**Resolving Race 2** is straightforward: call `Archetype_backend.install world
pipeline` once before the loop starts. This registers a dedicated
`Archetype_rebuild` phase ordered before all other phases. The rebuild runs
single-threaded in that phase; all subsequent parallel phases find the flag
`` `Clean `` and only read the index — no race:

```
collect → Archetype_rebuild phase (single-threaded) → parallel tick (read-only) → drain → render
```

`install` is optional. Single-threaded games can rely on the lazy rebuild inside
`iter*` and never call it. Parallel games call it once at startup; the overhead
is zero for frames where nothing is dirty.

If parallel query execution without a dedicated rebuild phase is needed in the
future (e.g. mid-frame dynamic world creation), the index would require a
reader-writer lock or an immutable/copy-on-write representation. Neither is
implemented. Profile before designing a solution.

---

## 9. What NOT to Do

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
