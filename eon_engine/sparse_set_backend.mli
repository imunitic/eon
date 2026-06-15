(** Sparse set backend for query execution.

    The default backend — delegates entity iteration to [World.iter_entities]
    and value fetching to [World.get_component]. Applies [having] and [excludes]
    as per-entity post-filters via [World.has_component].

    Use [Default] for the concrete instance backed by [World.t]:
    {[
      module Query = Eon_engine.Query.Make(Eon_engine.Sparse_set_backend.Default)
    ]}

    To use a custom world type that satisfies [World.S], apply [Make]:
    {[
      module My_backend = Eon_engine.Sparse_set_backend.Make(My_world)
      module Query = Eon_engine.Query.Make(My_backend)
    ]}
*)

module Make (W : World.S) : Query_backend.S with type world = W.t

module Default : Query_backend.S with type world = World.t
