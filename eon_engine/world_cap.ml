type ro = [ `R ]
type rw = [ `R | `W ]
type 'perm t = { raw : Eon_ecs.World.t }

let wrap raw    = { raw }
let readonly t  = { raw = t.raw }

(* Read operations *)
let get_component t entity comp =
  Eon_ecs.World.get_component t.raw entity ~name:(Component_descriptor.name comp)
let is_alive t              = Eon_ecs.World.is_alive t.raw
let count_entities t        = Eon_ecs.World.count_entities t.raw
let is_registered t comp    =
  Option.is_some (Eon_ecs.World.find_component t.raw ~name:(Component_descriptor.name comp))
let get_data t              = Eon_ecs.World.get_data t.raw
let get_service t           = Eon_ecs.World.get_service t.raw
let list_services t         = Eon_ecs.World.list_services t.raw
let iter_entities t         = Eon_ecs.Query.iter_entities t.raw
let has_component t entity name =
  match Eon_ecs.World.find_component t.raw ~name with
  | None -> false
  | Some _ -> Option.is_some (Eon_ecs.World.get_component t.raw entity ~name)

(* Write operations *)
let create_entity t         = Eon_ecs.World.create_entity t.raw
let destroy_entity t        = Eon_ecs.World.destroy_entity t.raw
let add_component t entity comp value =
  Eon_ecs.World.add_component t.raw entity ~name:(Component_descriptor.name comp) value
let set_component t entity comp value =
  Eon_ecs.World.set_component t.raw entity ~name:(Component_descriptor.name comp) value
let remove_component t entity comp =
  Eon_ecs.World.remove_component t.raw entity ~name:(Component_descriptor.name comp)
let remove_all_components t = Eon_ecs.World.remove_all_components t.raw
let add_data t              = Eon_ecs.World.add_data t.raw
let set_data t              = Eon_ecs.World.set_data t.raw
let add_service t           = Eon_ecs.World.add_service t.raw

(* Global ID counter for in-loop component registration via World_cap.
   Separate from Eon_engine.World.next_id which handles setup-time registration;
   this gives globally unique IDs across all worlds for runtime registration. *)
let next_id : int Atomic.t = Atomic.make 0

let register t comp =
  let name = Component_descriptor.name comp in
  if Option.is_some (Eon_ecs.World.find_component t.raw ~name) then
    Component_descriptor.Already_registered
  else begin
    let id = Atomic.fetch_and_add next_id 1 in
    ignore (Eon_ecs.World.register_component t.raw ~name ~id);
    Component_descriptor.Registered
  end
