open Bechamel

module World = Eon_ecs__World

let register_components world names =
  List.iteri
    (fun id name -> ignore (World.register_component world ~name ~id))
    names

let default_distribution eid idx =
  (* Default pattern: every (idx + 2)th entity has component idx *)
  eid mod (idx + 2) = 0

let distribution_all _ _ = true

let distribution_every step =
  if step <= 0 then invalid_arg "distribution_every expects step > 0";
  fun eid _ -> eid mod step = 0

let distribution_alternating eid idx =
  (eid + idx) mod 2 = 0

let distribution_random ?seed ~probability () =
  if probability < 0. || probability > 1. then
    invalid_arg "distribution_random expects probability in [0, 1]";
  let state =
    match seed with
    | Some seed -> Random.State.make [| seed |]
    | None -> Random.State.make [| 0x51f15fab; 0x5a1fbead |]
  in
  fun _ _ -> Random.State.float state 1.0 <= probability

let distribution_gradient ~period ~peak eid idx =
  if period <= 0 then invalid_arg "distribution_gradient expects period > 0";
  if peak <= 0 then invalid_arg "distribution_gradient expects peak > 0";
  let local = (eid + idx) mod period in
  local < peak

let[@warning "-16"] populate_world ?(distribution = default_distribution) ~entity_count
    ~component_count =
  let world = World.create () in
  let names =
    List.init component_count (fun i -> Printf.sprintf "C%d" (i + 1))
  in
  register_components world names;

  for eid = 0 to entity_count - 1 do
    let entity = World.create_entity world in
    List.iteri
      (fun idx name ->
         if distribution eid idx then
           World.add_component world entity ~name (eid + idx))
      names
  done;

  world, names

let analyze_single_instance instance raw =
  let open Analyze in
  let ols = ols ~bootstrap:0 ~r_square:true ~predictors:[| Measure.run |] in
  let table = Analyze.all ols instance raw in
  Analyze.merge ols [ instance ] [ table ]

(* Auto-scaled ns -> ns/us/ms/s, so "which is faster" reads from the unit
   alone instead of requiring the reader to compare exponents (e.g. "4.638e+05"
   vs "2.203e+06"). Mirrors the convention hyperfine/criterion.rs use for the
   same reason. *)
let format_duration_ns ns =
  let ns = abs_float ns in
  if ns < 1_000. then Printf.sprintf "%.1f ns" ns
  else if ns < 1_000_000. then Printf.sprintf "%.2f \xc2\xb5s" (ns /. 1_000.)
  else if ns < 1_000_000_000. then
    Printf.sprintf "%.2f ms" (ns /. 1_000_000.)
  else Printf.sprintf "%.2f s" (ns /. 1_000_000_000.)

let pp_results results =
  Hashtbl.iter
    (fun measure_label tests ->
      Format.printf "== %s ==@." measure_label;
      Hashtbl.iter
        (fun test_name ols ->
          let estimates = Analyze.OLS.estimates ols in
          let slope =
            match estimates with
            | Some (_intercept :: slope :: _) -> slope
            | Some (slope :: _) -> slope
            | _ -> nan
          in
          let is_alloc =
            String.ends_with ~suffix:"allocated"
              (String.lowercase_ascii measure_label)
          in
          let metric = if is_alloc then "alloc/run" else "time/run" in
          let value =
            if is_alloc then Printf.sprintf "%.3e" slope
            else format_duration_ns slope
          in
          Format.printf "  %s: %s (%s)@." test_name value metric)
        tests)
    results

let bench_with_gc cfg suite =
  let instances =
    [ Toolkit.Instance.monotonic_clock;
      Toolkit.Instance.minor_allocated;
      Toolkit.Instance.major_allocated ]
  in
  let raw = Benchmark.all cfg instances suite in
  List.iter
    (fun instance ->
       let analyzed = analyze_single_instance instance raw in
       pp_results analyzed)
    instances
