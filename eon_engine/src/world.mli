(** Eon Engine World wrapper. *)

(** Entity identifier — alias for [Eon_ecs.Entity_id.t]. *)
type entity_id = Eon_ecs.Entity_id.t

(** Read-only capability. *)
type ro = [ `R ]

(** Read-write capability. *)
type rw = [ `R | `W ]

(* ================================================================ *)
(* World.S — Backend signature                                       *)
(* ================================================================ *)

(** Uniform world signature that query backends depend on.
    Only exposes read operations so any ['perm t] is accepted.
    Backends call [iter_entities] and [has_component] exclusively. *)
module type S = sig
  type 'perm t

  val get_component    : 'perm t -> entity_id -> 'a Component_descriptor.t -> 'a option
  val is_alive         : 'perm t -> entity_id -> bool
  val is_registered    : 'perm t -> 'a Component_descriptor.t -> bool
  val count_entities   : 'perm t -> int
  val get_data         : 'perm t -> [> ] -> 'a option
  val count_data       : 'perm t -> int
  val get_service      : 'perm t -> [> ] -> 'a option
  val list_services    : 'perm t -> int list

  val iter_entities : 'perm t -> string list -> (entity_id -> unit) -> unit
  (** Iterate every alive entity that has all of the named components, using the
      smallest sparse set as the iteration base. Raises [Invalid_argument] if any
      name was never registered. *)

  val has_component : 'perm t -> entity_id -> string -> bool
  (** Return [true] if the entity currently holds the named component.
      Returns [false] if the component is not registered or is absent on the entity. *)
end

(* ================================================================ *)
(* Concrete World module                                             *)
(* ================================================================ *)

(** Opaque handle to the engine world. ['perm] is phantom: [ro] for
    read-only access, [rw] for full read-write access. *)
type 'perm t

(** Create a new empty world with full read-write capability. *)
val create : unit -> rw t

(** Downgrade to read-only. Zero cost — only the phantom type changes. *)
val readonly : rw t -> ro t

(** Downgrade any capability level to read-only. Zero cost.
    Safe because [ro t] is a strict subset of any ['perm t]'s operations. *)
val as_ro : 'perm t -> ro t

(** {2 Read operations — accept any capability} *)

val get_component        : 'perm t -> entity_id -> 'a Component_descriptor.t -> 'a option
val is_alive             : 'perm t -> entity_id -> bool
val is_registered        : 'perm t -> 'a Component_descriptor.t -> bool
val count_entities       : 'perm t -> int

val get_data      : 'perm t -> [> ] -> 'a option
val count_data    : 'perm t -> int
val get_service   : 'perm t -> [> ] -> 'a option
val list_services : 'perm t -> int list

val iter_entities : 'perm t -> string list -> (entity_id -> unit) -> unit
val has_component : 'perm t -> entity_id -> string -> bool

(** {2 Write operations — require [rw] capability} *)

val create_entity        : rw t -> entity_id
val destroy_entity       : rw t -> entity_id -> unit
val add_component        : rw t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
val set_component        : rw t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
val remove_component     : rw t -> entity_id -> 'a Component_descriptor.t -> unit
val remove_all_components: rw t -> entity_id -> unit
val register             : rw t -> 'a Component_descriptor.t -> Component_descriptor.registration_result

val add_data    : rw t -> [> ] -> 'a -> unit
val set_data    : rw t -> [> ] -> 'a -> unit
val add_service : rw t -> [> ] -> 'a -> unit
