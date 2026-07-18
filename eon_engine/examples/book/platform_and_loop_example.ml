(* Companion example for docs/eon_engine chapter: Platform and loop. *)

open Eon_engine

let make_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

(* Buses: Signals/Commands (Single_bus) are same-frame (drain = collect);
   Events (Double_bus) are next-frame — see the previous chapter's
   reactive-handlers example for the exact drain-count semantics. This
   table is the reference; behaviour was already exercised end-to-end
   there, not repeated here. *)
let bus_table_is_documentation_only = ()

(* Input: the engine's job is minimal — poll the platform backend once per
   frame and store the result as a Raw_input_frame world resource. Game
   systems read it via Raw_input_frame.fetch/fetch_opt world (NOT `.get` —
   no such function exists; fetch raises Not_found before the first tick,
   fetch_opt returns None). Input_backend.Scripted replays a fixed frame
   list, for deterministic tests without a real window. *)
let input_example () =
  Input_backend.Scripted.set_frames
    [ { Raw_input_frame.empty with
        keys_pressed = Key.Set.singleton Key.Space };
      Raw_input_frame.empty ];

  let frame1 = Input_backend.Scripted.collect () in
  assert (Key.Set.mem Key.Space frame1.keys_pressed);

  let frame2 = Input_backend.Scripted.collect () in
  assert (Key.Set.is_empty frame2.keys_pressed);

  (* Once exhausted, Scripted returns Raw_input_frame.empty. *)
  let frame3 = Input_backend.Scripted.collect () in
  assert (frame3 = Raw_input_frame.empty);
  Input_backend.Scripted.shutdown ()

(* Platform: Platform.S bundles Input_backend/Audio_backend/Rendering_backend
   for Loop.Make. Platform.Headless (null everything) is for servers, CI, and
   scripted integration tests — exactly what this example uses. Game
   binaries supply their own concrete platform (e.g. a raylib platform). *)
let platform_example () =
  let module P = Platform.Headless in
  P.Input_backend.init ();
  let frame = P.Input_backend.collect () in
  assert (frame = Raw_input_frame.empty);
  P.Input_backend.shutdown ()

(* Loop: Loop.Make orchestrates one frame — collect input, collect buses,
   Progress.tick (runs the pipeline), drain buses, submit audio, render.
   Loop.Make's BUSES argument is Eon_ecs.Loop.BUSES (collect/drain : unit ->
   unit), not Eon_engine.Bus.S — Loop_buses satisfies it, closed over
   Buses.Default at module init time. *)
module Engine_progress = Progress.Make (Pipeline.Default)

module Engine_loop =
  Loop.Make
    (Eon_ecs.Clock.Mtime)
    (Engine_progress)
    (Platform.Headless)
    (Loop_buses)

let loop_example () =
  let world = make_world () in
  let e = World.create_entity world in
  World.add_component world e Components.Tag.component ({ value = "alive" } : Components.Tag.t);

  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Gameplay
  in
  Pipeline.Default.reset pipeline;
  Pipeline.Default.register_all pipeline world;
  let progress = Engine_progress.create ~mode:Engine_progress.Variable pipeline in

  let frames = ref 0 in
  let world =
    Engine_loop.run ~progress ~world
      ~should_continue:(fun _world ->
        incr frames;
        !frames <= 3)
      ()
  in
  assert (!frames = 4);
  assert (World.is_alive world e)

let () =
  input_example ();
  platform_example ();
  loop_example ();
  ignore bus_table_is_documentation_only
