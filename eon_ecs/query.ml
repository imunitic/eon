(** Eon ECS — Query
    ------------------------------------------------------------------
    Efficient iteration over entities that share one or more components.
    Uses Sparse_set intersection via Component_registry.
    ------------------------------------------------------------------ *)

(** Choose the smallest Sparse_set to minimize iterations. *)
let smallest sets =
  List.fold_left
    (fun acc set ->
      match acc with
      | None -> Some set
      | Some s when Sparse_set.size set < Sparse_set.size s -> Some set
      | _ -> acc)
    None
    sets

(** Helper to get component storage by name. *)
let storage world name =
  match World.find_component world ~name with
  | Some c -> Some c.Component.data
  | None -> None

(** Helper to get the generation of an entity id *)
let eid_of world id =
  Entity_id.make id @@ World.generation_at world id

(** Iterate over entities with one component. *)
let iter1 world c1 f =
  Option.iter
    (fun s1 ->
      Sparse_set.iter
        (fun id v1 -> f (eid_of world id) v1)
        s1)
    (storage world c1)

(** Iterate over entities with two components. *)
let iter2 world c1 c2 f =
  match storage world c1, storage world c2 with
  | Some s1, Some s2 ->
     let base, _ =
       if Sparse_set.size s1 < Sparse_set.size s2 then (s1, s2)
       else (s2, s1)
     in
     Sparse_set.iter
       (fun id _ ->
         let eid = eid_of world id in
         match Sparse_set.get s1 eid, Sparse_set.get s2 eid with
         | Some v1, Some v2 -> f eid v1 v2
         | _ -> ())
       base
  | _ -> ()

(** Iterate over entities with three components. *)
let iter3 world c1 c2 c3 f =
  match storage world c1, storage world c2, storage world c3 with
  | Some s1, Some s2, Some s3 ->
     let base =
       smallest [ s1; s2; s3 ] |> Option.get
     in
     Sparse_set.iter
       (fun id _ ->
         let eid = eid_of world id in
         if Sparse_set.contains s1 eid
            && Sparse_set.contains s2 eid
            && Sparse_set.contains s3 eid
         then
           match Sparse_set.get s1 eid,
                 Sparse_set.get s2 eid,
                 Sparse_set.get s3 eid with
           | Some v1, Some v2, Some v3 -> f eid v1 v2 v3
           | _ -> ())
       base
  | _ -> ()

(** Iterate over entities with four components *)
let iter4 world c1 c2 c3 c4 f =
  match storage world c1, storage world c2, storage world c3, storage world c4 with
  | Some s1, Some s2, Some s3, Some s4 ->
     let base = smallest [ s1; s2; s3; s4 ] |> Option.get in
     Sparse_set.iter
       (fun id _ ->
         let eid = eid_of world id in
         if Sparse_set.contains s1 eid
            && Sparse_set.contains s2 eid
            && Sparse_set.contains s3 eid
            && Sparse_set.contains s4 eid
         then
           match Sparse_set.get s1 eid,
                 Sparse_set.get s2 eid,
                 Sparse_set.get s3 eid,
                 Sparse_set.get s4 eid with
           | Some v1, Some v2, Some v3, Some v4 -> f eid v1 v2 v3 v4
           | _ -> ())
       base
  | _ -> ()

(** Count how many entities match the given components. *)
let count world names =
  let sets =
    names
    |> List.filter_map (storage world)
  in
  match smallest sets with
  | None -> 0
  | Some base ->
     let others = List.filter (fun s -> s != base) sets in
     let count = ref 0 in
     Sparse_set.iter
       (fun id _ ->
          let eid = eid_of world id in
         if List.for_all (fun s -> Sparse_set.contains s eid) others
         then incr count)
       base;
     !count
