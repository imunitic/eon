(** Property test: Cached_backend must never change query results, only cost.

    Model: two worlds (one queried through Cached_backend, one queried
    directly through Sparse_set_backend) receive the exact same sequence of
    add_component/remove_component/cache_signature/uncache_signature
    operations, applied to entities created in the same order in both --
    so entity (index, generation) pairs line up between the two worlds even
    though they're distinct [World.t] instances. After every single
    operation, both worlds' results for the same fixed query signature must
    agree. *)

open Eon_engine

module A = struct
  type t = int
  let component : t Components.t = Components.component "A"
end

module B = struct
  type t = int
  let component : t Components.t = Components.component "B"
end

let n_entities = 4

type op =
  | Add of int * bool (* entity index, true = A, false = B *)
  | Remove of int * bool
  | Cache
  | Uncache

let gen_op =
  QCheck.Gen.(
    oneof_weighted
      [ 4, map2 (fun e a -> Add (e, a)) (int_bound (n_entities - 1)) bool
      ; 3, map2 (fun e a -> Remove (e, a)) (int_bound (n_entities - 1)) bool
      ; 1, pure Cache
      ; 1, pure Uncache
      ])

let arb_ops = QCheck.list (QCheck.make gen_op)

let entity_key e = (Eon_ecs.Entity_id.index e, Eon_ecs.Entity_id.generation e)

let prop_cached_matches_direct =
  QCheck.Test.make ~name:"Cached_backend results always match Sparse_set_backend" ~count:1_000
    arb_ops
    (fun ops ->
       (* A fresh functor application per trial -- Cached_backend's cache is
          module-level state created once at instantiation, so reusing one
          module-level Q across all 1000 independent trial worlds would leak
          cache entries between unrelated worlds. *)
       let module QCached =
         Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default))
       in
       let module QDirect = Query.Make (Sparse_set_backend.Default) in
       let matches_cached world =
         let acc = ref [] in
         QCached.from world |> QCached.having A.component |> QCached.having B.component
         |> QCached.iter (fun v -> acc := entity_key (View.entity v) :: !acc);
         List.sort compare !acc
       in
       let matches_direct world =
         let acc = ref [] in
         QDirect.from world |> QDirect.having A.component |> QDirect.having B.component
         |> QDirect.iter (fun v -> acc := entity_key (View.entity v) :: !acc);
         List.sort compare !acc
       in
       let w_cached = World.create () in
       let w_direct = World.create () in
       ignore (World.register w_cached A.component);
       ignore (World.register w_cached B.component);
       ignore (World.register w_direct A.component);
       ignore (World.register w_direct B.component);
       let e_cached = Array.init n_entities (fun _ -> World.create_entity w_cached) in
       let e_direct = Array.init n_entities (fun _ -> World.create_entity w_direct) in
       List.for_all
         (fun op ->
            (match op with
             | Add (i, is_a) ->
               let comp = if is_a then A.component else B.component in
               World.add_component w_cached e_cached.(i) comp 0;
               World.add_component w_direct e_direct.(i) comp 0
             | Remove (i, is_a) ->
               let comp = if is_a then A.component else B.component in
               World.remove_component w_cached e_cached.(i) comp;
               World.remove_component w_direct e_direct.(i) comp
             | Cache ->
               (* Only meaningful on the cached side -- direct comparison
                  target has no caching concept at all. *)
               QCached.cache_signature ~required:["A"; "B"] ~excludes:[]
             | Uncache ->
               QCached.uncache_signature ~required:["A"; "B"] ~excludes:[]);
            matches_cached w_cached = matches_direct w_direct)
         ops)

let tests = List.map QCheck_alcotest.to_alcotest [ prop_cached_matches_direct ]
