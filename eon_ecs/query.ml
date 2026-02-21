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
let iter2 (type a b) world c1 c2 (f : Entity_id.t -> a -> b -> unit) : unit =
  match storage world c1, storage world c2 with
  | Some s1, Some s2 ->
     let s1 = (Obj.magic s1 : a Sparse_set.t) in
     let s2 = (Obj.magic s2 : b Sparse_set.t) in
     let visit id =
       let eid = eid_of world id in
       match Sparse_set.get s1 eid, Sparse_set.get s2 eid with
       | Some v1, Some v2 -> f eid v1 v2
       | _ -> ()
     in
     if Sparse_set.size s1 < Sparse_set.size s2 then
       Sparse_set.iter (fun id _ -> visit id) s1
     else
       Sparse_set.iter (fun id _ -> visit id) s2
  | _ -> ()

(** Iterate over entities with three components. *)
let iter3 (type a b c) world c1 c2 c3 (f : Entity_id.t -> a -> b -> c -> unit) : unit =
  match storage world c1, storage world c2, storage world c3 with
  | Some s1, Some s2, Some s3 ->
     let s1 = (Obj.magic s1 : a Sparse_set.t) in
     let s2 = (Obj.magic s2 : b Sparse_set.t) in
     let s3 = (Obj.magic s3 : c Sparse_set.t) in
     let visit id =
       let eid = eid_of world id in
       if Sparse_set.contains s1 eid
          && Sparse_set.contains s2 eid
          && Sparse_set.contains s3 eid
       then
         match Sparse_set.get s1 eid,
               Sparse_set.get s2 eid,
               Sparse_set.get s3 eid with
         | Some v1, Some v2, Some v3 -> f eid v1 v2 v3
         | _ -> ()
     in
     let n1 = Sparse_set.size s1
     and n2 = Sparse_set.size s2
     and n3 = Sparse_set.size s3 in
     if n1 <= n2 && n1 <= n3 then
       Sparse_set.iter (fun id _ -> visit id) s1
     else if n2 <= n1 && n2 <= n3 then
       Sparse_set.iter (fun id _ -> visit id) s2
     else
       Sparse_set.iter (fun id _ -> visit id) s3
  | _ -> ()

(** Iterate over entities with four components *)
let iter4 (type a b c d) world c1 c2 c3 c4 (f : Entity_id.t -> a -> b -> c -> d -> unit) : unit =
  match storage world c1, storage world c2, storage world c3, storage world c4 with
  | Some s1, Some s2, Some s3, Some s4 ->
     let s1 = (Obj.magic s1 : a Sparse_set.t) in
     let s2 = (Obj.magic s2 : b Sparse_set.t) in
     let s3 = (Obj.magic s3 : c Sparse_set.t) in
     let s4 = (Obj.magic s4 : d Sparse_set.t) in
     let visit id =
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
         | _ -> ()
     in
     let n1 = Sparse_set.size s1
     and n2 = Sparse_set.size s2
     and n3 = Sparse_set.size s3
     and n4 = Sparse_set.size s4 in
     if n1 <= n2 && n1 <= n3 && n1 <= n4 then
       Sparse_set.iter (fun id _ -> visit id) s1
     else if n2 <= n1 && n2 <= n3 && n2 <= n4 then
       Sparse_set.iter (fun id _ -> visit id) s2
     else if n3 <= n1 && n3 <= n2 && n3 <= n4 then
       Sparse_set.iter (fun id _ -> visit id) s3
     else
       Sparse_set.iter (fun id _ -> visit id) s4
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
