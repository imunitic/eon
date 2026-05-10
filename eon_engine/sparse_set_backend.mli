(** Default sparse set backend for query execution.
    
    This is the default backend that wraps Eon_ecs.Query directly.
    Applies having/excludes filters as post-filters inside the callback.
    
    Use with Query.Make:
    {[
      module Query = Eon_engine.Query.Make(Eon_engine.Sparse_set_backend)
    ]}
*)

include Query_backend.S with type world = World.t
