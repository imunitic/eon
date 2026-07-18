(** Typed, phantom-constrained resource accessors for world-scoped data.

    A resource is per-frame or simulation-scoped data written by the engine
    loop or exclusive systems, readable by any system. Examples:
    [Raw_input_frame], [Audio_command_buffer], a per-frame delta-time record.

    Each resource module is a typed facade over the world data plane.
    The key is private to the module — nothing outside can construct a
    correctly typed access to its storage slot. *)

(** Convert any polymorphic variant to an opaque resource key for use with [Make]. *)
val key : [> ] -> Obj.t

(** Signature every resource module satisfies. *)
module type S = sig
  type t

  val fetch : [> World.ro] World.t -> t
  (** Read the resource. Accepts both [ro] and [rw] worlds — any system may
      read. Raises [Not_found] if the resource has not been stored. *)

  val store : World.rw World.t -> t -> unit
  (** Write the resource. Requires [rw] — only the loop and exclusive systems
      may write. The compiler prevents parallel systems from calling this. *)
end

(** Generate a [Resource.S] implementation.

    Usage:
    {[
      module Physics_state = Resource.Make(struct
        type t = Physics.world
        let key = Resource.key `Physics_state
      end)
    ]}

    [Resource.key] wraps any polymorphic variant so the functor argument
    typechecks. The wrapped value is used as the storage key in the world
    data plane — keep it unique per resource. *)
module Make (T : sig
  type t
  val key : Obj.t
end) : S with type t = T.t


