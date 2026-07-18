(** Per-entity typed cursor, passed to the [Query.iter] callback.

    A [View.t] points at one entity for the duration of an iteration step.
    Use [get] to read components the query required (guaranteed present) and
    [get_opt] for components that may or may not be present.

    Example:
    {[
      Query.from world
      |> Query.having Position.name
      |> Query.having Velocity.name
      |> Query.iter (fun view ->
           let pos = View.get view (module Position) in
           let vel = View.get view (module Velocity) in
           ...)
    ]}
*)

type t

val entity : t -> Eon_ecs.Entity_id.t
(** The entity this view points at. *)

val get : t -> (module C : Component.S) -> C.t
(** Typed read. Raises [Invalid_argument] if the component is absent on this
    entity — treat a raise as a programmer error (you read a component you did
    not require in the query). *)

val get_opt : t -> (module C : Component.S) -> C.t option
(** Typed optional read. Returns [None] if the component is absent.
    Use for components not listed in the query's [having] filters. *)

val make : 'perm World.t -> Eon_ecs.Entity_id.t -> t
(** Internal constructor — used by [Query.Make]. Not for game code. *)
