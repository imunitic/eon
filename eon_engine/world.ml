type entity_id = Eon_ecs.Entity_id.t

(* ================================================================ *)
(* World.S — Backend signature                                       *)
(* ================================================================ *)

module type S = sig
  type t

  val create               : unit -> t
  val create_entity        : t -> entity_id
  val add_component        : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val set_component        : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val get_component        : t -> entity_id -> 'a Component_descriptor.t -> 'a option
  val remove_component     : t -> entity_id -> 'a Component_descriptor.t -> unit
  val remove_all_components: t -> entity_id -> unit
  val destroy_entity       : t -> entity_id -> unit
  val register             : t -> 'a Component_descriptor.t -> Component_descriptor.registration_result
  val is_registered        : t -> 'a Component_descriptor.t -> bool
  val count_entities       : t -> int
  val is_alive             : t -> entity_id -> bool

  val add_data      : t -> [> ] -> 'a -> unit
  val set_data      : t -> [> ] -> 'a -> unit
  val get_data      : t -> [> ] -> 'a option
  val count_data    : t -> int
  val add_service   : t -> [> ] -> 'a -> unit
  val get_service   : t -> [> ] -> 'a option
  val list_services : t -> int list

  val iter_entities : t -> string list -> (entity_id -> unit) -> unit
  val has_component : t -> entity_id -> string -> bool
end

(* ================================================================ *)
(* Concrete World module                                             *)
(* ================================================================ *)

type t = {
  core              : Eon_ecs.World.t;
  mutable next_id   : int [@atomic];
}

let create () =
  { core = Eon_ecs.World.create (); next_id = 0 }

let create_entity world =
  Eon_ecs.World.create_entity world.core

let add_component world entity comp value =
  let name = Component_descriptor.name comp in
  Eon_ecs.World.add_component world.core entity ~name value

let set_component world entity comp value =
  let name = Component_descriptor.name comp in
  Eon_ecs.World.set_component world.core entity ~name value

let get_component world entity comp =
  let name = Component_descriptor.name comp in
  Eon_ecs.World.get_component world.core entity ~name

let remove_component world entity comp =
  let name = Component_descriptor.name comp in
  Eon_ecs.World.remove_component world.core entity ~name

let remove_all_components world entity =
  Eon_ecs.World.remove_all_components world.core entity

let destroy_entity world entity =
  Eon_ecs.World.destroy_entity world.core entity

let register world comp =
  let name = Component_descriptor.name comp in
  if Option.is_some (Eon_ecs.World.find_component world.core ~name) then
    Component_descriptor.Already_registered
  else begin
    let id = Atomic.Loc.fetch_and_add [%atomic.loc world.next_id] 1 in
    ignore (Eon_ecs.World.register_component world.core ~name ~id);
    Component_descriptor.Registered
  end

let is_registered world comp =
  Option.is_some
    (Eon_ecs.World.find_component world.core ~name:(Component_descriptor.name comp))

let count_entities world =
  Eon_ecs.World.count_entities world.core

let is_alive world entity =
  Eon_ecs.World.is_alive world.core entity

let add_data world key value =
  Eon_ecs.World.add_data world.core key value

let set_data world key value =
  Eon_ecs.World.set_data world.core key value

let get_data world key =
  Eon_ecs.World.get_data world.core key

let count_data world =
  Eon_ecs.World.count_data world.core

let add_service world key value =
  Eon_ecs.World.add_service world.core key value

let get_service world key =
  Eon_ecs.World.get_service world.core key

let list_services world =
  Eon_ecs.World.list_services world.core

let iter_entities world names f =
  Eon_ecs.Query.iter_entities world.core names f

let has_component world entity name =
  match Eon_ecs.World.find_component world.core ~name with
  | None -> false
  | Some _ -> Option.is_some (Eon_ecs.World.get_component world.core entity ~name)
