(** Non-fatal errors returned by a {!Rendering_backend.S} render call.

    Truly fatal errors (GPU lost, out of memory) raise exceptions; this type
    carries softer failures (missing texture, unrecognised font_id) that the
    engine loop can log without aborting the frame. *)

type t = { errors : string list }

val empty      : t
val has_errors : t -> bool
