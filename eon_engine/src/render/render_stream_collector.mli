(** Phase-ordered collector runner for {!Render_stream}.

    Collectors are registered to named phases. Phases are ordered via [~after]
    declarations; [collect] runs all collectors in topological phase order.

    This is the bridge between the ECS tick and the render backend: game code
    registers collectors here; {!Render_system} calls [collect] each frame. *)

type ('phase, 'command) t

(** A collector reads world state and emits commands into a stream. *)
type 'command collector = World.ro World.t -> 'command Render_stream.t -> unit

val create : unit -> ('phase, 'command) t

val add_phase : ?after:'phase -> 'phase -> ('phase, 'command) t -> ('phase, 'command) t
(** Add a phase. [~after:p] declares that [p] runs before the new phase.
    Raises [Invalid_argument] if [~after] names an unknown phase.
    No-op if the phase already exists (ordering edges are still applied). *)

val add_collector : 'phase -> 'command collector -> ('phase, 'command) t -> ('phase, 'command) t
(** Attach a collector to a phase. Collectors within a phase run in addition order.
    Raises [Invalid_argument] if the phase is not registered. *)

val collect : ('phase, 'command) t -> World.ro World.t -> 'command Render_stream.t -> unit
(** Run all collectors in topological phase order. *)
