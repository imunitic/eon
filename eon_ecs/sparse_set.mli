type 'a t
val create : ?capacity:int -> unit -> 'a t
val capacity : 'a t -> int
val size : 'a t -> int
val grow : 'a t -> unit
val contains : 'a t -> Entity_id.t -> bool
val get : 'a t -> Entity_id.t -> 'a option
val add : 'a t -> Entity_id.t -> 'a -> unit
val set_value : 'a t -> Entity_id.t -> 'a -> unit
val remove : 'a t -> Entity_id.t -> unit
val iter : (int -> 'a -> unit) -> 'a t -> unit
