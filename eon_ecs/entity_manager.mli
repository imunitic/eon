module Entity_id = Entity_id

type t 
val create : int -> t
val capacity : t -> int
val count : t -> int
val grow : t -> unit
val create_entity : t -> Entity_id.t
val destroy_entity : t -> Entity_id.t -> unit
val is_alive : t -> Entity_id.t -> bool
