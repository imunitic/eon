(** Engine bus family — mutex-wrapped singleton instances for signals, events,
    and commands.

    [Default] wires the engine's [Single_bus] (signals, commands) and
    [Double_bus] (events) — the same implementations as [Eon_ecs.Buses.Default]
    but with mutex-protected [emit] for parallel-system safety.

    Apply [Make] with remote transport modules for the multiplayer use case. *)

module Make
    (Signals_transport  : Bus.S)
    (Events_transport   : Bus.S)
    (Commands_transport : Bus.S) : sig
  val signals         : unit -> 'a Signals_transport.t
  val events          : unit -> 'a Events_transport.t
  val commands        : unit -> 'a Commands_transport.t
  val unsubscribe_all : unit -> unit
end

module Default : sig
  val signals         : unit -> 'a Single_bus.t
  val events          : unit -> 'a Double_bus.t
  val commands        : unit -> 'a Single_bus.t
  val unsubscribe_all : unit -> unit
end
