# Data-Plane and Service-Plane Namespacing

## 1. Eon ECS Core: Flat Namespace by Design

`Eon_ecs.World` provides two resource stores: the data-plane and the service-plane. Both are flat — there is no concept of a namespace at the ECS core level, and there never will be. Namespacing is not an ECS problem. The ECS core is responsible for entity lifecycle, component storage, and query iteration. Resource stores are a convenience layer for attaching world-scoped data and services to the simulation. Keeping them flat at the core level preserves simplicity and avoids layering concerns that belong higher up.

## 2. How the Data-Plane and Service-Plane Work in Eon_ecs

Both stores accept any OCaml value as a key via open polymorphic variants. The variant is converted to an `Obj.t` using `Obj.repr`, giving a stable identity-based handle usable in a hash table.

```ocaml
let world = World.create () in

(* Data-plane: per-world simulation parameters *)
World.add_data world `Gravity 9.81;
World.add_data world `Timescale 1.0;
let g = World.get_data world `Gravity in  (* Some 9.81 *)

(* Service-plane: long-lived singletons *)
World.add_service world `Renderer (Renderer.create ());
let r = World.get_service world `Renderer in
```

**Structural difference between the two stores:**

The **service-plane** uses a `Hashtbl` keyed by `Obj.repr key`. Services are registered once at startup and retrieved by point lookup. Typical services are message buses, asset loaders, audio engines, and physics contexts — registered once, referenced many times.

The **data-plane** maps variant keys to integer IDs and stores values in a `Sparse_set`. This gives both O(1) keyed access and O(n) dense iteration over all entries. Data-plane entries represent simulation parameters that systems may iterate — gravity, time scale, environmental constants. The sparse set keeps these densely packed for cache-friendly access.

## 3. The Namespacing Problem

`Eon_ecs.World.create ()` creates a world with its own private resource store. Worlds are already isolated — there is nothing to namespace within a single world. What makes namespacing meaningful is **shared state across worlds**.

A game with multiple worlds — one per level, one for the UI, one for the background scene — needs some data and services to be shared (a renderer, an audio engine, player state) while other data remains strictly private per world (level gravity, local timescale, level-specific services). There is no mechanism in `Eon_ecs` to express this, nor should there be.

The goal at the `eon_engine` layer is:

- Works identically to today if you never use namespacing — fully isolated worlds with zero overhead
- Opt-in: attach named references to other worlds; their stores become reachable via a namespace string at the call site
- No explicit store reference needed at call sites — the namespace string is the indirection

## 4. The Model: Namespacing is World Composition

The key insight is that a shared resource store is just a `World.t` you use only for its data and services. There is no new `Store.t` type needed. A namespace is a named reference to another `World.t`.

`Eon_engine.World.t` holds a **namespace map**: a `(string, World.t) Hashtbl.t`. When a data or service call includes a `~ns` argument, the world looks up that string in its namespace map and routes the call to the target world's resource store. When no `~ns` is given, the call routes to the world's own private store.

```ocaml
type t = {
  raw        : Eon_ecs.World.t;
  namespaces : (string, t) Hashtbl.t;
}
```

Sharing is configured once at construction time. Call sites stay clean — they only know the namespace string, not the target world.

## 5. Opt-In: Isolated Worlds Still Work

A world created with `World.create ()` has an empty namespace map. All data and service calls route to its own private store. This is identical to the current behavior — no overhead, no shared state, no new concepts needed. The namespacing feature is completely transparent to code that does not use it.

```ocaml
(* This always works regardless of namespacing *)
let world = World.create () in
World.add_data world `Gravity 9.81;
World.add_service world `Renderer (Renderer.create ());
```

## 6. API

### 6.1 Namespace management

```ocaml
(* Register a named reference to another world *)
val attach_ns : t -> ns:string -> t -> unit
(* attach_ns world ~ns:"global" global_world *)

(* Convenience: attach the same namespace to many worlds at once *)
val attach_ns_all : ns:string -> t -> t list -> unit
(* attach_ns_all ~ns:"global" global [level_1; level_2; level_3] *)
```

`attach_ns` is the primitive — it mutates `world`'s namespace map; the target world is not modified. `attach_ns_all` is a pure convenience wrapper over `List.iter (fun w -> attach_ns w ~ns target) worlds` and adds no new semantics.

### 6.2 Data-plane

```ocaml
val add_data   : t -> ?ns:string -> [> ] -> 'a -> unit
val set_data   : t -> ?ns:string -> [> ] -> 'a -> unit
val get_data   : t -> ?ns:string -> [> ] -> 'a option
val count_data : t -> ?ns:string -> unit -> int
```

### 6.3 Service-plane

```ocaml
val add_service   : t -> ?ns:string -> [> ] -> 'a -> unit
val get_service   : t -> ?ns:string -> [> ] -> 'a option
val list_services : t -> ?ns:string -> unit -> int list
```

### 6.4 Namespace resolution

```ocaml
let resolve world ns_opt =
  match ns_opt with
  | None    -> world.raw
  | Some ns ->
    match Hashtbl.find_opt world.namespaces ns with
    | Some target -> target.raw
    | None        -> raise (Unknown_namespace ns)
```

All data and service operations call `resolve` first, then delegate to `Eon_ecs.World` on the result. The target world's `Eon_ecs.World.t` is what receives the operation — that world's private entity state is untouched; only its resource store is accessed.

## 7. World Topologies

### 7.1 Fully isolated worlds (default)

No `attach_ns` calls. Each world owns its data and services completely. This is the common case for simple games or tools.

```ocaml
let world_a = World.create () in
let world_b = World.create () in

World.add_data world_a `Gravity 9.81;
World.add_data world_b `Gravity 0.0;
(* No connection. No conflict. *)
```

### 7.2 Shared global services

A single shared world holds cross-cutting services. Each level world attaches it under a common namespace string.

```ocaml
let global = World.create () in
World.add_service global `Renderer (Renderer.create ());
World.add_service global `Audio    (Audio.create ());

let level_1 = World.create () in
let level_2 = World.create () in
World.attach_ns level_1 ~ns:"global" global;
World.attach_ns level_2 ~ns:"global" global;

(* Both levels reach the same renderer *)
let r1 = World.get_service level_1 ~ns:"global" `Renderer in
let r2 = World.get_service level_2 ~ns:"global" `Renderer in
(* r1 and r2 are the same object *)

(* Private data remains isolated *)
World.add_data level_1 `Gravity 9.81;
World.add_data level_2 `Gravity 0.0;
```

### 7.3 Parent–child worlds

A child world is granted read/write access to a parent's data and services by attaching the parent under a namespace. The parent's entity state is not exposed — only its resource stores are reachable.

```ocaml
let parent = World.create () in
World.add_data parent `Config { max_enemies = 10; ... };

let child = World.create () in
World.attach_ns child ~ns:"parent" parent;

let config = World.get_data child ~ns:"parent" `Config in
```

### 7.4 Multiple shared namespaces

A world can attach multiple shared worlds, each under a distinct namespace string. This supports tiered sharing: global cross-cutting services, level-scoped shared state, and private per-world data all coexist.

```ocaml
let global      = World.create () in
let level_scope = World.create () in
let system_a    = World.create () in

World.attach_ns system_a ~ns:"global" global;
World.attach_ns system_a ~ns:"level"  level_scope;

World.add_service system_a ~ns:"global" `Renderer r;  (* → global *)
World.add_data    system_a ~ns:"level"  `Enemy_count 0; (* → level_scope *)
World.add_data    system_a             `Local_timer 0.0; (* → system_a private *)
```

## 8. What Stays in Eon_ecs

Nothing changes in `Eon_ecs`. The core continues to expose a flat key space. The namespace routing is entirely an `Eon_engine.World` concern. `Eon_ecs` users who work without the engine layer retain the current API without any overhead.

## 9. The Global Namespace Convention

The shared global world pattern (section 7.2) requires all participating worlds to agree on a namespace string. Without a shared constant, different parts of a codebase can drift apart — `"global"` in one file, `"globals"` in another, `"shared"` in a third.

`Eon_engine` provides a single string constant to anchor the convention:

```ocaml
(* eon_engine.mli *)
val default_global_ns : string
(* = "global" *)
```

This is nothing more than a string. The engine does not pre-create a global world, does not hold any shared mutable state, and does not force any topology. The developer still creates the global world explicitly — one intentional line — and attaches it using the constant:

```ocaml
let global = World.create () in

let level_1 = World.create () in
World.attach_ns level_1 ~ns:Eon_engine.default_global_ns global;
```

**Why not pre-create the global world in the engine?**

A module-level `let global = World.create ()` in `Eon_engine` would be evaluated once at module load time and shared for the lifetime of the process. This creates two problems:

- **Test isolation**: tests that touch the global world pollute each other. Resetting it requires an explicit teardown call that is easy to forget.
- **Multiple simulations**: a server running independent game instances in the same process would have a single shared global world across all of them — invisible and wrong.

The constant gives consistent naming. The developer retains ownership of the world's lifecycle.

## 10. Future: App.Make and Game Initialization

The existing functor stack in `eon_ecs` already functions as an implicit application constructor:

```ocaml
module Loop = Eon_ecs.Loop.Make(Clock.Mtime)(Progress_adapter)(My_renderer)(Buses)
```

The "app" is the composed set of functors applied at module level. There is no `App.t` because there is no object — the module *is* the application. What Bevy's runtime `App` does by calling `app.add_system(...)` at runtime, OCaml modules express at compile time through functor composition.

An explicit `Engine.Make` functor would provide a **blessed composition** with a clear entry point, consolidating the variation points a developer must supply:

```ocaml
module App = Eon_engine.App.Make(struct
  module Renderer = My_renderer
  module Clock    = Eon_ecs.Clock.Mtime
  let global_ns   = "global"
end)
```

The resulting `App` module would expose `App.world` and `App.global` as module-level values — compile-time artifacts of the functor application, not runtime-constructed objects. The topology (which renderer, which clock, which buses) is fixed at compile time. Systems are still registered at runtime via `Pipeline.Default`, but the structural wiring is not.

This is a meaningful distinction from the Bevy model. In Bevy, the application is a mutable runtime object. In eon, the application is an OCaml module. The `global_ns` field in the `App.Make` struct argument is the natural long-term home for the global namespace convention — replacing the `default_global_ns` constant once this concept exists.

**This is not a near-term task.** `App.Make` makes sense as the last thing composed, once the variation points are known: rendering backends are settled, the World wrapper is stable, and the query builder is in place. Building it now would risk designing it around the wrong seams. The `default_global_ns` constant is the right answer until then.

## 11. Future: Recursive Traversal

In the current design namespace resolution is single-hop — `~ns:"global"` reaches the directly attached world. A natural extension is multi-hop traversal: a namespace string like `"global.meta"` could resolve by first looking up `"global"`, then looking up `"meta"` in the resulting world's namespace map. This is not part of the initial implementation but the data structure supports it without modification — worlds referencing worlds is already a graph, traversal depth is the only variable.
