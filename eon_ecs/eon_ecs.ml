module Entity_id = Entity_id
module Component = Component
module World = World

(* -------------------------------------------------------------------------- *)
(* 🧩 Buses *)
(* -------------------------------------------------------------------------- *)

module Bus = struct
  module type S = Bus.BUS
  module Single = Single_bus
  module Double = Double_bus
end

module Signals  = Single_bus
module Events   = Double_bus
module Commands = Single_bus

(* -------------------------------------------------------------------------- *)
(* 🧩 Systems *)
(* -------------------------------------------------------------------------- *)

(* Export the functor itself for custom bus configurations *)
module System = struct
  module Make = System.Make
  module Default = System.Make(Signals)(Events)(Commands)
end
