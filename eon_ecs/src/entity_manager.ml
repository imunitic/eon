module Entity_id = Entity_id

type t = {
    mutable generations : int array; (* per-entity generation counters *)
    mutable free_list : int array; (* stack of reusable indices *)
    mutable free_top : int; (* index of next free slot in freelist *)
    mutable count : int; (* number of alive entities *)
  }

let create initial_capacity =
  {
    generations = Array.make initial_capacity 0;
    free_list = Array.make initial_capacity (-1);
    free_top = 0;
    count = 0;
  }

let capacity mgr = Array.length mgr.generations
let count mgr = mgr.count

let generation_at mgr index = mgr.generations.(index)

let grow mgr =
  let old_cap = capacity mgr in
  let new_cap = max 1 (old_cap * 2) in
  let new_gens = Array.make new_cap 0 in
  let new_free = Array.make new_cap (-1) in
  Array.blit mgr.generations 0 new_gens 0 old_cap;
  Array.blit mgr.free_list 0 new_free 0 mgr.free_top;
  mgr.generations <- new_gens;
  mgr.free_list <- new_free

let create_entity mgr : Entity_id.t =
  if mgr.free_top > 0 then (
    mgr.free_top <- mgr.free_top - 1;
    let idx = mgr.free_list.(mgr.free_top) in
    let gen = mgr.generations.(idx) in
    mgr.count <- mgr.count + 1;
    Entity_id.make idx gen
  ) else (
    if mgr.count >= capacity mgr then grow mgr;
    let idx = mgr.count in
    let gen = mgr.generations.(idx) in
    mgr.count <- mgr.count +1;
    Entity_id.make idx gen
  )

let destroy_entity mgr (e: Entity_id.t) =
  let idx = Entity_id.index e in
  if idx < capacity mgr then (
    mgr.generations.(idx) <- mgr.generations.(idx) + 1;
    if mgr.free_top >= capacity mgr then grow mgr;
    mgr.free_list.(mgr.free_top) <- idx;
    mgr.free_top <- mgr.free_top + 1;

    mgr.count <- mgr.count - 1;
  )

let is_alive mgr (e: Entity_id.t) =
  let idx = Entity_id.index e in
  idx < capacity mgr &&
  mgr.generations.(idx) = Entity_id.generation e

let add_component (_mgr: t) (entity: Entity_id.t)
      (comp : Component.any_component) (value : 'a) =
  Component.with_data comp (fun data ->
      Sparse_set.add data entity (Obj.magic value))

let set_component (_mgr: t) (entity: Entity_id.t)
      (comp : Component.any_component) (value : 'a) =
  Component.with_data comp (fun data ->
      Sparse_set.set_value data entity (Obj.magic value))

let get_component (_mgr: t) (entity: Entity_id.t)
      (comp : Component.any_component) =
  Component.with_data_result comp (fun data ->
      Sparse_set.get data entity)

let remove_component (_mgr: t) (entity: Entity_id.t)
      (comp: Component.any_component) =
  Component.with_data comp (fun data ->
      Sparse_set.remove data entity)
