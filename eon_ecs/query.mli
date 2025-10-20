(** Iteration helpers for accessing component storage. *)

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
  (Entity_id.t -> 'a -> 'a -> unit) ->
  unit

(** Iterate over entities that expose three named components simultaneously. *)
val iter3 :
  World.t ->
  string ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'a -> 'a -> unit) ->
  unit

(** Iterate over entities that expose four named components simultaneously. *)
val iter4 :
  World.t ->
  string ->
  string ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'a -> 'a -> 'a -> unit) ->
  unit

(** Count the entities that contain every component listed. *)
val count : World.t -> string list -> int
