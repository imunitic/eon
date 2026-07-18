(** ECS system that populates and stores a {!Render_stream} each frame.

    Creates a single [Render_stream] on construction, clears it at the start
    of each tick, runs the collector to repopulate it, then stores a reference
    under key [`Render_stream] in the world data plane for the engine loop to
    read.

    The system never calls the backend — it only produces data.

    Use {!Make} for the common case (wires into [Pipeline.Default]).
    Use {!Make_with_system} when running a custom pipeline built via
    [System.Make] / [Pipeline.Make]. *)

module Make_with_system
    (B   : Rendering_backend.S)
    (Sys : System.DISPATCH) : sig
  val make
    :  render_stream_collector:('phase, B.command) Render_stream_collector.t
    -> (unit, unit, unit) Sys.t
end

(** Convenience alias: [Make_with_system(B)(System.Default)]. *)
module Make (B : Rendering_backend.S) : sig
  val make
    :  render_stream_collector:('phase, B.command) Render_stream_collector.t
    -> (unit, unit, unit) System.Default.t
end
