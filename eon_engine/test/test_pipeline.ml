(** Tests for Eon_engine.Pipeline parallel dispatch. *)

open Eon_engine

let setup_world () =
  World.create ()

let with_reset pipe f =
  Fun.protect ~finally:(fun () -> Pipeline.Default.reset pipe) f

let make_pipe phases systems =
  let base =
    List.fold_left
      (fun p ph -> Pipeline.Default.add_phase ph p)
      (Pipeline.Default.create ())
      phases
  in
  List.fold_left
    (fun p (ph, sys) -> Pipeline.Default.add_system ph sys p)
    base systems

(* ---- phase ordering ---- *)

let test_phase_ordering () =
  let w = setup_world () in
  let order = ref [] in
  let push s = order := !order @ [s] in
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `A
    |> Pipeline.Default.add_phase `B
    |> Pipeline.Default.before ~earlier:`A ~later:`B
    |> Pipeline.Default.add_system `A
         (System.Default.make (Exclusive (fun _rw _dt -> push "A")))
    |> Pipeline.Default.add_system `B
         (System.Default.make (Exclusive (fun _rw _dt -> push "B")))
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    ignore (Pipeline.Default.run pipe w 0.016);
    Alcotest.(check (list string)) "A runs before B" ["A"; "B"] !order)

let test_after_ordering () =
  let w = setup_world () in
  let order = ref [] in
  let push s = order := !order @ [s] in
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `A
    |> Pipeline.Default.add_phase `B
    |> Pipeline.Default.after ~later:`B ~earlier:`A
    |> Pipeline.Default.add_system `A
         (System.Default.make (Exclusive (fun _rw _dt -> push "A")))
    |> Pipeline.Default.add_system `B
         (System.Default.make (Exclusive (fun _rw _dt -> push "B")))
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    ignore (Pipeline.Default.run pipe w 0.016);
    Alcotest.(check (list string)) "after: A still before B" ["A"; "B"] !order)

(* ---- add_system raises on unregistered phase ---- *)

let test_add_system_unregistered_phase () =
  Alcotest.check_raises
    "unregistered phase raises Invalid_argument"
    (Invalid_argument "Pipeline.add_system: phase not registered")
    (fun () ->
       let pipe = Pipeline.Default.create () in
       ignore
         (Pipeline.Default.add_system `Ghost
            (System.Default.make (Exclusive (fun _ _ -> ()))) pipe))

(* ---- parallel systems run ---- *)

let test_parallel_runs () =
  let w = setup_world () in
  let count = ref 0 in
  let pipe =
    make_pipe [`Update]
      [`Update, System.Default.make (Parallel (fun _ro _dt -> incr count))]
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    ignore (Pipeline.Default.run pipe w 0.016);
    Alcotest.(check int) "parallel system ran once" 1 !count)

(* ---- exclusive systems run AFTER parallel in the same phase ---- *)

let test_exclusive_after_parallel () =
  let w = setup_world () in
  let order = ref [] in
  let push s = order := !order @ [s] in
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Update
    |> Pipeline.Default.add_system `Update
         (System.Default.make (Parallel  (fun _ro _dt -> push "parallel")))
    |> Pipeline.Default.add_system `Update
         (System.Default.make (Exclusive (fun _rw _dt -> push "exclusive")))
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    ignore (Pipeline.Default.run pipe w 0.016);
    Alcotest.(check (list string)) "parallel before exclusive"
      ["parallel"; "exclusive"] !order)

(* ---- exclusive system can mutate world (rw access) ---- *)

let test_exclusive_writes () =
  let w = setup_world () in
  let pipe =
    make_pipe [`Update]
      [`Update, System.Default.make
                  (Exclusive (fun rw _dt ->
                     ignore (World.create_entity rw)))]
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    let before = World.count_entities w in
    ignore (Pipeline.Default.run pipe w 0.016);
    let after = World.count_entities w in
    Alcotest.(check int) "entity created by exclusive system" (before + 1) after)

(* ---- run_by_filter skips non-matching kinds ---- *)

let test_run_by_filter () =
  let w = setup_world () in
  let fired = ref [] in
  let push s = fired := s :: !fired in
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Update
    |> Pipeline.Default.add_system `Update
         (System.Default.make ~kind:`Fixed    (Exclusive (fun _rw _dt -> push "fixed")))
    |> Pipeline.Default.add_system `Update
         (System.Default.make ~kind:`Variable (Exclusive (fun _rw _dt -> push "variable")))
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    ignore (Pipeline.Default.run_by_filter ~filter:(fun k -> k = `Fixed) pipe w 0.016);
    Alcotest.(check (list string)) "only fixed fires" ["fixed"] !fired)

(* ---- register_all wires bus handlers: on_command fires on drain ---- *)

let test_handler_dispatch () =
  let w = setup_world () in
  let fired = ref false in
  let pipe =
    make_pipe [`Update]
      [`Update, System.Default.make
                  ~on_command:(fun _rw () -> fired := true)
                  (Exclusive (fun _ _ -> ()))]
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    Single_bus.emit (Buses.Default.commands ()) ();
    Single_bus.drain (Buses.Default.commands ());
    Alcotest.(check bool) "on_command handler fired after drain" true !fired)

(* ---- multiple systems per phase all run ---- *)

let test_multiple_systems_per_phase () =
  let w = setup_world () in
  let count = ref 0 in
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Update
    |> Pipeline.Default.add_system `Update
         (System.Default.make (Exclusive (fun _rw _dt -> incr count)))
    |> Pipeline.Default.add_system `Update
         (System.Default.make (Exclusive (fun _rw _dt -> incr count)))
    |> Pipeline.Default.add_system `Update
         (System.Default.make (Exclusive (fun _rw _dt -> incr count)))
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    ignore (Pipeline.Default.run pipe w 0.016);
    Alcotest.(check int) "all three systems ran" 3 !count)

(* ---- phases returns the registered phases ---- *)

let test_phases_returns_all () =
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `A
    |> Pipeline.Default.add_phase `B
    |> Pipeline.Default.add_phase `C
  in
  Alcotest.(check int) "three phases" 3
    (List.length (Pipeline.Default.phases pipe))

(* ---- make_system (module Def) wires correctly ---- *)

module Counter_system = struct
  type signal  = unit
  type event   = unit
  type command = [ `Inc ]

  let count = ref 0

  let on_signal  _ _ = ()
  let on_event   _ _ = ()
  let on_command _rw = function `Inc -> incr count

  let update (_rw : World.rw World.t) _dt = ()
end

let test_make_exclusive_wires () =
  let w = setup_world () in
  Counter_system.count := 0;
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Update
    |> Pipeline.Default.add_system `Update (System.make_exclusive (module Counter_system))
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    Single_bus.emit (Buses.Default.commands ()) `Inc;
    Single_bus.drain (Buses.Default.commands ());
    Alcotest.(check int) "on_command fired via make_exclusive" 1 !Counter_system.count)

let test_make_parallel_update_runs () =
  let w = setup_world () in
  let ran = ref false in
  let module M = struct
    type signal  = unit
    type event   = unit
    type command = unit
    let on_signal  _ _ = ()
    let on_event   _ _ = ()
    let on_command _ _ = ()
    let update (_ro : World.ro World.t) _dt = ran := true
  end in
  let pipe =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Update
    |> Pipeline.Default.add_system `Update (System.make_parallel (module M))
  in
  Pipeline.Default.register_all pipe w;
  with_reset pipe (fun () ->
    ignore (Pipeline.Default.run pipe w 0.016);
    Alcotest.(check bool) "update ran via make_parallel" true !ran)

let tests =
  [
    ("phase ordering via before",          `Quick, test_phase_ordering);
    ("phase ordering via after",           `Quick, test_after_ordering);
    ("add_system on unregistered phase",   `Quick, test_add_system_unregistered_phase);
    ("parallel system runs",               `Quick, test_parallel_runs);
    ("exclusive runs after parallel",      `Quick, test_exclusive_after_parallel);
    ("exclusive system writes world",      `Quick, test_exclusive_writes);
    ("run_by_filter skips other kinds",    `Quick, test_run_by_filter);
    ("on_command fires after drain",       `Quick, test_handler_dispatch);
    ("multiple systems per phase all run", `Quick, test_multiple_systems_per_phase);
    ("phases returns all registered",      `Quick, test_phases_returns_all);
    ("make_exclusive wires on_command",    `Quick, test_make_exclusive_wires);
    ("make_parallel runs update",          `Quick, test_make_parallel_update_runs);
  ]
