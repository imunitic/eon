module Entity_id : sig
  (** Unique, generational entity identifiers. *)
  include module type of Entity_id
end

module Component : sig
  (** Defines component metadata and typed storage. *)
  include module type of Component
end

module World : sig
  (** Central ECS world — manages entities, components, and resources. *)
  include module type of World
end

module Bus : sig
  module type S = Bus.BUS
  module Single = Single_bus
  module Double = Double_bus
end

module Signals = Single_bus
module Events = Double_bus
module Commands = Single_bus

module System : sig
  (** The functor used to create a system type from custom bus modules. *)
  module Make :
  functor (Signal_bus  : Bus.S)
            (Event_bus   : Bus.S)
            (Command_bus : Bus.S)
  -> sig
    type core = {
        register : World.t -> unit;
        update   : World.t -> float -> unit;
      }

    type ('signal, 'event, 'command) reactive = {
        core       : core;
        on_signal  : World.t -> 'signal -> unit;
        on_event   : World.t -> 'event -> unit;
        on_command : World.t -> 'command -> unit;
      }

    val make_core :
      ?register:(World.t -> unit) ->
      ?update:(World.t -> float -> unit) ->
      unit -> core

    val make_reactive :
      ?register:(World.t -> unit) ->
      ?update:(World.t -> float -> unit) ->
      ?on_signal:(World.t -> 's -> unit) ->
      ?on_event:(World.t -> 'e -> unit) ->
      ?on_command:(World.t -> 'c -> unit) ->
      unit -> ('s, 'e, 'c) reactive

    val attach_handlers :
      ?signals:'s Signal_bus.t ->
      ?events:'e Event_bus.t ->
      ?commands:'c Command_bus.t ->
      World.t ->
      ('s, 'e, 'c) reactive ->
      unit
  end

  module Default :
  sig
    include module type of System.Make(Signals)(Events)(Commands)
  end
end
