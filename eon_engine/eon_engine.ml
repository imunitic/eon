(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

module Math = Math
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
  module Default       = System.Default
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

module Resource  = Resource
module Service   = Service
module Namespace = Namespace

let default_global_ns = "global"

module Asset_lookup         = Asset_lookup
module Audio_command        = Audio_command
module Audio_command_buffer = Audio_command_buffer
module Audio_backend        = Audio_backend

module Key             = Key
module Mouse_button    = Mouse_button
module Gamepad_button  = Gamepad_button
module Raw_input_frame = Raw_input_frame
module Input_backend   = Input_backend

module Color                   = Color
module Render_commands         = Render_commands
module Render_stream           = Render_stream
module Rendering_result        = Rendering_result
module Rendering_backend       = Rendering_backend
module Render_stream_collector = Render_stream_collector
module Render_system           = Render_system

module Transform_hierarchy = Transform_hierarchy
module Transform_system = struct
  module Make    = Transform_system.Make
  module Default = Transform_system.Default
end
module Lifecycle_system = struct
  module Make    = Lifecycle_system.Make
  module Default = Lifecycle_system.Default
end

module Prefab = Prefab
module Prefab_edn = Prefab_edn
module Prefab_edn_defaults = Prefab_edn_defaults

module Time           = Time
module Platform        = Platform
module Progress = struct
  include Progress
  module Default           = Progress.Make(Pipeline.Default)
  module Default_with_time = Progress.Make_with_time(Pipeline.Default)(Time)
end
module Loop           = Loop
module Loop_buses     = Loop_buses

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

