module Entity_id = Entity_id
module Component = Component
module World = World

module Bus = struct
  module type S = Bus.BUS
  module Single = Single_bus
  module Double = Double_bus
end

module Signals = Single_bus
module Events = Double_bus
module Commands = Single_bus

module System = System.Make(Signals)(Events)(Commands)
