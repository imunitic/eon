(** Eon Engine — Query Builder

    Builder pattern for constructing and executing queries over entities.
    Uses a pluggable backend via functor application.
*)

module Make (B : Query_backend.S) : sig
  type query
  (** Accumulated query constraints. Not resolved until iter/count is called. *)

  val from : B.world -> query
  (** Entry point. Captures the world, starts an empty query. *)

  (** -- Component value fetching --
      These contribute to callback arity. Order defines callback argument order. *)
  val with_component  : string -> query -> query
  val with_components : string list -> query -> query

  (** -- Presence filters (markers) --
      Must be present but value is NOT fetched. Do NOT contribute to arity.
      Use case: `having "Frozen"` filters to frozen entities without pulling
      the Frozen value into the callback. *)
  val having      : string -> query -> query
  val having_all  : string list -> query -> query

  (** -- Exclusion filters --
      Must be absent. Do NOT contribute to arity. *)
  val not_having     : string -> query -> query
  val not_having_any : string list -> query -> query

  (** -- Execution --
      Callback argument order matches with_component call order.
      iter1 expects exactly 1 with_component, iter2 expects exactly 2, etc.
      Raises invalid_arg if arity does not match. *)
  val iter1 : (Eon_ecs.Entity_id.t -> 'a -> unit)                      -> query -> unit
  val iter2 : (Eon_ecs.Entity_id.t -> 'a -> 'b -> unit)                -> query -> unit
  val iter3 : (Eon_ecs.Entity_id.t -> 'a -> 'b -> 'c -> unit)          -> query -> unit
  val iter4 : (Eon_ecs.Entity_id.t -> 'a -> 'b -> 'c -> 'd -> unit)    -> query -> unit

  val count : query -> int
end
