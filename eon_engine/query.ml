module Make (B : Query_backend.S with type 'perm world = 'perm World.t) = struct
  type 'perm query = {
    world    : 'perm B.world;
    required : string list;
    excludes : string list;
  }

  let from world = { world; required = []; excludes = [] }

  let having name query =
    { query with required = query.required @ [name] }

  let having_all names query =
    { query with required = query.required @ names }

  let not_having name query =
    { query with excludes = query.excludes @ [name] }

  let not_having_any names query =
    { query with excludes = query.excludes @ names }

  let iter f query =
    B.iter_entities query.world
      ~required:query.required
      ~excludes:query.excludes
      (fun entity -> f (View.make query.world entity))

  let count query =
    B.count query.world
      ~required:query.required
      ~excludes:query.excludes
end
