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
val component : string -> 'a t

(** Get the name of a component descriptor. *)
val name : 'a t -> string

(** Check if a component descriptor is already registered in the world. *)
val is_registered : Eon_ecs.World.t -> 'a t -> bool

(** Register a component descriptor with a world using an explicit ID.
    
    Returns:
    - [Registered] if the component was newly registered
    - [Already_registered] if the component was already registered
    
    The operation is idempotent for the same component descriptor.
*)
val register_component : Eon_ecs.World.t -> 'a t -> id:int -> registration_result

(** Register a component descriptor with a world using an automatically generated ID.
    
    Uses a thread-safe global counter to generate unique IDs.
    
    Returns:
    - [Registered] if the component was newly registered
    - [Already_registered] if the component was already registered
    
    The operation is idempotent for the same component descriptor.
*)
val register : Eon_ecs.World.t -> 'a t -> registration_result