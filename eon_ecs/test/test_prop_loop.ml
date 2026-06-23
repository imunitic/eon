module Loop = Eon_ecs__Loop

type event =
  | Collect
  | Tick of float
  | Drain
  | Render of float
  | Continue of float

let events : event list ref = ref []
let push e = events := e :: !events

type world_state = unit
let world () : world_state = ()

module Clock_stub = struct
  let now () = 0.0
end

module Test_progress = struct
  type 'phase t = unit
  type world = world_state

  let tick () ~world ~dt =
    push (Tick dt);
    world
end

module Test_renderer = struct
  type world = world_state
  type result = float

  let render _world ~dt =
    push (Render dt);
    dt
end

module Test_buses = struct
  let collect () = push Collect
  let drain   () = push Drain
end

module Test_loop = Loop.Make (Clock_stub) (Test_progress) (Test_renderer) (Test_buses)

type step_case = {
  last_ms : int;
  dt_ms : int;
  continue : bool;
}

let pp_step_case c =
  Printf.sprintf
    "{last_ms=%d; dt_ms=%d; continue=%b}"
    c.last_ms
    c.dt_ms
    c.continue

let gen_step_case =
  let open QCheck.Gen in
  map3
    (fun last_ms dt_ms continue -> { last_ms; dt_ms; continue })
    (int_bound 20_000)
    (int_bound 2_000)
    bool

let arb_step_case = QCheck.make ~print:pp_step_case gen_step_case

let approx_equal a b = Float.abs (a -. b) <= 1e-9

let events_match actual expected_dt =
  match actual with
  | [ Collect; Tick dt1; Drain; Render dt2; Continue result ] ->
      approx_equal dt1 expected_dt
      && approx_equal dt2 expected_dt
      && approx_equal result expected_dt
  | _ -> false

let prop_loop_step_sequence =
  let test_fn c =
    events := [];
    let w = world () in
    let last_time = float_of_int c.last_ms /. 1_000.0 in
    let dt = float_of_int c.dt_ms /. 1_000.0 in
    let now = last_time +. dt in
    let should_continue _world result =
      push (Continue result);
      c.continue
    in
    let _, next_last_time, render_result, continue =
      Test_loop.step
        ~progress:()
        ~world:w
        ~last_time
        ~now
        ~should_continue
    in
    continue = c.continue
    && approx_equal next_last_time now
    && approx_equal render_result dt
    && events_match (List.rev !events) dt
  in
  QCheck.Test.make
    ~name:"Loop.step sequencing collect->tick->drain->render->continue"
    ~count:1_000
    arb_step_case
    test_fn

let tests =
  [ QCheck_alcotest.to_alcotest prop_loop_step_sequence ]
