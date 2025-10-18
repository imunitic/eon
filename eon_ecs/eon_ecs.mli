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
  module type S = System.S

  module Make = System.Make
  module Default : module type of Make (Signals) (Events) (Commands)
end

module Pipeline : sig
  module type S = Pipeline.S
  module Make = Pipeline.Make
  module Default : module type of Make (System.Default)
end
