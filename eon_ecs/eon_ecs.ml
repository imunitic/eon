module Entity_id = Entity_id
module Component = Component
module World = World

module Signals = Single_bus
module Events = Double_bus
module Commands = Single_bus

module System = System.Make(Signals)(Events)(Commands)
