(** Generational entity identifier. *)

type t
(** An opaque entity identifier, combining index and generation. *)

val make : int -> int -> t
(** Create an entity ID from index and generation. *)

val index : t -> int
(** Get the index portion of the ID. *)

val generation : t -> int
(** Get the generation portion of the ID. *)

val equal : t -> t -> bool
(** Compare two IDs for equality. *)

val invalid : t
(** Sentinel invalid entity ID. *)
