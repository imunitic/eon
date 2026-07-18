(* Companion example for docs/eon_ecs chapter: Progress and Loop. *)

open Eon_ecs

module System   = Eon_ecs.System.Default
module Pipeline = Eon_ecs.Pipeline.Default
module Progress = Eon_ecs.Progress.Default
module Loop     = Eon_ecs.Loop.Default

let variable_count = `Variable_count
let fixed_count     = `Fixed_count

let counting_system key kind =
  System.make
    ~update:(fun world _dt ->
      match World.get_data world key with
      | Some n -> World.set_data world key (n + 1)
      | None   -> ())
    ~kind
    ()

(* Variable mode: exactly ONE tick per Progress.tick call, regardless
   of dt — the system just sees whatever dt was passed. *)
let variable_mode_example () =
  let world = World.create () in
  World.add_data world variable_count 0;
  let pipeline =
    Pipeline.create ()
    |> Pipeline.add_phase `Gameplay
    |> Pipeline.add_system `Gameplay (counting_system variable_count `Variable)
  in
  Pipeline.register_all pipeline world;
  let progress = Progress.create ~mode:Progress.Variable pipeline in

  let world = Progress.tick progress ~world ~dt:0.5 in
  match World.get_data world variable_count with
  | Some n -> assert (n = 1)
  | None -> assert false

(* Fixed mode: an accumulator. dt accumulates; the system runs once
   per full `step` worth of accumulated time, 0 to N times per
   Progress.tick call — a classic fixed-timestep catch-up loop. With
   step = 0.1 and a single tick of dt = 0.25, two full steps fit
   (0.25 / 0.1 = 2, with 0.05 left over for the next tick). *)
let fixed_mode_example () =
  let world = World.create () in
  World.add_data world fixed_count 0;
  let pipeline =
    Pipeline.create ()
    |> Pipeline.add_phase `Gameplay
    |> Pipeline.add_system `Gameplay (counting_system fixed_count `Fixed)
  in
  Pipeline.register_all pipeline world;
  let progress = Progress.create ~mode:(Progress.Fixed 0.1) pipeline in

  let world = Progress.tick progress ~world ~dt:0.25 in
  match World.get_data world fixed_count with
  | Some n -> assert (n = 2)
  | None -> assert false

(* Hybrid mode: the Fixed-style accumulator loop for `Fixed systems,
   PLUS one `Variable run per tick regardless of the accumulator — a
   world can have both kinds of systems and each sees the update
   cadence appropriate to it. *)
let hybrid_mode_example () =
  let world = World.create () in
  World.add_data world variable_count 0;
  World.add_data world fixed_count 0;
  let pipeline =
    Pipeline.create ()
    |> Pipeline.add_phase `Gameplay
    |> Pipeline.add_system `Gameplay (counting_system variable_count `Variable)
    |> Pipeline.add_system `Gameplay (counting_system fixed_count `Fixed)
  in
  Pipeline.register_all pipeline world;
  let progress = Progress.create ~mode:(Progress.Hybrid 0.1) pipeline in

  let world = Progress.tick progress ~world ~dt:0.25 in
  (match World.get_data world variable_count with
   | Some n -> assert (n = 1)   (* once, regardless of dt *)
   | None -> assert false);
  match World.get_data world fixed_count with
  | Some n -> assert (n = 2)    (* accumulator catch-up, same as Fixed above *)
  | None -> assert false

(* Loop.run repeatedly steps a progress controller until
   should_continue returns false — the predicate reads world state,
   so "run until N frames have ticked" is just a data-plane check. *)
let loop_run_until_example () =
  let world = World.create () in
  World.add_data world variable_count 0;
  let pipeline =
    Pipeline.create ()
    |> Pipeline.add_phase `Gameplay
    |> Pipeline.add_system `Gameplay (counting_system variable_count `Variable)
  in
  Pipeline.register_all pipeline world;
  let progress = Progress.create ~mode:Progress.Variable pipeline in

  let count_of world =
    match World.get_data world variable_count with
    | Some n -> n
    | None -> 0
  in
  let final_world =
    Loop.run
      ~progress
      ~world
      ~should_continue:(fun world -> count_of world < 5)
      ()
  in
  assert (count_of final_world = 5)

let () =
  variable_mode_example ();
  fixed_mode_example ();
  hybrid_mode_example ();
  loop_run_until_example ()
