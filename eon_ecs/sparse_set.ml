type 'a t = {
    mutable sparse : int array;
    mutable dense  : int array;
    mutable values : 'a array;
    mutable count  : int;
  }

let create ?(capacity=128) () =
  {
    sparse = Array.make capacity (-1);
    dense  = Array.make capacity (-1);
    values = Array.make capacity (Obj.magic ());
    count  = 0;
  }

let capacity set = Array.length set.dense
let size set = set.count

let grow set =
  let old_cap = capacity set in
  let new_cap = max (old_cap * 2) 1 in
  let grow_int a =
    let b = Array.make new_cap (-1) in
    Array.blit a 0 b 0 old_cap;
    b
  in
  let grow_val a =
    let b = Array.make new_cap (Obj.magic ()) in
    Array.blit a 0 b 0 old_cap;
    b
  in
  set.sparse <- grow_int set.sparse;
  set.dense  <- grow_int set.dense;
  set.values <- grow_val set.values

let ensure_capacity set idx =
  while idx >= capacity set do
    grow set
  done

let contains set entity_id =
  let idx = Entity_id.index entity_id in
  idx < capacity set && set.sparse.(idx) <> -1

let get set entity_id =
  let idx = Entity_id.index entity_id in
  if idx < capacity set then
    let dense_idx = set.sparse.(idx) in
    if dense_idx <> -1 then Some set.values.(dense_idx) else None
  else
    None

let add set entity_id value =
  let idx = Entity_id.index entity_id in
  ensure_capacity set idx;
  (* if entity already present, just overwrite its value *)
  if set.sparse.(idx) <> -1 then
    set.values.(set.sparse.(idx)) <- value
  else (
    let dense_idx = set.count in
    set.sparse.(idx) <- dense_idx;
    set.dense.(dense_idx) <- idx;
    set.values.(dense_idx) <- value;
    set.count <- set.count + 1
  )

let set_value set entity_id value =
  let idx = Entity_id.index entity_id in
  ensure_capacity set idx;
  let dense_idx = set.sparse.(idx) in
  if dense_idx <> -1 then
    set.values.(dense_idx) <- value
  else
    add set entity_id value

let remove set entity_id =
  let idx = Entity_id.index entity_id in
  if idx < capacity set then
    let dense_idx = set.sparse.(idx) in
    if dense_idx <> -1 then (
      let last = set.count - 1 in
      let last_entity = set.dense.(last) in
      (* swap last element into this slot *)
      set.dense.(dense_idx) <- last_entity;
      set.values.(dense_idx) <- set.values.(last);
      set.sparse.(last_entity) <- dense_idx;
      (* clear sparse mapping *)
      set.sparse.(idx) <- -1;
      set.count <- last
    )

let iter f set =
  for i = 0 to set.count - 1 do
    f set.dense.(i) set.values.(i)
  done
