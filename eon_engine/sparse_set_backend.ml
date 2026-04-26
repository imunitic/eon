(** Sparse set backend for query execution.
    
    This is the default backend that wraps Eon_ecs.Query directly.
    Applies having/excludes filters as post-filters inside the callback.
*)

type world = Eon_ecs.World.t

(** Check if an entity has a component by name.
    Returns false if component is not registered or entity doesn't have it. *)
let entity_has_component world entity name =
  (* First check if component is registered to avoid exception from get_component *)
  match Eon_ecs.World.find_component world ~name with
  | None -> false  (* Component not registered *)
  | Some _ ->
      match Eon_ecs.World.get_component world entity ~name with
      | Some _ -> true
      | None -> false

(** Check if an entity has all components in the having list. *)
let has_all_having world entity = function
  | [] -> true
  | having -> List.for_all (entity_has_component world entity) having

(** Check if an entity has any component in the excludes list. *)
let has_any_excluded world entity = function
  | [] -> false
  | excludes -> List.exists (entity_has_component world entity) excludes

let iter1 world ~includes ~having ~excludes f =
  match includes with
  | [c1] ->
      Eon_ecs.Query.iter1 world c1 (fun entity v1 ->
        if has_all_having world entity having && not (has_any_excluded world entity excludes) then
          f entity v1)
  | _ -> invalid_arg "iter1 requires exactly 1 component in includes"

let iter2 world ~includes ~having ~excludes f =
  match includes with
  | [c1; c2] ->
      Eon_ecs.Query.iter2 world c1 c2 (fun entity v1 v2 ->
        if has_all_having world entity having && not (has_any_excluded world entity excludes) then
          f entity v1 v2)
  | _ -> invalid_arg "iter2 requires exactly 2 components in includes"

let iter3 world ~includes ~having ~excludes f =
  match includes with
  | [c1; c2; c3] ->
      Eon_ecs.Query.iter3 world c1 c2 c3 (fun entity v1 v2 v3 ->
        if has_all_having world entity having && not (has_any_excluded world entity excludes) then
          f entity v1 v2 v3)
  | _ -> invalid_arg "iter3 requires exactly 3 components in includes"

let iter4 world ~includes ~having ~excludes f =
  match includes with
  | [c1; c2; c3; c4] ->
      Eon_ecs.Query.iter4 world c1 c2 c3 c4 (fun entity v1 v2 v3 v4 ->
        if has_all_having world entity having && not (has_any_excluded world entity excludes) then
          f entity v1 v2 v3 v4)
  | _ -> invalid_arg "iter4 requires exactly 4 components in includes"

let count world ~includes ~having ~excludes =
  let count_ref = ref 0 in
  let count_fn1 _ _ = incr count_ref in
  let count_fn2 _ _ _ = incr count_ref in
  let count_fn3 _ _ _ _ = incr count_ref in
  let count_fn4 _ _ _ _ _ = incr count_ref in
  match includes with
  | [_] ->
      iter1 world ~includes ~having ~excludes count_fn1;
      !count_ref
  | [_; _] ->
      iter2 world ~includes ~having ~excludes count_fn2;
      !count_ref
  | [_; _; _] ->
      iter3 world ~includes ~having ~excludes count_fn3;
      !count_ref
  | [_; _; _; _] ->
      iter4 world ~includes ~having ~excludes count_fn4;
      !count_ref
  | _ -> invalid_arg "count requires 1-4 components in includes"

