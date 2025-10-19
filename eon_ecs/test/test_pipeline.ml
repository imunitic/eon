open Eon_ecs
open Alcotest

(* -------------------------------------------------------------------------- *)
(* 🔹 Setup *)
(* -------------------------------------------------------------------------- *)

module Single_bus = Eon_ecs__.Single_bus
module Double_bus = Eon_ecs__.Double_bus
module System = Eon_ecs__System
module Sys = System.Make(Single_bus)(Double_bus)(Single_bus)
module Pipeline = Eon_ecs__.Pipeline.Make(Sys)

(* -------------------------------------------------------------------------- *)
(* 🔹 Test 1: add_phase *)
(* -------------------------------------------------------------------------- *)

let test_add_phase () =
  let p =
    Pipeline.create ()
    |> Pipeline.add_phase `Init
    |> Pipeline.add_phase `Update
    |> Pipeline.add_phase `Render
  in
  let phases = Pipeline.phases p in
  check int "phase count" 3 (List.length phases)

(* -------------------------------------------------------------------------- *)
(* 🔹 Test 2: before / after relationships *)
(* -------------------------------------------------------------------------- *)

let test_before_after () =
  let p =
    Pipeline.create ()
    |> Pipeline.add_phase `A
    |> Pipeline.add_phase `B
    |> Pipeline.add_phase `C
    |> Pipeline.before ~earlier:`A ~later:`B
    |> Pipeline.before ~earlier:`B ~later:`C
  in
  let order = Pipeline.phases p in
  let names = List.map (function `A -> "A" | `B -> "B" | `C -> "C") order in
  check (list string) "topological order" [ "A"; "B"; "C" ] names

(* -------------------------------------------------------------------------- *)
(* 🔹 Test 3: system registration and run order *)
(* -------------------------------------------------------------------------- *)

let test_run_order () =
  let logs = ref [] in
  let record msg = logs := !logs @ [ msg ] in

  let mk_sys name =
    Sys.make_core
      ~register:(fun _ -> record ("register:" ^ name))
      ~update:(fun _ _ -> record ("update:" ^ name))
      ()
  in

  let sys_a = Sys.from_core (mk_sys "A")
  and sys_b = Sys.from_core (mk_sys "B")
  and sys_c = Sys.from_core (mk_sys "C") in

  let p =
    Pipeline.create ()
    |> Pipeline.add_phase `A
    |> Pipeline.add_phase `B
    |> Pipeline.add_phase `C
    |> Pipeline.before ~earlier:`A ~later:`B
    |> Pipeline.before ~earlier:`B ~later:`C
    |> Pipeline.add_system `A sys_a
    |> Pipeline.add_system `B sys_b
    |> Pipeline.add_system `C sys_c
  in

  let world = World.create () in
  Pipeline.register_all p world;
  ignore (Pipeline.run p world 0.016);

  check (list string) "execution order"
    [ "register:A"; "register:B"; "register:C";
      "update:A"; "update:B"; "update:C" ]
    !logs

(* -------------------------------------------------------------------------- *)
(* 🔹 Test 4: cycle detection *)
(* -------------------------------------------------------------------------- *)

let test_cycle_detection () =
  let p =
    Pipeline.create ()
    |> Pipeline.add_phase `A
    |> Pipeline.add_phase `B
    |> Pipeline.before ~earlier:`A ~later:`B
    |> Pipeline.before ~earlier:`B ~later:`A
  in
  let raised =
    try ignore (Pipeline.phases p); false
    with Invalid_argument _ -> true
  in
  check bool "cycle detected" true raised

(* -------------------------------------------------------------------------- *)
(* 🔹 Test 5: run_filtered behavior *)
(* -------------------------------------------------------------------------- *)

let test_run_filtered () =
  let logs = ref [] in
  let record msg = logs := !logs @ [ msg ] in

  (* Helper that makes a system with a given kind *)
  let mk_sys name kind =
    Sys.make_core
      ~register:(fun _ -> record ("register:" ^ name))
      ~update:(fun _ _ -> record ("update:" ^ name))
      ()
    |> Sys.from_core
    |> fun sys -> { sys with kind }  (* mark kind manually *)
  in

  (* Systems of different kinds *)
  let sys_fixed = mk_sys "FixedSys" `Fixed
  and sys_var = mk_sys "VariableSys" `Variable in

  let p =
    Pipeline.create ()
    |> Pipeline.add_phase `Main
    |> Pipeline.add_system `Main sys_fixed
    |> Pipeline.add_system `Main sys_var
  in

  let world = World.create () in
  Pipeline.register_all p world;

  ignore (Pipeline.run_filtered ~kind:`Fixed p world 0.016);
  check (list string) "only fixed systems run"
    [ "register:FixedSys"; "register:VariableSys"; "update:FixedSys" ]
    !logs;

  logs := [];

  ignore (Pipeline.run_filtered ~kind:`Variable p world 0.016);
  check (list string) "only variable systems run"
    [ "update:VariableSys" ]
    !logs

(* -------------------------------------------------------------------------- *)
(* 🔹 Collect tests *)
(* -------------------------------------------------------------------------- *)

let tests = [
  test_case "add phase"        `Quick test_add_phase;
  test_case "before/after"     `Quick test_before_after;
  test_case "run order"        `Quick test_run_order;
  test_case "cycle detection"  `Quick test_cycle_detection;
  test_case "run_filtered"     `Quick test_run_filtered;
]
