(* Companion example for docs/eon_engine chapter: World and components. *)

open Eon_engine

let make_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

(* World capabilities: rw is full access; readonly/as_ro downgrade to a
   read-only view, zero cost — only the phantom type changes. Read ops
   (is_alive, get_component, ...) accept either; write ops (create_entity,
   add_component, ...) are typed to require rw specifically. *)
let capabilities_example () =
  let world : World.rw World.t = make_world () in
  let player = World.create_entity world in

  let ro : World.ro World.t = World.readonly world in
  assert (World.is_alive ro player);

  (* World.create_entity ro would be a type error — ro has no write ops.
     Only rw handles reach this line: *)
  let _second = World.create_entity world in
  ()

(* Component descriptors: a typed value in place of a raw string key.
   Define once, register once, then use for every add/get/set/remove. *)
let health : int Components.t = Eon_engine.component "Health"

let component_descriptor_example () =
  let world = make_world () in
  let _ = World.register world health in
  let player = World.create_entity world in

  World.add_component world player health 100;
  match World.get_component world player health with
  | Some hp -> assert (hp = 100)
  | None -> assert false

(* Built-in components: Engine_components.register_all wires every
   shipped component in one call; extend it by including it in a
   game-specific registration module. *)
module Game_components = struct
  include Components.Engine_components

  let mana : int Components.t = Eon_engine.component "Mana"

  let register_all world =
    Components.Engine_components.register_all world;
    ignore (World.register world mana)
end

let built_in_components_example () =
  let world = World.create () in
  Game_components.register_all world;
  let player = World.create_entity world in
  World.add_component world player Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world player Game_components.mana 50;
  match World.get_component world player Components.Local_transform.component with
  | Some (t : Components.Local_transform.t) -> assert (t.position = Math.Vec2.zero)
  | None -> assert false

(* Resources and services: a typed facade over the raw data/service
   plane, generated per-resource so the storage key never leaks outside
   the module that owns it. The record type is named at the top level,
   not inline inside the functor argument — Resource.Make's result
   signature makes Physics_state.t transparently equal to this type, but
   a record type declared only inside an anonymous functor argument
   struct isn't in scope for field-label disambiguation afterwards. *)
type physics_state = { gravity : float; bodies : int }

module Physics_state = Resource.Make (struct
  type t = physics_state
  let key = Resource.key `Physics_state
end)

let resource_example () =
  let world = make_world () in
  Physics_state.store world { gravity = 9.8; bodies = 0 };
  let read_gravity (world : [> World.ro ] World.t) = (Physics_state.fetch world).gravity in
  assert (read_gravity world = 9.8)

(* Namespace: a flat directory of named worlds, for cross-world access.
   Composes with Resource.fetch/Service.fetch to reach a resource that
   lives in a DIFFERENT world than the one the current system was given. *)
let namespace_example () =
  let global_world = make_world () in
  Physics_state.store global_world { gravity = 9.8; bodies = 0 };

  let ns = Namespace.create () in
  Namespace.attach ns "global" global_world;

  (* Some other system, holding a different world entirely, reaches the
     global world's resource through the namespace: *)
  let other_world = World.create () in
  ignore other_world;
  let gravity =
    (Physics_state.fetch (Namespace.named "global" ns)).gravity
  in
  assert (gravity = 9.8);

  match Namespace.named "does_not_exist" ns with
  | _ -> assert false
  | exception Namespace.Unknown_namespace _ -> ()

let () =
  capabilities_example ();
  component_descriptor_example ();
  built_in_components_example ();
  resource_example ();
  namespace_example ()
