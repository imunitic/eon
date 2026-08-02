(* Companion example for docs/eon_engine chapter: Queries and systems. *)

open Eon_engine

let make_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

(* Query builder: Query.Default is the pre-instantiated instance backed by
   World.t. having/having_all/not_having take component *names* (string),
   not descriptors — Query.count/iter narrow to the intersection. *)
let query_example () =
  let world = make_world () in
  let mover = World.create_entity world in
  World.add_component world mover Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world mover Components.Velocity.component
    ({ dx = 1.0; dy = 0.0 } : Components.Velocity.t);

  let stationary = World.create_entity world in
  World.add_component world stationary Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);

  let moving_count =
    Query.Default.from world
    |> Query.Default.having Components.Local_transform.name
    |> Query.Default.having Components.Velocity.name
    |> Query.Default.count
  in
  assert (moving_count = 1);

  Query.Default.from world
  |> Query.Default.having Components.Local_transform.name
  |> Query.Default.having Components.Velocity.name
  |> Query.Default.iter (fun view ->
       let e = View.entity view in
       assert (e = mover));

  let without_velocity_count =
    Query.Default.from world
    |> Query.Default.having Components.Local_transform.name
    |> Query.Default.not_having Components.Velocity.name
    |> Query.Default.count
  in
  assert (without_velocity_count = 1)

(* Cached queries: Cached_backend.Make(World)(Sparse_set_backend.Default)
   wraps the default backend with an opt-in, per-signature result cache.
   cache_signature only registers a (required, excludes) pair for caching —
   it does not fill it; the first iter/count after registration always pays
   a full scan (same cost as Query.Default) and snapshots each involved
   component's World.component_generation. Later calls for the same
   signature skip the scan and serve the cached match list directly, as
   long as no generation has moved; the moment one has, exactly one call
   pays a refill before the cache goes fresh again. A signature nobody
   registered behaves identically to Query.Default — caching is per
   signature, never blanket. *)
module Cached = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default))

let cached_backend_example () =
  let world = make_world () in
  let mover = World.create_entity world in
  World.add_component world mover Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world mover Components.Velocity.component
    ({ dx = 1.0; dy = 0.0 } : Components.Velocity.t);

  Cached.cache_signature
    ~required:[ Components.Local_transform.name; Components.Velocity.name ]
    ~excludes:[];

  (* First call fills the cache: a full scan, same cost as Query.Default. *)
  let filled =
    Cached.from world
    |> Cached.having Components.Local_transform.name
    |> Cached.having Components.Velocity.name
    |> Cached.count
  in
  assert (filled = 1);

  (* Nothing changed Local_transform's or Velocity's generation since the
     fill, so this call serves the cached match list directly. *)
  let still_cached =
    Cached.from world
    |> Cached.having Components.Local_transform.name
    |> Cached.having Components.Velocity.name
    |> Cached.count
  in
  assert (still_cached = 1);

  (* Adding Velocity to a second entity bumps Velocity's generation, so the
     next call for this signature detects staleness and refills once. *)
  let second = World.create_entity world in
  World.add_component world second Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world second Components.Velocity.component
    ({ dx = 0.0; dy = 1.0 } : Components.Velocity.t);

  let refilled =
    Cached.from world
    |> Cached.having Components.Local_transform.name
    |> Cached.having Components.Velocity.name
    |> Cached.count
  in
  assert (refilled = 2);

  Cached.uncache_signature
    ~required:[ Components.Local_transform.name; Components.Velocity.name ]
    ~excludes:[]

(* Parallel system: update receives a ro world — it cannot write directly,
   so it computes new positions and emits a command; on_command applies the
   mutation with rw access when the command bus is drained. *)
module Movement = struct
  type signal  = unit
  type event   = unit
  type command = [ `Move_to of Eon_ecs.Entity_id.t * float * float ]

  let on_signal  _ _ = ()
  let on_event   _ _ = ()

  let on_command (world : World.rw World.t) = function
    | `Move_to (entity, x, y) ->
      World.set_component world entity Components.Local_transform.component
        ({ position = Math.Vec2.create x y; rotation = 0.0; scale = Math.Vec2.one }
         : Components.Local_transform.t)

  let update (world : World.ro World.t) dt =
    let bus = Buses.Default.commands () in
    Query.Default.from world
    |> Query.Default.having Components.Local_transform.name
    |> Query.Default.having Components.Velocity.name
    |> Query.Default.iter (fun view ->
         let e   = View.entity view in
         let lt  = View.get view (module Components.Local_transform) in
         let vel = View.get view (module Components.Velocity) in
         Commands.emit bus (`Move_to (e, lt.position.x +. vel.dx *. dt,
                                          lt.position.y +. vel.dy *. dt)))
end

(* Exclusive system: update receives rw directly — structural mutations
   (destroy_entity, add/remove component) belong here, never in a
   Parallel system's update. *)
module Cleanup = struct
  type signal  = unit
  type event   = unit
  type command = unit

  let on_signal  _ _ = ()
  let on_event   _ _ = ()
  let on_command _ _ = ()

  let update (world : World.rw World.t) _dt =
    Query.Default.from world
    |> Query.Default.having Components.Tag.name
    |> Query.Default.iter (fun view ->
         let e   = View.entity view in
         let tag = View.get view (module Components.Tag) in
         if tag.value = "dead" then World.destroy_entity world e)
end

(* Pipeline.run dispatches parallel systems (concurrently, ro) then
   exclusive systems (sequentially, rw) for one phase — but it does NOT
   drain any bus itself. A command emitted during update is only staged;
   the caller must drain the command bus (Commands.drain, an alias for
   Single_bus's collect) before its on_command handler actually runs.
   Eon_engine.Loop (see the next chapter) does this automatically every
   frame; calling Pipeline.run directly, as here, means doing it by hand. *)
(* Pipeline.Default wires System.Default to the process-global Buses.Default
   singleton — every Pipeline.Default.create () is a fresh phase/system
   graph, but register_all attaches its systems' handlers to that same
   global bus. Calling register_all again from a second, independent
   Pipeline.Default instance without an intervening Pipeline.Default.reset
   leaves the FIRST instance's handlers still subscribed, so a later drain
   dispatches to both — reset () unsubscribes everything and clears the
   per-instance "already registered" guard so the next register_all starts
   clean. reset takes the pipeline value itself (its only real effect is
   global — unsubscribing every handler on Buses.Default — but the API
   still threads it through the instance whose "already registered" guard
   it also clears). Needed whenever more than one Pipeline.Default example
   runs in the same process, as here. *)
let parallel_and_exclusive_example () =
  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Gameplay
    |> Pipeline.Default.add_system `Gameplay (System.make_parallel  (module Movement))
    |> Pipeline.Default.add_system `Gameplay (System.make_exclusive (module Cleanup))
  in
  Pipeline.Default.reset pipeline;
  let world = make_world () in
  let mover = World.create_entity world in
  World.add_component world mover Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world mover Components.Velocity.component
    ({ dx = 1.0; dy = 0.0 } : Components.Velocity.t);

  let corpse = World.create_entity world in
  World.add_component world corpse Components.Tag.component
    ({ value = "dead" } : Components.Tag.t);

  Pipeline.Default.register_all pipeline world;
  let world = Pipeline.Default.run pipeline world (1.0 /. 60.0) in
  Commands.drain (Buses.Default.commands ());

  (match World.get_component world mover Components.Local_transform.component with
   | Some (lt : Components.Local_transform.t) -> assert (lt.position.x > 0.0)
   | None -> assert false);
  assert (not (World.is_alive world corpse))

(* Systems with reactive bus handlers: on_signal/on_event/on_command always
   receive rw and run sequentially during drain, regardless of whether the
   system's own update is Parallel or Exclusive. Events (Double_bus) are
   next-frame: an emission is only visible to on_event after TWO drains —
   the first moves it from the staging queue into the live queue, the
   second actually dispatches it. Commands (Single_bus) need only one. *)
module Combat = struct
  type signal  = unit
  type event   = [ `Enemy_died of Eon_ecs.Entity_id.t ]
  type command = [ `Apply_damage of Eon_ecs.Entity_id.t * int ]

  let on_signal _ _ = ()

  let on_event (world : World.rw World.t) = function
    | `Enemy_died e -> World.destroy_entity world e

  let health : int Components.t = Eon_engine.component "Health"

  let on_command (world : World.rw World.t) = function
    | `Apply_damage (e, amount) ->
      (match World.get_component world e health with
       | Some hp -> World.set_component world e health (hp - amount)
       | None -> ())

  let update (_world : World.ro World.t) _dt = ()
end

let reactive_handlers_example () =
  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Gameplay
    |> Pipeline.Default.add_system `Gameplay (System.make_parallel (module Combat))
  in
  Pipeline.Default.reset pipeline;
  let world = make_world () in
  let _ = World.register world Combat.health in
  let attacker = World.create_entity world in
  World.add_component world attacker Combat.health 10;
  let enemy = World.create_entity world in

  Pipeline.Default.register_all pipeline world;

  (* Command path: one drain is enough, same as the Movement example. *)
  Single_bus.emit (Buses.Default.commands ()) (`Apply_damage (attacker, 3));
  Commands.drain (Buses.Default.commands ());
  (match World.get_component world attacker Combat.health with
   | Some hp -> assert (hp = 7)
   | None -> assert false);

  (* Event path: needs two drains before on_event fires. *)
  Double_bus.emit (Buses.Default.events ()) (`Enemy_died enemy);
  assert (World.is_alive world enemy);
  Events.drain (Buses.Default.events ());
  assert (World.is_alive world enemy);   (* not dispatched yet *)
  Events.drain (Buses.Default.events ());
  assert (not (World.is_alive world enemy))

(* Inline closure style: for throwaway or test systems, skip the module
   file. Parallel/Exclusive resolve here via type-directed disambiguation
   from System.Default.make's expected argument type — write them
   unqualified. The fully-qualified form (System.Exclusive, System.Parallel)
   does NOT resolve: eon_engine.mli never re-exports System.update_kind or
   its constructors under the System module path, only System.S/DISPATCH/
   Make/Default, which reference update_kind structurally. *)
let inline_closure_example () =
  let world = make_world () in
  let count_system =
    System.Default.make
      (Parallel (fun world _dt ->
        let n = World.count_entities world in
        assert (n >= 0)))
      ~kind:`Variable
  in
  let spawn_system =
    System.Default.make
      (Exclusive (fun world _dt ->
        ignore (World.create_entity world)))
      ~kind:`Variable
  in
  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Setup
    |> Pipeline.Default.add_system `Setup count_system
    |> Pipeline.Default.add_system `Setup spawn_system
  in
  Pipeline.Default.reset pipeline;
  Pipeline.Default.register_all pipeline world;
  let before = World.count_entities world in
  let world = Pipeline.Default.run pipeline world 0.0 in
  assert (World.count_entities world = before + 1)

(* Executor: the threading-substrate seam Pipeline.Make dispatches parallel
   jobs through — Executor.S is just run_all : (unit -> unit) list -> unit,
   synchronous, blocking until every job completes. Pipeline.Default is
   fixed to Executor.Sequential internally.

   NOTE: swapping in a different Executor for a custom Pipeline.Make
   assembly (as the module doc comments on System.Make / Pipeline.Make
   suggest, e.g. "pass System.Make(Core) as the system argument") is not
   actually constructible from application code today: eon_engine.mli's
   [System.Make (C : Eon_ecs.System.S) : System.DISPATCH with type kind =
   C.kind] leaves Signal_bus/Event_bus/Command_bus abstract — it does not
   also constrain them to [= C.Signal_bus] etc. Every concrete Buses value
   (Buses.Default, or a fresh Buses.Make(Single_bus)(Double_bus)(Single_bus))
   is then structurally incompatible with any System.Make(...) result's bus
   types when passed to Pipeline.Make, even when built from the exact same
   underlying Single_bus/Double_bus modules. Pipeline.Default sidesteps this
   because it's assembled inside eon_engine itself, where the types are
   still transparent. Until System.Make's signature additionally exposes
   [and module Signal_bus = C.Signal_bus and module Event_bus = C.Event_bus
   and module Command_bus = C.Command_bus], a custom-Executor pipeline is a
   library-internal capability only, not a public one — use
   Executor.run_all directly (as below) if you need domain-pool parallelism
   for your own job batches outside the pipeline. *)
let executor_example () =
  let counter = Atomic.make 0 in
  let jobs = List.init 8 (fun _ () -> Atomic.incr counter) in
  Executor.Sequential.run_all jobs;
  assert (Atomic.get counter = 8);

  let pool_size = max 1 (Executor.Domain_pool.recommended_size () - 1) in
  let module Pool = Executor.Domain_pool.Make (struct let size = pool_size end) in
  let counter2 = Atomic.make 0 in
  let jobs2 = List.init 8 (fun _ () -> Atomic.incr counter2) in
  Pool.run_all jobs2;
  assert (Atomic.get counter2 = 8)

let () =
  query_example ();
  cached_backend_example ();
  parallel_and_exclusive_example ();
  reactive_handlers_example ();
  inline_closure_example ();
  executor_example ()
