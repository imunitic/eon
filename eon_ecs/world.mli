(** The Eon ECS world - holds entities, components, and resources. *)

type t

val create : unit -> t

val create_entity : t -> Entity_id.t
val destroy_entity : t -> Entity_id.t -> unit
val count_entities : t -> int
val is_alive : t -> Entity_id.t -> bool

val register_component : t -> name:string -> id:int -> 'a Component.component
val find_component : t -> name:string -> 'a Component.component option

val add_resource : t -> string -> 'a -> unit
val get_resource : t -> string -> 'a option


val add_component : t -> Entity_id.t -> name:string -> 'a -> unit
val get_component : t -> Entity_id.t -> name:string -> 'a option
val remove_component : t -> Entity_id.t -> name:string -> unit
