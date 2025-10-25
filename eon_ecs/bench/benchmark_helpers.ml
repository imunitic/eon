open Bechamel

let analyze_single_instance instance raw =
  let open Analyze in
  let ols = ols ~bootstrap:0 ~r_square:true ~predictors:[| Measure.run |] in
  let table = Analyze.all ols instance raw in
  Analyze.merge ols [ instance ] [ table ]

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
          Format.printf "  %s: %.3e (time/run)@." test_name slope)
        tests)
    results
