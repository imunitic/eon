module Registry : sig
  (** Internal, hash-table backed registry exposing raw storage helpers. *)
  (** Underlying hash-table type alias. *)
  type t

  (** Create an empty registry table. *)
  val create : unit -> ('a, 'b) Hashtbl.t

  (** Insert a component definition keyed by [name] and [id]. *)
  val register :
    t -> name:string -> id:int -> 'a Component.component

  (** Look up a component definition by name. *)
  val find : t -> name:string -> 'a Component.component option

  (** Visit every stored component definition. *)
  val iter : (Component.any_component -> unit) -> t -> unit

  (** Number of entries present in the table. *)
  val count : ('a, 'b) Hashtbl.t -> int
end

(** Registry of component definitions. Internal API. *)

(** Opaque registry handle. *)
type t

(** Create a new empty component registry. *)
val create : unit -> t

(** Register a new component by name and ID. Raises if already registered. *)
val register :
  t -> name:string -> id:int -> 'a Component.component

(** Look up a component by name. *)
val find :
  t -> name:string -> 'a Component.component option

(** Iterate over all registered components. *)
val iter :
  (Component.any_component -> unit) -> t -> unit

(** Number of registered components. *)
val count : t -> int
