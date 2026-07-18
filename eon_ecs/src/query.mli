(** Query helpers over registered world components.

    Query functions iterate only alive entities and only those with the requested
    component sets.

    Example:
    {[
      Query.iter2 world "Position" "Velocity"
        (fun entity (x, y) (vx, vy) ->
           ignore entity;
           ignore (x +. vx, y +. vy))
    ]}
*)

(** Iterate over all entities that provide the named component, yielding each
    entity ID and component payload to the callback. *)
val iter1 :
  World.t ->
  string ->
  (Entity_id.t -> 'a -> unit) ->
  unit

(** Iterate over entities that have both named components, providing both values
    to the callback. *)
val iter2 :
  World.t ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'b -> unit) ->
  unit

(** Iterate over entities that expose three named components simultaneously. *)
val iter3 :
  World.t ->
  string ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'b -> 'c -> unit) ->
  unit

(** Iterate over entities that expose four named components simultaneously. *)
val iter4 :
  World.t ->
  string ->
  string ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'b -> 'c -> 'd -> unit) ->
  unit

(** Count the entities that contain every component listed.
    Raises [Invalid_argument] if any name was never registered — consistent
    with [iter_entities] and [get_component]. *)
val count : World.t -> string list -> int

(** Iterate every alive entity that holds all of the named components, using
    the smallest sparse set as the iteration base.
    Raises [Invalid_argument] if any name was never registered — consistent
    with [get_component] / [add_component]. *)
val iter_entities : World.t -> string list -> (Entity_id.t -> unit) -> unit
