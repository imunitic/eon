(** Query backend signature for pluggable query execution strategies.

    This signature defines the interface for query backends that implement
    entity iteration and counting operations. The backend is responsible for
    efficiently iterating over entities that match the given component constraints.

    Key design decisions:
    - Abstract [world] type decouples backend from Eon_ecs.World.t
    - Three constraint lists: includes (fetch values), having (presence only), excludes (must be absent)
    - Backends are chosen at compile time via functor application
*)

module type S = sig
  type world
  (** Abstract world type — decouples backend from Eon_ecs.World.t.
      Sparse_set_backend sets this to Eon_ecs.World.t.
      A future full archetype storage backend sets it to its own world type. *)

  val iter1 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> unit) ->
    unit
  (** Iterate over entities that have all components in [includes], 
      have all components in [having] (but don't fetch their values),
      and do not have any components in [excludes].
      
      The callback receives the entity ID and values for components in [includes].
      The order of values matches the order of component names in [includes]. *)

  val iter2 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> 'b -> unit) ->
    unit
  (** Like [iter1] but with two included components. *)

  val iter3 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> 'b -> 'c -> unit) ->
    unit
  (** Like [iter1] but with three included components. *)

  val iter4 :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    (Eon_ecs.Entity_id.t -> 'a -> 'b -> 'c -> 'd -> unit) ->
    unit
  (** Like [iter1] but with four included components. *)

  val count :
    world ->
    includes:string list ->
    having:string list ->
    excludes:string list ->
    int
  (** Count entities that match the given constraints without iterating. *)
end
