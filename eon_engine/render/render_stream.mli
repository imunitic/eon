(** Ordered render command buffer with world-space and screen-space lists.

    World-space commands are camera-relative — a [`Set_camera] establishes the
    camera context for the draw commands that follow it. Screen-space commands
    are fixed to the screen regardless of camera; use for HUD and UI.

    Commands are stored in emission order. {!clear} resets both lists in place
    each frame — no allocation until collectors start adding commands. *)

type 'command t

val create     : unit -> 'command t
val clear      : 'command t -> unit
(** Reset both lists. Called by [Render_system] at the start of each frame. *)

val add_world  : 'command t -> 'command -> unit
val add_screen : 'command t -> 'command -> unit

val iter_world  : 'command t -> ('command -> unit) -> unit
(** Iterate world-space commands in emission order. *)

val iter_screen : 'command t -> ('command -> unit) -> unit
(** Iterate screen-space commands in emission order. *)

val fetch     : [> World.ro] World.t -> 'command t
(** Raises [Not_found] if no stream has been stored this frame. *)

val fetch_opt : [> World.ro] World.t -> 'command t option
(** Returns [None] when no [Render_system] is registered — expected in
    headless configurations. Use this in the loop. *)

val store : World.rw World.t -> 'command t -> unit
