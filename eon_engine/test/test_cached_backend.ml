(** Tests for Eon Engine Cached_backend *)

open Eon_engine

module A = struct
  type t = int
  let component : t Components.t = Components.component "A"
end

module B = struct
  type t = int
  let component : t Components.t = Components.component "B"
end

module C = struct
  type t = int
  let component : t Components.t = Components.component "C"
end

let create_world () =
  let world = World.create () in
  ignore (World.register world A.component);
  ignore (World.register world B.component);
  ignore (World.register world C.component);
  world

(* A fresh [Q] instance (a fresh functor application, hence a fresh cache
   table) per test -- Cached_backend's cache is module-level state created
   once at instantiation, so sharing one [Q] across tests would leak cache
   entries between them. *)

let test_uncached_signature_delegates_directly () =
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  World.add_component world e1 A.component 1;
  (* Never called Q.cache_signature -- behaves exactly like the wrapped
     Sparse_set_backend. *)
  let seen = ref [] in
  Q.from world |> Q.having A.component |> Q.iter (fun v -> seen := View.entity v :: !seen);
  Alcotest.(check int) "uncached signature still finds match" 1 (List.length !seen);
  Alcotest.(check bool) "e1 found" true (List.mem e1 !seen)

let test_cached_signature_returns_correct_results () =
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  let e2 = World.create_entity world in
  World.add_component world e1 A.component 1;
  World.add_component world e1 B.component 1;
  World.add_component world e2 A.component 1;
  Q.cache_signature ~required:["A"; "B"] ~excludes:[];
  let seen = ref [] in
  Q.from world |> Q.having A.component |> Q.having B.component
  |> Q.iter (fun v -> seen := View.entity v :: !seen);
  Alcotest.(check int) "only e1 has both A and B" 1 (List.length !seen);
  Alcotest.(check bool) "e1 found" true (List.mem e1 !seen)

let test_cache_survives_unrelated_mutation () =
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  World.add_component world e1 A.component 1;
  World.add_component world e1 B.component 1;
  Q.cache_signature ~required:["A"; "B"] ~excludes:[];
  let seen1 = ref [] in
  Q.from world |> Q.having A.component |> Q.having B.component
  |> Q.iter (fun v -> seen1 := View.entity v :: !seen1);
  Alcotest.(check int) "initial fill: one match" 1 (List.length !seen1);
  (* C is unrelated to the cached signature -- must not force a refill or
     change the result. *)
  let e2 = World.create_entity world in
  World.add_component world e2 C.component 1;
  let seen2 = ref [] in
  Q.from world |> Q.having A.component |> Q.having B.component
  |> Q.iter (fun v -> seen2 := View.entity v :: !seen2);
  Alcotest.(check int) "unrelated mutation: still one match" 1 (List.length !seen2);
  Alcotest.(check bool) "still e1" true (List.mem e1 !seen2)

let test_staleness_on_add_component () =
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  World.add_component world e1 A.component 1;
  World.add_component world e1 B.component 1;
  Q.cache_signature ~required:["A"; "B"] ~excludes:[];
  let n1 = Q.from world |> Q.having A.component |> Q.having B.component |> Q.count in
  Alcotest.(check int) "before add: one match" 1 n1;
  let e2 = World.create_entity world in
  World.add_component world e2 A.component 1;
  World.add_component world e2 B.component 1;
  let n2 = Q.from world |> Q.having A.component |> Q.having B.component |> Q.count in
  Alcotest.(check int) "after add: refilled to two matches" 2 n2

let test_staleness_on_remove_component () =
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  World.add_component world e1 A.component 1;
  World.add_component world e1 B.component 1;
  Q.cache_signature ~required:["A"; "B"] ~excludes:[];
  let n1 = Q.from world |> Q.having A.component |> Q.having B.component |> Q.count in
  Alcotest.(check int) "before remove: one match" 1 n1;
  World.remove_component world e1 B.component;
  let n2 = Q.from world |> Q.having A.component |> Q.having B.component |> Q.count in
  Alcotest.(check int) "after remove: refilled to zero matches" 0 n2

let test_same_tick_swap () =
  (* A length/count-based staleness proxy would see the match count return
     to 1 and wrongly conclude the cached entry is still valid, serving the
     stale entity e1 instead of the new e2. The generation counter must
     catch this since both the remove and the add bump it. *)
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  World.add_component world e1 A.component 1;
  World.add_component world e1 B.component 1;
  Q.cache_signature ~required:["A"; "B"] ~excludes:[];
  let seen1 = ref [] in
  Q.from world |> Q.having A.component |> Q.having B.component
  |> Q.iter (fun v -> seen1 := View.entity v :: !seen1);
  Alcotest.(check bool) "initially e1" true (List.mem e1 !seen1);
  (* Same-tick swap: remove e1's B, add a fresh e2 with both A and B. *)
  World.remove_component world e1 B.component;
  let e2 = World.create_entity world in
  World.add_component world e2 A.component 1;
  World.add_component world e2 B.component 1;
  let seen2 = ref [] in
  Q.from world |> Q.having A.component |> Q.having B.component
  |> Q.iter (fun v -> seen2 := View.entity v :: !seen2);
  Alcotest.(check int) "still exactly one match" 1 (List.length !seen2);
  Alcotest.(check bool) "now e2, not stale e1" true (List.mem e2 !seen2);
  Alcotest.(check bool) "e1 no longer present" false (List.mem e1 !seen2)

let test_uncache_signature () =
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  World.add_component world e1 A.component 1;
  Q.cache_signature ~required:["A"] ~excludes:[];
  let n1 = Q.from world |> Q.having A.component |> Q.count in
  Alcotest.(check int) "cached: one match" 1 n1;
  Q.uncache_signature ~required:["A"] ~excludes:[];
  let e2 = World.create_entity world in
  World.add_component world e2 A.component 1;
  (* No longer cached -- delegates straight through, sees e2 immediately
     with no explicit refill step needed. *)
  let n2 = Q.from world |> Q.having A.component |> Q.count in
  Alcotest.(check int) "uncached: sees both immediately" 2 n2

let test_excludes_change_invalidates () =
  let module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default)) in
  let world = create_world () in
  let e1 = World.create_entity world in
  World.add_component world e1 A.component 1;
  Q.cache_signature ~required:["A"] ~excludes:["C"];
  let n1 =
    Q.from world |> Q.having A.component |> Q.not_having C.component |> Q.count
  in
  Alcotest.(check int) "before: e1 has no C, matches" 1 n1;
  (* C is in [excludes], not [required] -- its membership change must still
     invalidate the cache. *)
  World.add_component world e1 C.component 1;
  let n2 =
    Q.from world |> Q.having A.component |> Q.not_having C.component |> Q.count
  in
  Alcotest.(check int) "after: e1 now has C, excluded" 0 n2

let tests = [
  Alcotest.test_case "uncached signature delegates directly" `Quick
    test_uncached_signature_delegates_directly;
  Alcotest.test_case "cached signature returns correct results" `Quick
    test_cached_signature_returns_correct_results;
  Alcotest.test_case "cache survives unrelated mutation" `Quick
    test_cache_survives_unrelated_mutation;
  Alcotest.test_case "staleness on add_component" `Quick
    test_staleness_on_add_component;
  Alcotest.test_case "staleness on remove_component" `Quick
    test_staleness_on_remove_component;
  Alcotest.test_case "same-tick swap" `Quick test_same_tick_swap;
  Alcotest.test_case "uncache_signature" `Quick test_uncache_signature;
  Alcotest.test_case "excludes component change invalidates" `Quick
    test_excludes_change_invalidates;
]
