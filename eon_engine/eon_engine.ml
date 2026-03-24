(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

module Components = Components

(** Check if a component is registered in the world. *)
let is_registered = Components.is_registered

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

(** Register a component descriptor with a world.

    This is a convenience alias for [Components.register].
    
    Example:
    {[
      Engine.register world Position.component
    ]}
*)
let register = Components.register