(** Frame-level time resource.

    The concrete {!Time} module satisfies {!S}. Systems that need elapsed time
    or the frame counter fetch it via {!fetch}; the common case is just the
    [dt] parameter passed to [update].

    When using [Progress.Make_with_time], {!write} is called before the first
    tick and seeds the resource automatically — no manual pre-initialisation
    needed. {!fetch} raises [Not_found] only if called before the first tick. *)

(** Signature every Time module satisfies. *)
module type S = sig
  type t = { delta : float; elapsed : float; frame : int }
  include Resource.S with type t := t
  (* fetch : [> World.ro] World.t -> t        -- from Resource.S *)
  (* store : World.rw World.t -> t -> unit    -- from Resource.S *)
  val zero  : t
  val write : World.rw World.t -> float -> unit
end

(** {1 Concrete Time module} *)

type t = { delta : float; elapsed : float; frame : int }

val fetch : [> World.ro] World.t -> t
(** Read the current frame's time data. Raises [Not_found] if {!write} has
    never been called (i.e. before the first tick). *)

val store : World.rw World.t -> t -> unit
(** Write a time value directly. Useful for testing. *)

val zero  : t
val write : World.rw World.t -> float -> unit
