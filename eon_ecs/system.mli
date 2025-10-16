module Make
  (Signal_bus  : Bus.BUS)
  (Event_bus   : Bus.BUS)
  (Command_bus : Bus.BUS)
  : sig
    type core = {
      register : World.t -> unit;
      update   : World.t -> float -> unit;
    }

    val make_core :
      ?register:(World.t -> unit) ->
      ?update:(World.t -> float -> unit) ->
      unit -> core

    type ('signal, 'event, 'command) reactive = {
      core       : core;
      on_signal  : World.t -> 'signal -> unit;
      on_event   : World.t -> 'event -> unit;
      on_command : World.t -> 'command -> unit;
    }

    type ('s, 'e, 'c) t = ('s, 'e, 'c) reactive

    val ignore_signal  : 'a -> 'b -> unit
    val ignore_event   : 'a -> 'b -> unit
    val ignore_command : 'a -> 'b -> unit

    val make_reactive :
      ?register:(World.t -> unit) ->
      ?update:(World.t -> float -> unit) ->
      ?on_signal:(World.t -> 's -> unit) ->
      ?on_event:(World.t -> 'e -> unit) ->
      ?on_command:(World.t -> 'c -> unit) ->
      unit -> ('s, 'e, 'c) t

    val from_core : core -> ('s, 'e, 'c) reactive
    val to_core   : ('s, 'e, 'c) reactive -> core

    val attach_handlers :
      ?signals:'s Signal_bus.t ->
      ?events:'e Event_bus.t ->
      ?commands:'c Command_bus.t ->
      World.t -> ('s, 'e, 'c) t -> unit
end
