open Bechamel
open Staged
open Eon_engine

(* Fresh temp directory, written once — the benchmarked closure only
   ever reads it, so setup cost (file I/O) doesn't pollute the
   measurement. *)
let write_prefab_dir files =
  let dir = Filename.temp_file "eon_prefab_bench" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  List.iter
    (fun (name, contents) ->
      let oc = open_out (Filename.concat dir (name ^ ".edn")) in
      output_string oc contents;
      close_out oc)
    files;
  dir

let create_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

(* ------------------------------------------------------------------ *)
(* Q1: Nested children — spawn cost/allocation as tree size grows.     *)
(* Each node has a single Tag component; the tree is flattened into a  *)
(* single root's :children vector [n] entries deep (not nested further *)
(* — this isolates "how many entities does the work-list spawn" from   *)
(* "how deep is the recursion", the latter already stress-tested       *)
(* structurally in test_prefab.ml's 50,000-deep chain).                *)
(* ------------------------------------------------------------------ *)

let flat_children_doc n =
  let children =
    String.concat " "
      (List.init n (fun i -> Printf.sprintf {|{:components {:Tag {:value "c%d"}}}|} i))
  in
  Printf.sprintf {|{:components {:Tag {:value "root"}} :children [%s]}|} children

let mk_nested_children n =
  let dir = write_prefab_dir [ "root", flat_children_doc n ] in
  let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
  Prefab_edn_defaults.register_all Prefab_edn.register_component;
  Test.make ~name:(Printf.sprintf "nested-children-%d" n)
    (stage (fun () -> ignore (Prefab_edn.load (create_world ()) "root")))

let nested_children_suite =
  Test.make_grouped ~name:"prefab_spawn"
    [ mk_nested_children 10; mk_nested_children 100; mk_nested_children 1_000 ]

(* ------------------------------------------------------------------ *)
(* Q2: Inheritance chains — resolve+merge cost as chain length grows.  *)
(* ------------------------------------------------------------------ *)

let chain_files n =
  List.init n (fun i ->
      let name = Printf.sprintf "n%d" i in
      if i = n - 1 then (name, {|{:components {:Tag {:value "root"}}}|})
      else
        ( name
        , Printf.sprintf {|{:extends "n%d" :components {:Tag {:value "n%d"}}}|} (i + 1) i ))

let mk_inheritance_chain n =
  let dir = write_prefab_dir (chain_files n) in
  let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
  Prefab_edn_defaults.register_all Prefab_edn.register_component;
  Test.make ~name:(Printf.sprintf "inheritance-chain-%d" n)
    (stage (fun () -> ignore (Prefab_edn.load (create_world ()) "n0")))

let inheritance_suite =
  Test.make_grouped ~name:"prefab_inheritance"
    [ mk_inheritance_chain 5; mk_inheritance_chain 20; mk_inheritance_chain 50 ]

let instances =
  [ Toolkit.Instance.monotonic_clock
  ; Toolkit.Instance.minor_allocated
  ; Toolkit.Instance.major_allocated
  ]

let benchmark cfg suite = Benchmark.all cfg instances suite

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Bechamel.Time.second 1.0) () in
  List.iter
    (fun suite ->
       let raw = benchmark cfg suite in
       List.iter
         (fun instance ->
            let analyzed = Benchmark_helpers.analyze_single_instance instance raw in
            Benchmark_helpers.pp_results analyzed)
         instances)
    [ nested_children_suite; inheritance_suite ];
  Format.printf "@.Hint: nested-children-* measures spawn throughput/allocation; inheritance-chain-* measures resolve+merge cost as :extends depth grows.@."
