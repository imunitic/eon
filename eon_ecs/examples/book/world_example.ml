(* Companion example for docs/eon_ecs chapter: World and components. *)

open Eon_ecs
open Components

(* Register once, per component, before any entity attaches it. *)
let make_world () =
  let world = World.create () in
  Position.register world;
  Health.register world;
  world

let entity_lifecycle () =
  let world = make_world () in

  let player = World.create_entity world in
  World.add_component world player ~name:Position.name { Position.x = 0.0; y = 0.0 };
  World.add_component world player ~name:Health.name { Health.current = 100; max = 100 };

  (* get_component: Some if the entity currently holds the component. *)
  (match World.get_component world player ~name:Health.name with
   | Some (h : Health.t) -> assert (h.current = 100)
   | None -> assert false);

  (* set_component overwrites the value; it promotes to an add if the
     entity didn't already have the component. *)
  World.set_component world player ~name:Health.name { Health.current = 80; max = 100 };

  (* get_component: None if the component is registered but was never
     attached to this entity — a normal, expected state. *)
  let enemy = World.create_entity world in
  (match World.get_component world enemy ~name:Health.name with
   | None -> ()
   | Some _ -> assert false);

  (* remove_component detaches without destroying the entity. *)
  World.remove_component world player ~name:Position.name;
  (match World.get_component world player ~name:Position.name with
   | None -> ()
   | Some _ -> assert false);

  (* destroy_entity detaches every remaining component — no manual
     cleanup needed. *)
  World.destroy_entity world player;
  World.destroy_entity world enemy

(* add/set/get/remove_component all raise if the component name was
   never registered — a distinct condition from "absent but
   registered." Never use this exception as a presence check; the
   [None] branch above is what a real presence check looks like. *)
let unregistered_name_raises () =
  let world = World.create () in
  let e = World.create_entity world in
  match World.get_component world e ~name:"Never_registered" with
  | _ -> assert false
  | exception Failure _ -> ()

(* component_generation: a monotonically increasing counter per registered
   component, bumped only when add_component/remove_component actually
   changes that component's membership on some entity — never on a
   value-only set_component of an already-present component. This is the
   staleness signal Eon_engine.Cached_backend snapshots to know when a
   cached query result needs a refill; eon_ecs itself has no consumer of
   it beyond exposing the primitive. *)
let component_generation_example () =
  let world = make_world () in
  let player = World.create_entity world in

  let g0 = World.component_generation world Health.name in

  (* add_component changes membership: generation bumps. *)
  World.add_component world player ~name:Health.name { Health.current = 100; max = 100 };
  let g1 = World.component_generation world Health.name in
  assert (g1 > g0);

  (* set_component on an already-present component changes only the
     value, not membership: generation does NOT bump. *)
  World.set_component world player ~name:Health.name { Health.current = 80; max = 100 };
  let g2 = World.component_generation world Health.name in
  assert (g2 = g1);

  (* remove_component changes membership again: generation bumps. *)
  World.remove_component world player ~name:Health.name;
  let g3 = World.component_generation world Health.name in
  assert (g3 > g2)

(* The data and service stores: a second plane of World storage for
   values that don't belong to any one entity. *)
let data_and_service_stores () =
  let world = World.create () in

  World.add_data world `Frame_count 0;
  World.set_data world `Frame_count 1;
  (match World.get_data world `Frame_count with
   | Some n -> assert (n = 1)
   | None -> assert false);

  World.add_service world `Rng (Random.State.make_self_init ());
  match World.get_service world `Rng with
  | Some (_ : Random.State.t) -> ()
  | None -> assert false

let () =
  entity_lifecycle ();
  unregistered_name_raises ();
  component_generation_example ();
  data_and_service_stores ()
