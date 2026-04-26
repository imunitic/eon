type t = {
    entities : Entity_manager.t;
    components : Component_registry.t; 
    resources : Resource_store.t;
  }

let create () =
  {
    entities = Entity_manager.create 128;
    components = Component_registry.create ();
    resources = Resource_store.create ();
  }

(* ---- Component API ---- *)
let register_component world ~name ~id =
  Component_registry.register world.components ~name ~id

let find_component world ~name =
  Component_registry.find world.components ~name

let remove_all_components world e =
  Component_registry.iter
    (fun (Component.Component c) ->
      Sparse_set.remove c.Component.data e)
    world.components

let add_component world entity ~name value =
  match Component_registry.find world.components ~name with
  | Some comp ->
     Entity_manager.add_component world.entities entity (Component.Component comp) value
  | None ->
     failwith ("Unknown component: " ^ name)

let set_component world entity ~name value =
  match Component_registry.find world.components ~name with
  | Some comp ->
      let component = Component.Component comp in
      Entity_manager.set_component world.entities entity component value
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

(* ----- Resource API ----- *)
(* data-plane *)
let add_data world key value =
  Resource_store.add_data world.resources key value

let set_data world key value =
  add_data world key value

let get_data world key =
  Resource_store.get_data world.resources key

let count_data world =
  Resource_store.count_data world.resources

(* service-plane *)
let add_service world name value =
  Resource_store.add_service world.resources name value

let get_service world name =
  Resource_store.get_service world.resources name

let list_services world =
  Resource_store.list_services world.resources

(* ----- Entity API ----- *)
let create_entity world = Entity_manager.create_entity world.entities
let destroy_entity world e =
  remove_all_components world e;
  Entity_manager.destroy_entity world.entities e
let count_entities world = Entity_manager.count world.entities
let is_alive world e = Entity_manager.is_alive world.entities e
let generation_at world id = Entity_manager.generation_at world.entities id
