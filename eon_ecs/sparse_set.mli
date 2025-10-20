(** Sparse set storage keyed by entity identifiers. *)

(** Packed storage for values associated with [Entity_id.t] keys. *)
type 'a t

(** Create an empty sparse set with an optional initial [capacity]. *)
val create : ?capacity:int -> unit -> 'a t

(** Maximum number of elements that can be stored without growing. *)
val capacity : 'a t -> int

(** Number of currently stored elements. *)
val size : 'a t -> int

(** Double the storage capacity to accommodate more entries. *)
val grow : 'a t -> unit

(** Test whether a value exists for the given entity. *)
val contains : 'a t -> Entity_id.t -> bool

(** Retrieve the stored value for an entity, if present. *)
val get : 'a t -> Entity_id.t -> 'a option

(** Insert a new value for an entity. Fails if the slot is already occupied. *)
val add : 'a t -> Entity_id.t -> 'a -> unit

(** Replace the value stored for an entity, growing the set if needed. *)
val set_value : 'a t -> Entity_id.t -> 'a -> unit

(** Remove any value associated with the entity. *)
val remove : 'a t -> Entity_id.t -> unit

(** Iterate over all stored entries in dense index order. *)
val iter : (int -> 'a -> unit) -> 'a t -> unit
