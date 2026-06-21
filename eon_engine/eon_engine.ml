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

module World_cap = World_cap
module Executor  = Executor

module System = struct
  module type S        = System.S
  module type DISPATCH = System.DISPATCH
  module Make          = System.Make
  module Default       = System.Make(Eon_ecs.System.Make(Signals)(Events)(Commands))
end

module Pipeline = struct
  module type S = Pipeline.S
  module Make    = Pipeline.Make
  (* Default is wired here (not in pipeline.ml) so System.Default.t unifies
     with Pipeline.Default.system_t — same functor application, not a copy. *)
  module Default = Pipeline.Make(System.Default)(Executor.Sequential)
end

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

(** Extension API for backend implementors. *)
module Backend = struct
  module World = struct
    let to_raw = World.to_raw
  end
end
