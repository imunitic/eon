(** [Resource.S] facade for the per-frame render stream.

    Written by [Render_system] during the pipeline tick; consumed by the loop
    after [drain]. Absence is a legitimate runtime condition — headless
    simulations and servers run without a render stream. *)

type 'command t = 'command Render_stream.t

val fetch     : [> World.ro] World.t -> 'command t
(** Raises [Not_found] if no render stream has been stored this frame. *)

val fetch_opt : [> World.ro] World.t -> 'command t option
(** Returns [None] when no [Render_system] is registered. Use this in the
    loop — absence is expected in headless configurations. *)

val store : World.rw World.t -> 'command t -> unit
