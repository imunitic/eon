module Make (W : World.S) : Query_backend.S with type world = W.t = struct
  type world = W.t

  (* Entity-only iteration: keeps entities that pass all three filter lists. *)
  let iter_entities world ~includes ~having ~excludes f =
    let required = includes @ having in
    W.iter_entities world required (fun entity ->
      if not (List.exists (W.has_component world entity) excludes) then
        f entity)

  let iter1 (type a) world ~includes ~having ~excludes
      (f : Eon_ecs.Entity_id.t -> a -> unit) =
    match includes with
    | [c1] ->
        let c1 : a Component_descriptor.t = c1 in
        iter_entities world ~includes ~having ~excludes (fun entity ->
          match W.get_component world entity c1 with
          | Some v1 -> f entity v1
          | None -> ())
    | _ -> invalid_arg "iter1 requires exactly 1 component in includes"

  let iter2 (type a b) world ~includes ~having ~excludes
      (f : Eon_ecs.Entity_id.t -> a -> b -> unit) =
    match includes with
    | [c1; c2] ->
        let c1 : a Component_descriptor.t = c1 in
        let c2 : b Component_descriptor.t = c2 in
        iter_entities world ~includes ~having ~excludes (fun entity ->
          match W.get_component world entity c1,
                W.get_component world entity c2 with
          | Some v1, Some v2 -> f entity v1 v2
          | _ -> ())
    | _ -> invalid_arg "iter2 requires exactly 2 components in includes"

  let iter3 (type a b c) world ~includes ~having ~excludes
      (f : Eon_ecs.Entity_id.t -> a -> b -> c -> unit) =
    match includes with
    | [c1; c2; c3] ->
        let c1 : a Component_descriptor.t = c1 in
        let c2 : b Component_descriptor.t = c2 in
        let c3 : c Component_descriptor.t = c3 in
        iter_entities world ~includes ~having ~excludes (fun entity ->
          match W.get_component world entity c1,
                W.get_component world entity c2,
                W.get_component world entity c3 with
          | Some v1, Some v2, Some v3 -> f entity v1 v2 v3
          | _ -> ())
    | _ -> invalid_arg "iter3 requires exactly 3 components in includes"

  let iter4 (type a b c d) world ~includes ~having ~excludes
      (f : Eon_ecs.Entity_id.t -> a -> b -> c -> d -> unit) =
    match includes with
    | [c1; c2; c3; c4] ->
        let c1 : a Component_descriptor.t = c1 in
        let c2 : b Component_descriptor.t = c2 in
        let c3 : c Component_descriptor.t = c3 in
        let c4 : d Component_descriptor.t = c4 in
        iter_entities world ~includes ~having ~excludes (fun entity ->
          match W.get_component world entity c1,
                W.get_component world entity c2,
                W.get_component world entity c3,
                W.get_component world entity c4 with
          | Some v1, Some v2, Some v3, Some v4 -> f entity v1 v2 v3 v4
          | _ -> ())
    | _ -> invalid_arg "iter4 requires exactly 4 components in includes"

  let count world ~includes ~having ~excludes =
    let n = ref 0 in
    iter_entities world ~includes ~having ~excludes (fun _ -> incr n);
    !n
end

module Default = Make (World)
