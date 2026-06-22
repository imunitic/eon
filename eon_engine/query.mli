(** Eon Engine — Query Builder

    Builder pattern for constructing and executing queries over entities.
    Uses a pluggable backend via functor application.

    Example:
    {[
      module Q = Query.Make(Sparse_set_backend.Default)

      Q.from world
      |> Q.having Position.name
      |> Q.having Velocity.name
      |> Q.not_having Frozen.name
      |> Q.iter (fun view ->
           let pos = View.get view Position.component in
           let vel = View.get view Velocity.component in
           ...)
    ]}
*)

module Make (B : Query_backend.S with type 'perm world = 'perm World.t) : sig
  type 'perm query
  (** Accumulated query constraints. Not resolved until [iter] or [count] is called.
      The ['perm] parameter tracks the world capability from [from]. *)

  val from : 'perm B.world -> 'perm query
  (** Entry point. Captures the world, starts an empty query.
      Accepts both [ro] and [rw] worlds — queries are always read-only. *)

  (** {2 Filters} *)

  val having     : string -> 'perm query -> 'perm query
  (** Require the named component to be present.
      Use for components you will read via [View.get] and for marker components
      you will not read — both are just "must be present." *)

  val having_all : string list -> 'perm query -> 'perm query
  (** Require all named components to be present. *)

  val not_having     : string -> 'perm query -> 'perm query
  (** Require the named component to be absent. *)

  val not_having_any : string list -> 'perm query -> 'perm query
  (** Require all named components to be absent. *)

  (** {2 Execution} *)

  val iter  : (View.t -> unit) -> 'perm query -> unit
  (** Iterate every matching entity. The callback receives a [View.t] cursor;
      use [View.get] / [View.get_opt] to read component values and
      [View.entity] to get the entity id. *)

  val count : 'perm query -> int
  (** Count matching entities without a callback. *)
end
