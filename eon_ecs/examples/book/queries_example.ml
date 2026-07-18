(* Companion example for docs/eon_ecs chapter: Queries. *)

open Eon_ecs
open Components

let make_world () =
  let world = World.create () in
  Position.register world;
  Velocity.register world;
  Health.register world;
  world

(* iter1: every entity that has the one named component. *)
let iter1_example () =
  let world = make_world () in
  let a = World.create_entity world in
  World.add_component world a ~name:Position.name { Position.x = 0.0; y = 0.0 };

  let seen = ref 0 in
  Query.iter1 world Position.name (fun _entity (_pos : Position.t) -> incr seen);
  assert (!seen = 1)

(* iter2: entities that have BOTH named components — a movement system
   is the textbook case. *)
let iter2_example () =
  let world = make_world () in
  let moving  = World.create_entity world in
  let still   = World.create_entity world in
  World.add_component world moving ~name:Position.name { Position.x = 0.0; y = 0.0 };
  World.add_component world moving ~name:Velocity.name { Velocity.dx = 1.0; dy = 0.0 };
  World.add_component world still  ~name:Position.name { Position.x = 5.0; y = 5.0 };
  (* [still] has no Velocity — iter2 will skip it *)

  let moved = ref [] in
  Query.iter2 world Position.name Velocity.name
    (fun entity (pos : Position.t) (vel : Velocity.t) ->
       moved := (entity, pos.x +. vel.dx, pos.y +. vel.dy) :: !moved);
  assert (List.length !moved = 1)

(* Query.count and Query.iter_entities pick the SMALLEST of the named
   sparse sets as the iteration base, then check membership in the
   others — the base set's size, not the total entity count, drives
   the cost. Here Health is the smallest set (1 entity) even though
   Position has 6. *)
let smallest_set_first_example () =
  let world = make_world () in
  for i = 1 to 6 do
    let e = World.create_entity world in
    World.add_component world e ~name:Position.name { Position.x = float_of_int i; y = 0.0 };
    if i = 3 then
      World.add_component world e ~name:Health.name { Health.current = 100; max = 100 }
  done;
  (* base = Health (1 entity); Query.count only has to walk that one entity
     and check it against Position, not scan all 6 Position entities *)
  assert (Query.count world [ Position.name; Health.name ] = 1)

(* count/iter_entities raise Invalid_argument for an unregistered name —
   note this is a DIFFERENT exception than World.get_component's
   Failure (see the World and components chapter). Both mean the same
   thing (a missing register_component call), the underlying exception
   type genuinely differs between the two call sites in eon_ecs today. *)
let unregistered_name_raises () =
  let world = World.create () in
  match Query.count world [ "Never_registered" ] with
  | _ -> assert false
  | exception Invalid_argument _ -> ()

let () =
  iter1_example ();
  iter2_example ();
  smallest_set_first_example ();
  unregistered_name_raises ()
