(** Generational entity identifier. *)

(** An opaque entity identifier, combining index and generation. *)
type t

(** Create an entity ID from index and generation. *)
val make : int -> int -> t

(** Get the index portion of the ID. *)
val index : t -> int

(** Get the generation portion of the ID. *)
val generation : t -> int

(** Compare two IDs for equality. *)
val equal : t -> t -> bool

(** Sentinel invalid entity ID. *)
val invalid : t
