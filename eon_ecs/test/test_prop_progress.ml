module Progress_core = Eon_ecs__Progress
module World = Eon_ecs__World
module Pipeline_sig = Eon_ecs__Pipeline
module Kind = Eon_ecs__System.Base_kind

type call = Kind.kind * float

module DummyPipeline : Pipeline_sig.S with type kind = Kind.kind and type world = World.t = struct
  type 'phase t = unit
  type ('s, 'e, 'c) system_t = unit
  type kind = Kind.kind
  type world = World.t

  let create () = ()
  let add_phase _ _ = ()
  let before ~earlier:_ ~later:_ _ = ()
  let after ~later:_ ~earlier:_ _ = ()
  let add_system _ _ _ = ()
  let register_all _ _ = ()
  let reset _ = ()
  let phases _ = []

  let run _ world _dt = world

  let run_by_filter ~filter _ world dt =
    let kind =
      if filter `Fixed then `Fixed
      else if filter `Variable then `Variable
      else invalid_arg "DummyPipeline.run_by_filter: unknown kind filter"
    in
    let calls = Option.value ~default:[] (World.get_data world `Progress_calls : call list option) in
    World.add_data world `Progress_calls (calls @ [ (kind, dt) ]);
    world
end

module Progress = Progress_core.Make_with_kind (Kind) (DummyPipeline)

let epsilon = 1e-8

let fixed_calls_for_tick ~step ~dt ~accumulator =
  let acc = ref (accumulator +. dt) in
  let calls = ref [] in
  while !acc +. epsilon >= step do
    calls := (`Fixed, step) :: !calls;
    acc := !acc -. step
  done;
  (List.rev !calls, !acc)

let simulate_variable dts =
  List.map (fun dt -> (`Variable, dt)) dts

let simulate_fixed ~step dts =
  let acc = ref 0.0 in
  let all = ref [] in
  List.iter
    (fun dt ->
      let calls, acc' = fixed_calls_for_tick ~step ~dt ~accumulator:!acc in
      acc := acc';
      all := !all @ calls)
    dts;
  !all

let simulate_hybrid ~step dts =
  let acc = ref 0.0 in
  let all = ref [] in
  List.iter
    (fun dt ->
      let fixed_calls, acc' = fixed_calls_for_tick ~step ~dt ~accumulator:!acc in
      acc := acc';
      all := !all @ fixed_calls @ [ (`Variable, dt) ])
    dts;
  !all

let approx_equal a b = Float.abs (a -. b) <= 1e-9

let calls_equal actual expected =
  let rec loop a e =
    match (a, e) with
    | [], [] -> true
    | (ka, da) :: ta, (ke, de) :: te ->
        ka = ke && approx_equal da de && loop ta te
    | _ -> false
  in
  loop actual expected

let gen_dt =
  QCheck.Gen.map (fun ms -> float_of_int ms /. 1_000.0) (QCheck.Gen.int_bound 50)

let arb_dts =
  QCheck.make
    ~print:(QCheck.Print.list QCheck.Print.float)
    (QCheck.Gen.list_size (QCheck.Gen.int_bound 150) gen_dt)

let run_progress mode dts =
  let world = World.create () in
  let progress = Progress.create ~mode (DummyPipeline.create ()) in
  let world_ref = ref world in
  List.iter
    (fun dt ->
      world_ref := Progress.tick progress ~world:!world_ref ~dt)
    dts;
  Option.value ~default:[] (World.get_data !world_ref `Progress_calls : call list option)

let prop_progress_tick_ordering =
  let step = 0.01 in
  let test_fn dts =
    let variable_actual = run_progress Progress.Variable dts in
    let fixed_actual = run_progress (Progress.Fixed step) dts in
    let hybrid_actual = run_progress (Progress.Hybrid step) dts in
    let variable_expected = simulate_variable dts in
    let fixed_expected = simulate_fixed ~step dts in
    let hybrid_expected = simulate_hybrid ~step dts in
    calls_equal variable_actual variable_expected
    && calls_equal fixed_actual fixed_expected
    && calls_equal hybrid_actual hybrid_expected
  in
  QCheck.Test.make
    ~name:"Progress.tick ordering across Variable/Fixed/Hybrid"
    ~count:1_000
    arb_dts
    test_fn

let tests =
  [ QCheck_alcotest.to_alcotest prop_progress_tick_ordering ]
