open Alcotest

module P = Eon_ecs__Progress
module World = Eon_ecs__World
module Pipeline = Eon_ecs__Pipeline

module DummyPipeline : Pipeline.S = struct
  type 'phase t = unit
  type ('s, 'e, 'c) system_t = unit

  let create () = ()

  let add_phase _ _ = ()
  let before ~earlier:_ ~later:_ _ = ()
  let after ~later:_ ~earlier:_ _ = ()
  let add_system _ _ _ = ()
  let register_all _ _ = ()
  let phases _ = []

  (* Simulate running systems by incrementing tick_count *)
  let run _ world _dt =
    let open World in
    add_data world "tick_count"
      (1 + Option.value ~default:0 (get_data world "tick_count"));
    world

  (* Match the new run_by_filter signature used by Progress *)
  let run_by_filter ~filter:_ _ world _dt =
    let open World in
    add_data world "tick_count"
      (1 + Option.value ~default:0 (get_data world "tick_count"));
    world
end

module Progress = P.Make(DummyPipeline)

let test_variable () =
  let world = World.create () in
  let pipeline = DummyPipeline.create () in
  let progress = Progress.create ~mode:Variable pipeline in
  let world = Progress.tick progress ~world ~dt:0.016 in
  check int "tick_count" 1 (Option.get (World.get_data world "tick_count"))

let test_fixed () =
  let world = World.create () in
  let pipeline = DummyPipeline.create () in
  let progress = Progress.create ~mode:(Fixed 0.01) pipeline in
  let world = Progress.tick progress ~world ~dt:0.03 in
  check int "fixed steps" 3 (Option.get (World.get_data world "tick_count"))

let test_hybrid () =
  let world = World.create () in
  let pipeline = DummyPipeline.create () in
  let progress = Progress.create ~mode:(Hybrid 0.01) pipeline in
  let world = Progress.tick progress ~world ~dt:0.03 in
  check int "hybrid steps"
    4 (* 3 fixed + 1 variable pass *)
    (Option.get (World.get_data world "tick_count"))

let tests =
  [
    test_case "Variable timestep" `Quick test_variable;
    test_case "Fixed timestep accumulator" `Quick test_fixed;
    test_case "Hybrid timestep combined" `Quick test_hybrid;
  ]
