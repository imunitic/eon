module Entity_id = Entity_id

type t 
val create : int -> t
val capacity : t -> int
val count : t -> int
val grow : t -> unit
val create_entity : t -> Entity_id.t
val destroy_entity : t -> Entity_id.t -> unit
val is_alive : t -> Entity_id.t -> bool
val generation_at : t -> int -> int

val add_component : t -> Entity_id.t -> Component.any_component -> 'a -> unit
val set_component : t -> Entity_id.t -> Component.any_component -> 'a -> unit
val get_component : t -> Entity_id.t -> Component.any_component -> 'a option
val remove_component : t -> Entity_id.t -> Component.any_component -> unit
