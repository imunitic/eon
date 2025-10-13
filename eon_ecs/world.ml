type t = {
    entities : Entity_manager.t;
    components : Component_registry.t; 
    resources : Resource_store.t;
    data_index : (string, int) Hashtbl.t;  (* map string -> int *)
    mutable next_data_id : int
  }

let create () =
  {
    entities = Entity_manager.create 128;
    components = Component_registry.create ();
    resources = Resource_store.create ();
    data_index = Hashtbl.create 16;
    next_data_id = 0;
  }

(* ----- Entity API ----- *)
let create_entity world = Entity_manager.create_entity world.entities
let destroy_entity world e = Entity_manager.destroy_entity world.entities e
let count_entities world = Entity_manager.count world.entities
let is_alive world e = Entity_manager.is_alive world.entities e

(* ---- Component API ---- *)
let register_component world ~name ~id =
  Component_registry.register world.components ~name ~id

let find_component world ~name =
  Component_registry.find world.components ~name

(* ----- Resource API ----- *)
let resolve_data_id world key =
  match Hashtbl.find_opt world.data_index key with
  | Some id -> id
  | None ->
      let id = world.next_data_id in
      world.next_data_id <- id + 1;
      Hashtbl.add world.data_index key id;
      id
(* data-plane *)
let add_data world key value =
  let id = resolve_data_id world key in
  Resource_store.add_data world.resources id value

let get_data world key =
  let id = resolve_data_id world key in
  Resource_store.get_data world.resources id

let count_data world =
  Resource_store.count_data world.resources

(* service-plane *)
let add_service world name value =
  Resource_store.add_service
    world.resources (Resource_store.of_typename name) value

let get_service world name =
  Resource_store.get_service
    world.resources (Resource_store.of_typename name)

let list_services world =
  Resource_store.list_services world.resources
  
let add_component world entity ~name value =
  match Component_registry.find world.components ~name with
  | Some comp ->
     Entity_manager.add_component world.entities entity (Component.Component comp) value
  | None ->
     failwith ("Unknown component: " ^ name)

let get_component world entity ~name =
  match Component_registry.find world.components ~name with
  | Some comp ->
     Entity_manager.get_component world.entities entity (Component.Component comp)
  | None ->
     failwith ("Unknown component: " ^ name)

let remove_component world entity ~name =
  match Component_registry.find world.components ~name with
  | Some comp ->
     Entity_manager.remove_component world.entities entity (Component.Component comp)
  | None ->
     failwith ("Unknown component: " ^ name)
