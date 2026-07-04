# Data-Plane and Service-Plane Namespacing

## 1. Eon ECS Core: Flat Namespace by Design

`Eon_ecs.World` provides two resource stores: the data-plane and the service-plane. Both are flat — there is no concept of a namespace at the ECS core level, and there never will be. Namespacing is not an ECS problem. The ECS core is responsible for entity lifecycle, component storage, and query iteration. Resource stores are a convenience layer for attaching world-scoped data and services to the simulation. Keeping them flat at the core level preserves simplicity and avoids layering concerns that belong higher up.

## 2. How the Data-Plane and Service-Plane Work in Eon_engine

`Eon_engine.World` wraps `Eon_ecs.World` and carries a phantom permission type — the same `ro`/`rw` distinction used by the parallel pipeline:

```ocaml
type 'perm t  (* wraps Eon_ecs.World.t, no namespace state *)

type ro = [ `R ]
type rw = [ `R | `W ]
```

The data and service APIs mirror `Eon_ecs.World` but add phantom constraints. Writes require `rw`; reads accept any permission:

```ocaml
(* Data-plane *)
val create     : unit -> rw t
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

The **data-plane** maps variant keys to integer IDs and stores values in a `Sparse_set`. This gives O(1) keyed access and O(n) dense iteration. Data-plane entries represent per-frame or simulation-scoped data — input frames, command buffers, environmental constants.

`World` has no namespace state, no `attach_ns`, no `get_ns`. It is a local store. Cross-world concerns live in `Namespace`.

## 3. The Namespacing Problem

`World.create ()` produces a world with its own private resource store. Worlds are isolated by default — nothing to namespace within a single world. What makes namespacing meaningful is access across worlds.

A game with multiple worlds — one per level, one for UI, one for background simulation — needs some resources and services to be shared (an audio backend, a physics engine, player state) while other data remains private per world (level gravity, local timescale). `Eon_ecs` has no mechanism for this, nor should it.

The goal at the `eon_engine` layer: provide a simple directory that maps names to worlds, and helpers that compose with `Resource.S` and `Service.S` for typed cross-world access. The engine provides the wiring; how game developers use it is their business.

## 4. Namespace.t — A Flat World Directory

`Namespace.t` is a flat map from namespace strings to worlds. It lives outside `World.t` — a plain value the developer creates, populates, and keeps wherever makes sense for their game:

```ocaml
module type Namespace.S = sig
  type t

  val create : unit -> t
  (** Empty directory. *)

  val attach : t -> string -> rw World.t -> unit
  (** Register a world under a name. Called at startup. *)

  val named  : string -> t -> rw World.t
  (** Look up a world by name. Raises [Unknown_namespace] if not found. *)
end
```

`named` returns `rw World.t` — worlds are attached at startup with full access. `Resource.fetch` and `Service.fetch` accept `[> ro] World.t`, so the result composes correctly in both parallel (read-only) and exclusive (read-write) system contexts.

Typical startup:

```ocaml
let global = World.create () in
let game   = World.create () in
let ui     = World.create () in

let ns = Namespace.create () in
Namespace.attach ns "global" global;
Namespace.attach ns "game"   game;
Namespace.attach ns "ui"     ui;
```

One `Namespace.t` instance. All worlds in one place. No per-world maps, no graph traversal, no routing handles.

## 5. Cross-World Access

`Resource.fetch` and `Service.fetch` (defined in `resource_service_design.md`) take any `World.t`. `Namespace.named` returns a `World.t`. The composition is the cross-world API:

```ocaml
(* local access *)
Resource.fetch world              (module Raw_input_frame)
Service.fetch  world              (module Steam_api)

(* cross-world access *)
Resource.fetch (Namespace.named "global" ns) (module Raw_input_frame)
Service.fetch  (Namespace.named "global" ns) (module Steam_api)
```

No special cross-world API is needed. `Namespace.named` is a world lookup; `Resource.fetch` / `Service.fetch` are typed accessors. Neither needs to know about the other.

For modules with richer APIs than `fetch`/`store` — like `Audio_command_buffer` — resolve the world first:

```ocaml
let global_world = Namespace.named "global" ns in
Audio_command_buffer.add (Audio_command_buffer.fetch global_world) cmd
```

## 6. The Engine's Contract

The engine's contract ends when the correct `World.t` arrives at the system boundary. What happens inside a system is game logic.

Systems that need cross-world access know they need it — that is the game developer's responsibility, not the engine's. How they make `Namespace.t` accessible (stored as a service in any world, a module-level value, a closure captured at pipeline construction, a function argument) is entirely their choice. The engine provides a coherent structure; it does not prescribe usage patterns beyond that.

```ocaml
(* all of these are valid ways to make ns accessible — game dev's call *)

(* option a: stored as a service *)
World.add_service game `Namespace ns;
let ns = World.get_service world `Namespace |> Option.get in

(* option b: module-level value in the game's init module *)
let ns = Game_init.namespace

(* option c: captured at pipeline construction *)
let make_system ns =
  System.make (fun world _dt ->
    Resource.fetch (Namespace.named "global" ns) (module Physics_state))
```

## 7. The Aggregator Pattern

For games that want named shorthand accessors — no first-class modules at call sites — the game developer can build their own aggregator module on top of `Namespace`, `Resource`, and `Service`:

```ocaml
(* game/world_ns.ml — optional, written by the game developer *)
module World_ns = struct
  let ns = Namespace.create ()

  let init steam_instance =
    Namespace.attach ns "global" (World.create ());
    Service.register  (Namespace.named "global" ns) (module Steam_api)   steam_instance;
    Resource.set      (Namespace.named "global" ns) (module Physics_state) (Physics_state.create ())

  (* named shorthand accessors *)
  let input   world = Resource.fetch world              (module Raw_input_frame)
  let audio   world = Resource.fetch world              (module Audio_command_buffer)
  let steam   ()    = Service.fetch  (Namespace.named "global" ns) (module Steam_api)
  let physics ()    = Resource.fetch (Namespace.named "global" ns) (module Physics_state)
end

(* in a system — module path access, no first-class modules *)
let update world _dt =
  let input = World_ns.input world in
  let steam = World_ns.steam () in
  ...
```

This is one pattern among many. The engine does not mandate it.

## 8. World Topologies

### 8.1 Fully isolated worlds (default)

No `Namespace.t` needed. Each world owns its data and services completely.

```ocaml
let world_a = World.create () in
let world_b = World.create () in

World.add_data world_a `Gravity 9.81;
World.add_data world_b `Gravity 0.0;
```

### 8.2 Shared global services

One `Namespace.t` holds all worlds. Systems access whichever world they need:

```ocaml
(* startup *)
let ns = Namespace.create () in
Namespace.attach ns "global" (World.create ());
Namespace.attach ns "level1" (World.create ());
Namespace.attach ns "level2" (World.create ());

Service.register (Namespace.named "global" ns) (module Steam_api) (Steam.connect ());

(* in a system running on level1's world *)
let update world _dt =
  let input = Resource.fetch world (module Raw_input_frame) in   (* level1 local *)
  let steam = Service.fetch  (Namespace.named "global" ns) (module Steam_api) in
  ...
```

### 8.3 Multiple namespaces

The flat map supports any topology — each name is an independent entry:

```ocaml
Namespace.attach ns "global" global;
Namespace.attach ns "ui"     ui_world;
Namespace.attach ns "game"   game_world;

let ui_state  = Resource.fetch (Namespace.named "ui"     ns) (module Ui_state) in
let game_data = Resource.fetch (Namespace.named "game"   ns) (module Game_data) in
let steam     = Service.fetch  (Namespace.named "global" ns) (module Steam_api) in
```

## 9. Everything Is Optional

The `eon_engine` layers are independently opt-in:

| Layer | What it adds | Skip when |
|---|---|---|
| `Eon_engine.World` | `'perm` phantom types on the ECS world | `Eon_ecs.World` is sufficient |
| `Resource.S` / `Service.S` | Typed, phantom-constrained local access | Raw `World.get_data` / `get_service` is acceptable |
| `Resource.fetch` / `Service.fetch` | First-class module convenience helpers | Direct `R.fetch world` is preferred |
| `Namespace.t` | Named cross-world directory | Single world, no cross-world access needed |

A card game developer uses one world and raw `World.get_data` / `get_service`. They ignore all of this. An action RPG with a shared global world and per-level simulation worlds uses all of it. Neither is wrong.

## 10. The Global Namespace Convention

When multiple parts of a codebase attach the same world to their `Namespace.t`, they must agree on the string. Without a shared constant, drift happens.

`Eon_engine` provides one:

```ocaml
val default_global_ns : string
(* = "global" *)
```

Nothing more than a string. The engine creates no global world, holds no shared state, forces no topology:

```ocaml
let ns = Namespace.create () in
Namespace.attach ns Eon_engine.default_global_ns global_world;
```

**Why not pre-create the global world?** A module-level `let global = World.create ()` evaluated at load time is shared across the process lifetime — test pollution and multi-simulation incoherence are the consequences. The constant anchors naming. The developer owns the world.

## 11. Future: App.Make and Game Initialization

An explicit `Engine.Make` functor would consolidate the variation points a developer supplies:

```ocaml
module App = Eon_engine.App.Make(struct
  module Renderer = My_renderer
  module Clock    = Eon_ecs.Clock.Mtime
  let global_ns   = Eon_engine.default_global_ns
end)
```

`global_ns` is the natural long-term home for the namespace convention. Not a near-term task — `App.Make` belongs after the rendering backend, World wrapper, and query layer are settled.
