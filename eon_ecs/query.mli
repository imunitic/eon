val iter1 : World.t -> string -> (Entity_id.t -> 'a -> unit) -> unit

val iter2 :
  World.t ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'a -> unit) ->
  unit

val iter3 :
  World.t ->
  string ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'a -> 'a -> unit) ->
  unit

val iter4 :
  World.t ->
  string ->
  string ->
  string ->
  string ->
  (Entity_id.t -> 'a -> 'a -> 'a -> 'a -> unit) ->
  unit

val count : World.t -> string list -> int
