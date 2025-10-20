(** Typed component definitions and runtime packing. *)

(** A component storing values of type ['a]. *)
type 'a component = {
  id   : int;
  name : string;
  mutable data : 'a Sparse_set.t;
}

(** Existential wrapper allowing heterogeneous component storage. *)
type any_component =
  | Component : 'a component -> any_component

(** Create a new typed component with the given ID and name. *)
val make : int -> string -> 'a component

(** Get the name of a component. *)
val name : any_component -> string

(** Get the ID of a component. *)
val id : any_component -> int

(** Apply a callback to the underlying sparse set, ignoring its result. *)
val with_data : any_component -> ('a Sparse_set.t -> unit) -> unit

(** Apply a callback to the underlying sparse set and return its result. *)
val with_data_result : any_component -> ('a Sparse_set.t -> 'b) -> 'b
