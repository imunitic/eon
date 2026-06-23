(** Bus family — polymorphic singleton instances for signals, events, and commands.

    [Make] creates a new bus family from three transport implementations.
    [Default] wires [Single_bus] (signals, commands) and [Double_bus] (events).

    Bus instances are polymorphic in their message type; the concrete type is
    fixed on first use via [System.attach] or a direct [Bus.emit] / [Bus.on]
    call. The polymorphism is achieved with [Obj.magic] — the same boundary
    used by [World.get_service]. Each bus should carry one game-level message
    type (a variant union); mixing incompatible types on the same instance is
    a logic error that [Obj.magic] cannot detect at runtime.

    For the multiplayer use case, apply [Make] with remote transport modules
    instead of using [Default]. *)

module Make
    (Signals_transport  : Bus.S)
    (Events_transport   : Bus.S)
    (Commands_transport : Bus.S) : sig
  val signals  : unit -> 'a Signals_transport.t
  val events   : unit -> 'a Events_transport.t
  val commands : unit -> 'a Commands_transport.t
end

module Default : sig
  val signals  : unit -> 'a Single_bus.t
  val events   : unit -> 'a Double_bus.t
  val commands : unit -> 'a Single_bus.t
end
