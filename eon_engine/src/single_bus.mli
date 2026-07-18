(** Same-frame engine bus with mutex-protected [emit].

    Embeds [Eon_ecs.Single_bus] and adds a [Mutex.t]; only [emit] locks.
    [drain = collect]: messages emitted during a frame are dispatched in
    the same frame's drain step. Satisfies [Bus.S]. *)

type 'msg t

val create  : unit -> 'msg t
val on      : 'msg t -> ('msg -> unit) -> unit
val clear   : 'msg t -> unit
val emit    : 'msg t -> 'msg -> unit
val collect : 'msg t -> unit
val drain   : 'msg t -> unit
