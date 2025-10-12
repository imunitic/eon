type t = {
    entities : Entity_manager.t;
    components : Component_registry.t; 
    resources : Resource_store.t
  }

let create () =
  {
    entities = Entity_manager.create 128;
    components = Component_registry.create ();
    resources = Resource_store.create ();
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
let add_resource world name value =
  Resource_store.add world.resources (Resource_store.of_typename name) value

let get_resource world name =
  Resource_store.get world.resources (Resource_store.of_typename name)

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
