(** Per-frame audio command accumulator.

    Game systems append [Audio_command.t] values during tick. The loop reads
    the buffer once after drain, calls [Audio_backend.submit], then clears it.
    The buffer is stored in the world data plane and created once at startup. *)

type t

val create  : unit -> t
val clear   : t -> unit
val add     : t -> Audio_command.t -> unit
val to_list : t -> Audio_command.t list

val get : 'perm World.t -> t option
val set : World.rw World.t -> t -> unit
