(** Eon Engine — Query Builder
    
    Builder pattern for constructing and executing queries over entities.
    Uses a pluggable backend via functor application.
*)

module Make (B : Query_backend.S) = struct
  type query = {
    world    : B.world;
    includes : string list;  (* with_component/with_components — fetched, count toward arity *)
    having   : string list;  (* having/having_all — presence check only, no value, no arity *)
    excludes : string list;  (* not_having/not_having_any — must be absent *)
  }

  let from world = {
    world;
    includes = [];
    having = [];
    excludes = [];
  }

  let with_component name query = {
    query with
    includes = query.includes @ [name]
  }

  let with_components names query = {
    query with
    includes = query.includes @ names
  }

  let having name query = {
    query with
    having = query.having @ [name]
  }

  let having_all names query = {
    query with
    having = query.having @ names
  }

  let not_having name query = {
    query with
    excludes = query.excludes @ [name]
  }

  let not_having_any names query = {
    query with
    excludes = query.excludes @ names
  }

  let iter1 f query =
    if List.length query.includes <> 1 then
      invalid_arg "iter1 requires exactly 1 component (use with_component once)";
    B.iter1 query.world
      ~includes:query.includes
      ~having:query.having
      ~excludes:query.excludes
      f

  let iter2 f query =
    if List.length query.includes <> 2 then
      invalid_arg "iter2 requires exactly 2 components (use with_component twice)";
    B.iter2 query.world
      ~includes:query.includes
      ~having:query.having
      ~excludes:query.excludes
      f

  let iter3 f query =
    if List.length query.includes <> 3 then
      invalid_arg "iter3 requires exactly 3 components (use with_component three times)";
    B.iter3 query.world
      ~includes:query.includes
      ~having:query.having
      ~excludes:query.excludes
      f

  let iter4 f query =
    if List.length query.includes <> 4 then
      invalid_arg "iter4 requires exactly 4 components (use with_component four times)";
    B.iter4 query.world
      ~includes:query.includes
      ~having:query.having
      ~excludes:query.excludes
      f

  let count query =
    B.count query.world
      ~includes:query.includes
      ~having:query.having
      ~excludes:query.excludes
end
