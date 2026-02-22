module Entity_id = Entity_id
module Component = Component
module World = World
module Query = Query
module Clock = Clock

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
  module type S = System.S
  module type KIND = System.KIND
  module Base_kind = System.Base_kind
  module Make_with_kinds = System.Make_with_kinds
  module Make = System.Make
  module Default = Make(Signals)(Events)(Commands)
end

(* -------------------------------------------------------------------------- *)
(* 🧩 Pipelines *)
(* -------------------------------------------------------------------------- *)

module Pipeline = struct
  module type S = Pipeline.S
  module Make = Pipeline.Make
  module Default = Make (System.Default)
end

(* -------------------------------------------------------------------------- *)
(* 🧩 Progress & Loop *)
(* -------------------------------------------------------------------------- *)

module Progress = struct
  module type S = Progress.TIME_MODE
  module Make_with_kind = Progress.Make_with_kind
  module Make = Progress.Make
  module Default = Make (Pipeline.Default)
end

module Loop = struct
  module type CLOCK = Loop.CLOCK
  module type RENDERER = Loop.RENDERER
  module type BUSES = Loop.BUSES
  module Make = Loop.Make

  module Noop_renderer = struct
    type world = World.t
    type result = unit
    let render _ ~dt:_ = ()
  end

  module Progress_adapter = struct
    type 'phase t = 'phase Progress.Default.t
    type world = World.t
    let tick = Progress.Default.tick
  end

  module Default_buses = Loop_default_buses

  module Default = Make
      (Clock.Mtime)
      (Progress_adapter)
      (Noop_renderer)
      (Default_buses)
end
