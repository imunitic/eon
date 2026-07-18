(** Typed, phantom-constrained service accessors for long-lived singletons.

    A service is registered once at startup and never mutated by game systems.
    Examples: a physics world handle, a network session context, a Steam API.

    The naming distinction from [Resource] signals intent:
    - [Resource.store] — per-frame write, expected in the loop or exclusive systems
    - [Service.register] — startup-only, before the loop starts *)

(** Convert any polymorphic variant to an opaque service key for use with [Make]. *)
val key : [> ] -> Obj.t

(** Signature every service module satisfies. *)
module type S = sig
  type t

  val fetch : [> World.ro] World.t -> t
  (** Read the service. Accepts both [ro] and [rw] worlds — any system may
      read. Raises [Not_found] if the service has not been registered. *)

  val register : World.rw World.t -> t -> unit
  (** Register the service. Intended for startup code before the loop starts.
      Calling this from inside a running system is semantically wrong even
      though the type allows it. *)
end

(** Generate a [Service.S] implementation.

    Usage:
    {[
      module Steam = Service.Make(struct
        type t = Steam_api.t
        let key = Service.key `Steam
      end)
    ]} *)
module Make (T : sig
  type t
  val key : Obj.t
end) : S with type t = T.t


