(** Sparse set storage indexed by zero-based integers. *)

(** Module type describing a key that can be mapped to an integer slot. *)
module type INDEXED_KEY = sig
  type t
  val index : t -> int
end

(** Signature exposed by sparse-set specialisations. *)
module type S = sig
  type key
  type 'a t

  val create : ?capacity:int -> unit -> 'a t
  val capacity : 'a t -> int
  val size : 'a t -> int
  val grow : 'a t -> unit
  val contains : 'a t -> key -> bool
  val get : 'a t -> key -> 'a option
  val add : 'a t -> key -> 'a -> unit
  val set_value : 'a t -> key -> 'a -> unit
  val remove : 'a t -> key -> unit
  val iter : (int -> 'a -> unit) -> 'a t -> unit
end

(** Build a sparse set keyed by the provided indexable type. *)
module Make (Key : INDEXED_KEY) : S with type key = Key.t

(** Default sparse set keyed by [Entity_id.t]. Backwards-compatible alias. *)
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

(** Integer-keyed sparse set helper for resource and service stores. *)
module Int : S with type key = int
