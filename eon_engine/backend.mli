(** Extension API for backend implementors.
    
    This module provides the API surface for implementing custom backends
    and extensions to Eon Engine. If you're building a game with eon_engine,
    you don't need this module.
*)

module World : sig
  val to_raw : World.t -> Eon_ecs.World.t
end

