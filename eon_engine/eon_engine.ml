(** Eon Engine public API.

    This module is the canonical entry-point for users of the [eon-engine] package.
    It provides a higher-level, typed component registration API on top of Eon ECS.
*)

module Components = Components

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

(** Register a component descriptor with a world using an explicit ID.

    This is a convenience alias for [Components.register_component].
    
    Example:
    {[
      Engine.register_component world Position.component ~id:0
    ]}
*)
let register_component = Components.register_component

(** Register a component descriptor with a world using an automatically generated ID.

    This is a convenience alias for [Components.register].
    
    Example:
    {[
      Engine.register world Position.component
    ]}
*)
let register = Components.register