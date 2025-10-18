(** The Eon ECS world - holds entities, components, and resources. *)

type t

val create : unit -> t

val create_entity : t -> Entity_id.t
val destroy_entity : t -> Entity_id.t -> unit
val count_entities : t -> int
val is_alive : t -> Entity_id.t -> bool
val generation_at : t -> int -> int

val register_component : t -> name:string -> id:int -> 'a Component.component
val find_component : t -> name:string -> 'a Component.component option

(* data-plane store *)
val add_data : t -> string -> 'a -> unit
val get_data : t -> string -> 'a option
val count_data : t -> int

(* service-plane *)
val add_service : t -> string -> 'a -> unit
val get_service : t -> string -> 'a option
val list_services : t -> Resource_store.Type_id.t list

val add_component : t -> Entity_id.t -> name:string -> 'a -> unit
val get_component : t -> Entity_id.t -> name:string -> 'a option
val remove_component : t -> Entity_id.t -> name:string -> unit
