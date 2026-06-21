(** Next-frame engine bus with mutex-protected [emit].

    Embeds [Eon_ecs.Double_bus] and adds a [Mutex.t]; only [emit] locks.
    Emissions are staged: they become visible the next frame after [drain]
    swaps the buffers. Satisfies [Bus.S]. *)

type 'msg t

val create  : unit -> 'msg t
val on      : 'msg t -> ('msg -> unit) -> unit
val emit    : 'msg t -> 'msg -> unit
val collect : 'msg t -> unit
val drain   : 'msg t -> unit
