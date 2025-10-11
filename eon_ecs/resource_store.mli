module Type_id : sig
  type t
end

type t

val create : unit -> t

val add : t -> Type_id.t -> 'a -> unit

val get : t -> Type_id.t -> 'a option

val remove : t -> Type_id.t -> unit

val clear : t -> unit

val list_keys : t -> Type_id.t list

val of_typename : string -> Type_id.t
