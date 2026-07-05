open Eon_engine

(* ------------------------------------------------------------------ *)
(* Generators                                                          *)
(* ------------------------------------------------------------------ *)

type cmd = int

let gen_cmd   = QCheck.Gen.int
let arb_cmd   = QCheck.make gen_cmd
let arb_cmds  = QCheck.list arb_cmd

(* Collect all world commands from a stream into a list. *)
let world_to_list s =
  let acc = ref [] in
  Render_stream.iter_world s (fun c -> acc := c :: !acc);
  List.rev !acc

(* Collect all screen commands from a stream into a list. *)
let screen_to_list s =
  let acc = ref [] in
  Render_stream.iter_screen s (fun c -> acc := c :: !acc);
  List.rev !acc

(* ------------------------------------------------------------------ *)
(* World-space ordering invariants                                     *)
(* ------------------------------------------------------------------ *)

let prop_world_preserves_emission_order =
  QCheck.Test.make ~name:"iter_world preserves emission order" ~count:1_000
    arb_cmds
    (fun cmds ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_world s) cmds;
       world_to_list s = cmds)

let prop_world_count_matches_additions =
  QCheck.Test.make ~name:"iter_world count matches add_world calls" ~count:1_000
    arb_cmds
    (fun cmds ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_world s) cmds;
       List.length (world_to_list s) = List.length cmds)

(* ------------------------------------------------------------------ *)
(* Screen-space ordering invariants                                    *)
(* ------------------------------------------------------------------ *)

let prop_screen_preserves_emission_order =
  QCheck.Test.make ~name:"iter_screen preserves emission order" ~count:1_000
    arb_cmds
    (fun cmds ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_screen s) cmds;
       screen_to_list s = cmds)

(* ------------------------------------------------------------------ *)
(* Independence invariant                                              *)
(* ------------------------------------------------------------------ *)

let prop_screen_does_not_affect_world =
  QCheck.Test.make ~name:"add_screen does not affect world" ~count:1_000
    (QCheck.pair arb_cmds arb_cmds)
    (fun (world_cmds, screen_cmds) ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_world s) world_cmds;
       List.iter (Render_stream.add_screen s) screen_cmds;
       world_to_list s = world_cmds)

let prop_world_does_not_affect_screen =
  QCheck.Test.make ~name:"add_world does not affect screen" ~count:1_000
    (QCheck.pair arb_cmds arb_cmds)
    (fun (world_cmds, screen_cmds) ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_world s) world_cmds;
       List.iter (Render_stream.add_screen s) screen_cmds;
       screen_to_list s = screen_cmds)

(* ------------------------------------------------------------------ *)
(* Clear invariants                                                    *)
(* ------------------------------------------------------------------ *)

let prop_clear_empties_world =
  QCheck.Test.make ~name:"clear empties world" ~count:1_000
    arb_cmds
    (fun cmds ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_world s) cmds;
       Render_stream.clear s;
       world_to_list s = [])

let prop_clear_empties_screen =
  QCheck.Test.make ~name:"clear empties screen" ~count:1_000
    arb_cmds
    (fun cmds ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_screen s) cmds;
       Render_stream.clear s;
       screen_to_list s = [])

let prop_clear_then_refill_preserves_order =
  QCheck.Test.make ~name:"clear then refill preserves order" ~count:1_000
    (QCheck.pair arb_cmds arb_cmds)
    (fun (first, second) ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_world s) first;
       Render_stream.clear s;
       List.iter (Render_stream.add_world s) second;
       world_to_list s = second)

(* ------------------------------------------------------------------ *)
(* Screen-space ordering invariants (mirrors world-space)             *)
(* ------------------------------------------------------------------ *)

let prop_screen_count_matches_additions =
  QCheck.Test.make ~name:"iter_screen count matches add_screen calls" ~count:1_000
    arb_cmds
    (fun cmds ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_screen s) cmds;
       List.length (screen_to_list s) = List.length cmds)

let prop_screen_clear_then_refill_preserves_order =
  QCheck.Test.make ~name:"screen: clear then refill preserves order" ~count:1_000
    (QCheck.pair arb_cmds arb_cmds)
    (fun (first, second) ->
       let s = Render_stream.create () in
       List.iter (Render_stream.add_screen s) first;
       Render_stream.clear s;
       List.iter (Render_stream.add_screen s) second;
       screen_to_list s = second)

(* ------------------------------------------------------------------ *)
(* Render_stream_collector — phase ordering property                  *)
(* ------------------------------------------------------------------ *)

(* Generate N phases (0..n-1) forming a linear chain: 0 -> 1 -> ... -> n-1.
   Verify collect visits them in that order regardless of insertion order. *)

let prop_collector_linear_chain_order =
  QCheck.Test.make ~name:"collector: linear chain visited in declared order"
    ~count:500
    (QCheck.int_range 2 8)
    (fun n ->
       let world = World.readonly (World.create ()) in
       let c     = Render_stream_collector.create () in
       (* Add all phases without ordering first *)
       let c = List.fold_left
         (fun c i -> Render_stream_collector.add_phase i c)
         c (List.init n Fun.id) in
       (* Then declare linear chain: i runs after (i-1) *)
       let c = List.fold_left
         (fun c i -> Render_stream_collector.add_phase ~after:(i-1) i c)
         c (List.init (n-1) (fun i -> i + 1)) in
       (* Attach a collector to each phase that records its phase index *)
       let order = ref [] in
       let c = List.fold_left
         (fun c i ->
            Render_stream_collector.add_collector i
              (fun _w _s -> order := i :: !order) c)
         c (List.init n Fun.id) in
       let s = Render_stream.create () in
       Render_stream_collector.collect c world s;
       List.rev !order = List.init n Fun.id)

(* Same chain but phases inserted in reverse order — topo sort must still
   produce 0,1,...,n-1. *)
let prop_collector_reverse_insertion_same_order =
  QCheck.Test.make
    ~name:"collector: reverse insertion order still yields declared topo order"
    ~count:500
    (QCheck.int_range 2 8)
    (fun n ->
       let world = World.readonly (World.create ()) in
       let c     = Render_stream_collector.create () in
       (* Add phases in reverse: n-1, n-2, ..., 0 *)
       let c = List.fold_left
         (fun c i -> Render_stream_collector.add_phase i c)
         c (List.init n (fun i -> n - 1 - i)) in
       (* Declare linear chain 0->1->...->n-1 *)
       let c = List.fold_left
         (fun c i -> Render_stream_collector.add_phase ~after:(i-1) i c)
         c (List.init (n-1) (fun i -> i + 1)) in
       let order = ref [] in
       let c = List.fold_left
         (fun c i ->
            Render_stream_collector.add_collector i
              (fun _w _s -> order := i :: !order) c)
         c (List.init n Fun.id) in
       let s = Render_stream.create () in
       Render_stream_collector.collect c world s;
       List.rev !order = List.init n Fun.id)

(* Each collector runs exactly once per collect call. *)
let prop_collector_each_runs_exactly_once =
  QCheck.Test.make ~name:"collector: each collector runs exactly once" ~count:500
    (QCheck.int_range 1 6)
    (fun n ->
       let world  = World.readonly (World.create ()) in
       let counts = Array.make n 0 in
       let c      = Render_stream_collector.create () in
       let c      = Render_stream_collector.add_phase 0 c in
       let c      = List.fold_left
         (fun c i -> Render_stream_collector.add_phase ~after:(i-1) i c)
         c (List.init (n-1) (fun i -> i + 1)) in
       let c      = List.fold_left
         (fun c i ->
            Render_stream_collector.add_collector i
              (fun _w _s -> counts.(i) <- counts.(i) + 1) c)
         c (List.init n Fun.id) in
       let s = Render_stream.create () in
       Render_stream_collector.collect c world s;
       Array.for_all (fun count -> count = 1) counts)

(* ------------------------------------------------------------------ *)
(* Test list                                                           *)
(* ------------------------------------------------------------------ *)

let tests =
  List.map QCheck_alcotest.to_alcotest [
    prop_world_preserves_emission_order;
    prop_world_count_matches_additions;
    prop_screen_preserves_emission_order;
    prop_screen_count_matches_additions;
    prop_screen_does_not_affect_world;
    prop_world_does_not_affect_screen;
    prop_clear_empties_world;
    prop_clear_empties_screen;
    prop_clear_then_refill_preserves_order;
    prop_screen_clear_then_refill_preserves_order;
    prop_collector_linear_chain_order;
    prop_collector_reverse_insertion_same_order;
    prop_collector_each_runs_exactly_once;
  ]
