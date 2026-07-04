# Data-Plane and Service-Plane Namespacing

## 1. Eon ECS Core: Flat Namespace by Design

`Eon_ecs.World` provides two resource stores: the data-plane and the service-plane. Both are flat — there is no concept of a namespace at the ECS core level, and there never will be. Namespacing is not an ECS problem. The ECS core is responsible for entity lifecycle, component storage, and query iteration. Resource stores are a convenience layer for attaching world-scoped data and services to the simulation. Keeping them flat at the core level preserves simplicity and avoids layering concerns that belong higher up.

## 2. How the Data-Plane and Service-Plane Work in Eon_engine

`Eon_engine.World` wraps `Eon_ecs.World` and carries a phantom permission type — the same `ro`/`rw` distinction used by the parallel pipeline:

```ocaml
type 'perm t = {
  raw        : 'perm Eon_ecs.World.t;
  namespaces : (string, 'perm t) Hashtbl.t;
}

type ro = [ `R ]
type rw = [ `R | `W ]
```

The data and service APIs mirror `Eon_ecs.World` but add phantom constraints. Writes require `rw`; reads accept any permission:

```ocaml
(* Data-plane *)
val add_data   : rw t -> [> ] -> 'a -> unit
val set_data   : rw t -> [> ] -> 'a -> unit
val get_data   : [> ro] t -> [> ] -> 'a option
val count_data : [> ro] t -> unit -> int

(* Service-plane *)
val add_service : rw t -> [> ] -> 'a -> unit
val get_service : [> ro] t -> [> ] -> 'a option
```

Both stores accept open polymorphic variants as keys. The variant is converted to an `Obj.t` via `Obj.repr`, giving a stable identity-based handle usable in a hash table.

**Structural difference between the two stores:**

The **service-plane** uses a `Hashtbl` keyed by `Obj.repr key`. Services are registered once at startup and retrieved by point lookup. Typical services are audio engines, physics contexts, and network sessions — registered once, referenced many times.

The **data-plane** maps variant keys to integer IDs and stores values in a `Sparse_set`. This gives O(1) keyed access and O(n) dense iteration. Data-plane entries represent per-frame or simulation-scoped data — input frames, command buffers, environmental constants. The sparse set keeps these densely packed for cache-friendly access.

There is no `?ns` parameter on any data or service operation. Namespace routing is handled entirely by `Namespace.S` — the World API stays clean.

## 3. The Namespacing Problem

`World.create ()` creates a world with its own private resource store. Worlds are isolated — there is nothing to namespace within a single world. What makes namespacing meaningful is typed, ergonomic access across worlds.

A game with multiple worlds — one per level, one for UI, one for background simulation — needs some resources and services to be shared (an audio backend, player state, a physics engine) while other data remains private per world (level gravity, local timescale, level-specific services). There is no mechanism in `Eon_ecs` for this, nor should there be.

The goal at the `eon_engine` layer:

- Zero overhead if namespacing is never used — one world, no topology, no new concepts
- Opt-in: attach named references to other worlds; `Namespace.S` routes typed access to the target world's local store
- No call-site boilerplate — the aggregator pattern (§7) gives named module-path access with no first-class modules at call sites

## 4. The Model: World Graph + Namespace.S

Two orthogonal concerns, each with a clear owner:

**`Eon_engine.World` manages the graph.** Each world holds a namespace map — a `(string, 'perm t) Hashtbl.t` of named references to other worlds. `attach_ns` wires the graph at startup. This is structural configuration, not data access. The World API exposes no namespace-routing parameters.

**`Namespace.S` does typed routing.** A `Namespace.t` is an abstract handle — a world reference plus optional routing. `Namespace.get_resource` resolves the target world and delegates to `Resource.S.fetch` on it. The resource module never knows it was routed; it sees a plain local world access.

The graph is **flat by design**. Every world is at most one hop away — `Namespace.named "global" world` resolves directly to the attached world. Nested traversal is unnecessary because `Namespace.S` gives direct typed access to any world in the graph: each world only knows about the worlds it explicitly attached, and systems reach them by name through `Namespace.S`.

## 5. World Structural API

Graph management operations — separate from data access:

```ocaml
val create : unit -> rw t

(* Attach a named reference to another world *)
val attach_ns     : 'perm t -> string -> 'perm t -> unit

(* Convenience: attach the same namespace to many worlds at once *)
val attach_ns_all : string -> 'perm t -> 'perm t list -> unit

(* Look up an attached world by name *)
val get_ns     : 'perm t -> string -> 'perm t       (* raises Unknown_namespace *)
val get_ns_opt : 'perm t -> string -> 'perm t option
```

`attach_ns` mutates the source world's namespace map; the target world is not modified. `get_ns` / `get_ns_opt` return the attached world with the same permission as the caller — a `ro` handle gives a `ro` view of the attached world. Permission does not escalate through lookup.

## 6. Namespace.S

`Namespace.S` is a module signature for typed, permission-aware routing to a world's local store via `Resource.S` and `Service.S`:

```ocaml
module type S = sig
  type 'perm t

  val local : 'perm World.t -> 'perm t
  (** Routes to the world's own local store — no namespace lookup. *)

  val named : string -> 'perm World.t -> 'perm t
  (** Routes to the world attached under the given namespace string. *)

  val resolve : 'perm t -> 'perm World.t
  (** Returns the resolved target world for direct access. *)

  val get_resource : (module Resource.S with type t = 'a) -> [> World.ro] t -> 'a
  val set_resource : (module Resource.S with type t = 'a) -> World.rw t -> 'a -> unit

  val get_service  : (module Service.S  with type t = 'a) -> [> World.ro] t -> 'a
  val reg_service  : (module Service.S  with type t = 'a) -> World.rw t -> 'a -> unit
end
```

The concrete `Namespace` module satisfies `Namespace.S`. `get_resource` is a one-liner:

```ocaml
let get_resource (module R : Resource.S) ns_t = R.fetch (resolve ns_t)
```

`resolve ns_t` returns the target `World.t` — either the world itself (`local`) or the attached world (`named`). `R.fetch` then accesses that world's local store. The resource module has no knowledge of routing; it sees a plain local access.

`resolve` is public so callers can reach any function on a resource module through a namespace handle — useful for modules with richer APIs than `fetch`/`store`:

```ocaml
let world = Namespace.resolve global_ns in
Audio_command_buffer.add (Audio_command_buffer.fetch world) cmd
```

**Phantom type propagation:** `get_resource` constrains its handle to `[> World.ro] t`, matching `Resource.S.fetch`. `set_resource` requires `World.rw t`, matching `Resource.S.store`. A `ro` namespace handle cannot call `set_resource` — the compiler rejects it at the call site, no runtime check needed.

## 7. The Aggregator Pattern

`Namespace.S` is most useful as a foundation for a concrete game-specific module that centralises all resource and service definitions for a world. This module has two roles: a single registration point at startup, and named shorthand accessors throughout the codebase. Call sites use module paths — no first-class modules, no string keys:

```ocaml
(* game/world_ns.ml *)
module World_ns = struct
  include Namespace.Local   (* or Namespace.Make(struct let ns = "global" end) *)

  (* Named accessors — call sites use World_ns.input, World_ns.audio, etc. *)
  let physics world = get_resource (module Physics_state)        world
  let input   world = get_resource (module Raw_input_frame)      world
  let audio   world = get_resource (module Audio_command_buffer) world
  let steam   world = get_service  (module Steam_api)            world

  (* All registration in one place — called once before the loop starts *)
  let init world steam_instance =
    reg_service  (module Steam_api)            world steam_instance;
    set_resource (module Audio_command_buffer) world (Audio_command_buffer.create ());
    set_resource (module Physics_state)        world (Physics_state.create ())
end

(* In a system *)
let update world _dt =
  let ns    = World_ns.local world in
  let input = World_ns.input ns in
  let audio = World_ns.audio ns in
  Audio_command_buffer.add audio (Play_sound { id = "hit"; volume = 1.0; ... })
```

`eon_engine` provides the machinery — `Namespace.S`, `Resource.S`, `Service.S`. The aggregator module is written by the game developer and names their specific resources and services. A game using multiple worlds defines one aggregator per logical namespace:

```ocaml
(* accessing resources from two worlds in the same system *)
let global_ns = World_ns.named "global" world in
let local_ns  = World_ns.local world in

let steam = World_ns.steam  global_ns in   (* → global world *)
let input = World_ns.input  local_ns  in   (* → this world's local store *)
```

## 8. World Topologies

### 8.1 Fully isolated worlds (default)

No `attach_ns` calls. Each world owns its data and services completely. No `Namespace.S` needed.

```ocaml
let world_a = World.create () in
let world_b = World.create () in

World.add_data world_a `Gravity 9.81;
World.add_data world_b `Gravity 0.0;
(* No connection. No conflict. *)
```

### 8.2 Shared global services

A shared world holds cross-cutting services. Level worlds attach it at startup and access it through a `Namespace.t` handle:

```ocaml
(* startup *)
let global  = World.create () in
let level_1 = World.create () in
let level_2 = World.create () in

Global_ns.init global (Steam.connect ());
World.attach_ns_all "global" global [level_1; level_2];

(* in a system running on level_1's world *)
let update world _dt =
  let gns = World_ns.named "global" world in
  let lns = World_ns.local world in
  let steam = World_ns.steam gns in   (* → global world *)
  let input = World_ns.input lns in   (* → level_1 local *)
  ...
```

### 8.3 Multiple attached worlds

A world attaches multiple others under distinct names. The graph is flat — each attachment is a direct named reference, one hop:

```ocaml
World.attach_ns game_world "global" global;
World.attach_ns game_world "ui"     ui_world;

let global_ns = World_ns.named "global" game_world in
let ui_ns     = Ui_ns.named   "ui"     game_world in

let steam    = World_ns.steam  global_ns in
let ui_state = Ui_ns.state     ui_ns     in
```

## 9. Everything Is Optional

The three `eon_engine` layers are independently opt-in:

| Layer | What it adds | Skip when |
|---|---|---|
| `Eon_engine.World` | `'perm` phantom types, `attach_ns` graph | Single world, `Eon_ecs.World` is enough |
| `Resource.S` / `Service.S` | Typed, phantom-constrained local access | Raw `World.get_data` / `get_service` is acceptable |
| `Namespace.S` + aggregator | Typed cross-world routing, named call-site ergonomics | Single world, no cross-world access needed |

A card game developer uses one world, stores data under polymorphic variant keys, and ignores all three layers. A multiplayer action game with a shared global world and per-player simulation worlds adopts all three. Each layer adds value only at the scale that needs it.

## 10. The Global Namespace Convention

When multiple worlds share a common world (§8.2), every `attach_ns` call must agree on the namespace string. Without a shared constant, drift happens — `"global"` in one file, `"globals"` in another.

`Eon_engine` provides a single string constant:

```ocaml
(* eon_engine.mli *)
val default_global_ns : string
(* = "global" *)
```

This is nothing more than a string. The engine does not pre-create a global world, holds no shared mutable state, and forces no topology. The developer creates the global world and attaches it explicitly:

```ocaml
let global = World.create () in
World.attach_ns level_1 Eon_engine.default_global_ns global;
```

**Why not pre-create the global world in the engine?** A module-level `let global = World.create ()` in `Eon_engine` is evaluated once at module load time and shared for the process lifetime:

- **Test isolation**: tests that touch the global world pollute each other — teardown is easy to forget.
- **Multiple simulations**: a server running independent game instances in the same process shares one global world across all of them — invisible and wrong.

The constant gives consistent naming. The developer retains lifecycle ownership.

## 11. Future: App.Make and Game Initialization

An explicit `Engine.Make` functor would provide a blessed composition with a clear entry point, consolidating the variation points a developer must supply:

```ocaml
module App = Eon_engine.App.Make(struct
  module Renderer = My_renderer
  module Clock    = Eon_ecs.Clock.Mtime
  let global_ns   = Eon_engine.default_global_ns
end)
```

The resulting `App` module would expose `App.world` and `App.global` as module-level values — compile-time artifacts of functor application. The `global_ns` field is the natural long-term home for the namespace convention, replacing `default_global_ns` once `App.Make` exists.

**This is not a near-term task.** `App.Make` makes sense once the variation points are settled: rendering backends, the World wrapper, and the query layer. Building it now risks designing it around the wrong seams. `default_global_ns` is the right answer until then.
