(** Component descriptor type and core operations for Eon Engine.

    This module defines the phantom type ['a t] used for typed component
    descriptors, along with the fundamental operations for creating and
    registering components.

    Component descriptors are typed references to component types that can be
    registered with a world. They're essentially strings with a phantom type
    parameter for compile-time type safety.
*)

(** Component descriptor type.

    A component descriptor contains the component's name.
    The type parameter ['a] is a phantom type used for type safety when
    adding/getting components from entities.
*)
type 'a t = string

(** Alias for component descriptor type, to avoid ambiguity with module type t. *)
type 'a component_descriptor = 'a t

(** Registration result type. *)
type registration_result = 
  | Registered
  | Already_registered

(** Create a component descriptor with a given name. 
    
    The same name will always return the same descriptor, but the phantom
    type parameter allows it to be used at different types.
*)
let component name : 'a t =
  name

(** Private module for ID generation using OCaml 5 Atomic features.
    
    Not exposed to users - internal engine implementation.
*)
module Id_counter = struct
  let counter = Atomic.make 0
  
  (** Get next globally unique component ID. *)
  let next () : int =
    Atomic.fetch_and_add counter 1
end

(** Key for storing component registration state in world data plane. *)
let registration_key = `Eon_engine_component_registry

(** Get or create component registration hashtable in world data plane. *)
let get_or_create_registry world : (string, int) Hashtbl.t =
  match Eon_ecs.World.get_data world registration_key with
  | Some registry -> registry
  | None ->
      let registry = Hashtbl.create 16 in
      Eon_ecs.World.add_data world registration_key registry;
      registry

let name (comp : 'a t) : string =
  comp

let is_registered world (comp : 'a t) : bool =
  let registry = get_or_create_registry world in
  Hashtbl.mem registry comp

(** Register a component with an automatically generated global ID. *)
let register world (comp : 'a t) : registration_result =
  let registry = get_or_create_registry world in
  
  (* Check if this component name is already registered *)
  match Hashtbl.find_opt registry comp with
  | Some _existing_id ->
      Already_registered
  | None ->
      let id = Id_counter.next () in
      (* Register with Eon_ecs *)
      let _ = Eon_ecs.World.register_component world ~name:comp ~id in
      (* Update registry *)
      Hashtbl.add registry comp id;
      Registered