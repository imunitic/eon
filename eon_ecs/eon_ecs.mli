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

module Query : sig
  include module type of Query
end

module Clock : sig
  module type S = Clock.S
  module Mtime : S
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
  module type S = System.S
  module type KIND = System.KIND

  module Base_kind : module type of System.Base_kind
  module Make_with_kinds : module type of System.Make_with_kinds
  module Make = System.Make
  module Default : module type of Make (Signals) (Events) (Commands)
end

module Pipeline : sig
  module type S = Pipeline.S
  module Make = Pipeline.Make
  module Default : module type of Make (System.Default)
end

module Progress : sig
  module type S = Progress.TIME_MODE
  module Make_with_kind : module type of Progress.Make_with_kind
  module Make = Progress.Make
  module Default : module type of Make (Pipeline.Default)
end

module Loop : sig
  module type CLOCK = Loop.CLOCK
  module type RENDERER = Loop.RENDERER
  module type BUSES = Loop.BUSES
  module Make = Loop.Make
  module Progress_adapter : sig
    type 'phase t = 'phase Progress.Default.t
    type world = World.t
    val tick : 'phase t -> world:world -> dt:float -> world
  end
  module Noop_renderer : RENDERER with type world = World.t and type result = unit
  module Default_buses : BUSES with type world = World.t
  module Default :
    module type of
      Make
        (Clock.Mtime)
        (Progress_adapter)
        (Noop_renderer)
        (Default_buses)
end
