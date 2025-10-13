module Type_id : sig
  type t
end

type t

type packed = Pack : 'a * (unit -> string) -> packed

val create : unit -> t
val add_service : t -> Type_id.t -> 'a -> unit
val get_service : t -> Type_id.t -> 'a option
val remove_service : t -> Type_id.t -> unit
val list_services : t -> Type_id.t list
val add_data : t -> int -> 'a -> unit
val get_data : t -> int -> 'a option
val remove_data : t -> int -> unit
val iter_data : (int -> 'a -> unit) -> t -> unit
val count_data : t -> int
val of_typename : string -> Type_id.t
