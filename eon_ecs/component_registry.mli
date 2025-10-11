module Registry : sig
  type t

  val create : unit -> ('a, 'b) Hashtbl.t

  val register :
    t -> name:string -> id:int -> 'a Component.component

  val find : t -> name:string -> 'a Component.component option
  val iter : (Component.any_component -> unit) -> t -> unit
  val count : ('a, 'b) Hashtbl.t -> int
end

(** Registry of component definitions. Internal API. *)

type t
(** Opaque registry handle. *)

val create : unit -> t
(** Create a new empty component registry. *)

val register :
  t -> name:string -> id:int -> 'a Component.component
(** Register a new component by name and ID. Raises if already registered. *)

val find :
  t -> name:string -> 'a Component.component option
(** Look up a component by name. *)

val iter :
  (Component.any_component -> unit) -> t -> unit
(** Iterate over all registered components. *)

val count : t -> int
(** Number of registered components. *)
