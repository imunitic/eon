(** Sparse set backend for query execution.

    The default backend. Delegates entity iteration to [World.iter_entities]
    and applies [excludes] as a per-entity post-filter via [World.has_component].
    Never touches component values — value extraction is the caller's job via [View].

    Use [Default] for the concrete instance backed by [World.t]:
    {[
      module Q = Eon_engine.Query.Make(Eon_engine.Sparse_set_backend.Default)
    ]}

    To use a custom world type that satisfies [World.S], apply [Make]:
    {[
      module My_backend = Eon_engine.Sparse_set_backend.Make(My_world)
      module Q = Eon_engine.Query.Make(My_backend)
    ]}
*)

module Make (W : World.S) : Query_backend.S with type world = W.t

module Default : Query_backend.S with type world = World.t
