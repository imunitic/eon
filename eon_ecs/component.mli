(** Typed component definitions and runtime packing. *)

type 'a component = {
  id   : int;
  name : string;
  mutable data : 'a Sparse_set.t;
}
(** A component storing values of type ['a]. *)

type any_component =
  | Component : 'a component -> any_component
(** Existential wrapper allowing heterogeneous component storage. *)

val make : int -> string -> 'a component
(** Create a new typed component with the given ID and name. *)

val name : any_component -> string
(** Get the name of a component. *)

val id : any_component -> int
(** Get the ID of a component. *)

val with_data : any_component -> ('a Sparse_set.t -> unit) -> unit
val with_data_result : any_component -> ('a Sparse_set.t -> 'b) -> 'b
