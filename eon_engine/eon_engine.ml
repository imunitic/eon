(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

module World = World
module Components = Components
module Query_backend = Query_backend
module Sparse_set_backend = Sparse_set_backend
module Query = Query
module View = View

module Bus        = Bus
module Single_bus = Single_bus
module Double_bus = Double_bus
module Signals    = Single_bus
module Events     = Double_bus
module Commands   = Single_bus

module Executor  = Executor

module Buses = Buses

module System = struct
  module type S        = System.S
  module type DISPATCH = System.DISPATCH
  module Make          = System.Make
  module Default       = System.Make(Eon_ecs.System.Make(Signals)(Events)(Commands))
  module type Parallel_def  = System.Parallel_def
  module type Exclusive_def = System.Exclusive_def
  module Make_factory       = System.Make_factory
  (* Default_factory and make_system are defined here (not in system.ml) so the
     return type of make_system uses this Default — same functor application as
     Pipeline.Default. *)
  module Default_factory  = System.Make_factory(Default)
  let make_parallel       = Default_factory.make_parallel
  let make_exclusive      = Default_factory.make_exclusive
end

module Pipeline = struct
  module type S = Pipeline.S
  module Make    = Pipeline.Make
  (* Default is wired here (not in pipeline.ml) so System.Default.t unifies
     with Pipeline.Default.system_t — same functor application, not a copy. *)
  module Default = Pipeline.Make(System.Default)(Executor.Sequential)(Buses.Default)
end

module Progress  = Progress
module Loop      = Loop
module Loop_buses = Loop_buses

(** Entity identifier type. *)
type entity_id = Eon_ecs.Entity_id.t

(** Create a component descriptor with a given name.

    This is a convenience alias for [Components.component].
    
    Note: The phantom type parameter requires a type annotation when binding
    the descriptor to ensure proper type inference. Component descriptors are
    typically defined once in modules and used many times without annotations.
    
    Example:
    {[
      module Position = struct
        type t = { x : float; y : float }
        let component : t Engine.Components.t = Engine.component "Position"
      end
    ]}
*)
let component = Components.component

