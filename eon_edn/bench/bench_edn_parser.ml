open Bechamel
open Staged

module Edn_parser = Eon_edn__Edn_parser
module Edn_middleware = Eon_edn__Edn_middleware

(* Representative documents: a flat map (exercises VMap consing/scalar
   parsing at scale) and a nested vector-of-maps (exercises recursive
   descent + allocation depth), sized by [count]. *)

let flat_map_doc count =
  let b = Buffer.create (count * 12) in
  Buffer.add_char b '{';
  for i = 0 to count - 1 do
    if i > 0 then Buffer.add_char b ' ';
    Buffer.add_string b (Printf.sprintf ":k%d %d" i i)
  done;
  Buffer.add_char b '}';
  Buffer.contents b

let nested_doc count =
  let b = Buffer.create (count * 24) in
  Buffer.add_char b '[';
  for i = 0 to count - 1 do
    if i > 0 then Buffer.add_char b ' ';
    Buffer.add_string b (Printf.sprintf {|{:id %d :pos [1.5 2.5] :name "e%d"}|} i i)
  done;
  Buffer.add_char b ']';
  Buffer.contents b

let mk_parse_flat_map count =
  let doc = flat_map_doc count in
  Test.make ~name:(Printf.sprintf "parse-flat-map-%d" count)
    (stage (fun () -> ignore (Edn_parser.run Edn_parser.value doc)))

let mk_parse_nested count =
  let doc = nested_doc count in
  Test.make ~name:(Printf.sprintf "parse-nested-%d" count)
    (stage (fun () -> ignore (Edn_parser.run Edn_parser.value doc)))

let parser_suite =
  Test.make_grouped ~name:"edn_parser"
    [ mk_parse_flat_map 100
    ; mk_parse_flat_map 1_000
    ; mk_parse_nested 100
    ; mk_parse_nested 1_000
    ]

(* Middleware overhead: same small tagged document, varying the number of
   pass-through handlers installed ahead of [default_handler], to see the
   marginal per-layer cost of [Effect.Deep.match_with] stacking. *)

let observing : Edn_middleware.handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff -> match eff with Eon_edn__Edn_effects.Tag _ -> None | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

let tagged_doc = {|#uuid "abc-123"|}

let mk_middleware_overhead n_handlers =
  let handlers = List.init n_handlers (fun _ -> observing) in
  Test.make ~name:(Printf.sprintf "middleware-overhead-%d-handlers" n_handlers)
    (stage (fun () ->
         ignore
           (Edn_middleware.run_with_middleware ~handlers
              (fun () -> Edn_parser.value ())
              tagged_doc)))

let middleware_suite =
  Test.make_grouped ~name:"edn_middleware"
    [ mk_middleware_overhead 0
    ; mk_middleware_overhead 1
    ; mk_middleware_overhead 5
    ; mk_middleware_overhead 20
    ]

let instances =
  [ Toolkit.Instance.monotonic_clock
  ; Toolkit.Instance.minor_allocated
  ; Toolkit.Instance.major_allocated
  ]

let benchmark cfg suite = Benchmark.all cfg instances suite

let () =
  let cfg = Benchmark.cfg ~limit:50 ~quota:(Time.second 1.0) () in
  List.iter
    (fun suite ->
       let raw = benchmark cfg suite in
       List.iter
         (fun instance ->
            let analyzed = Benchmark_helpers.analyze_single_instance instance raw in
            Benchmark_helpers.pp_results analyzed)
         instances)
    [ parser_suite; middleware_suite ];
  Format.printf "@.Hint: parse-* measures reader throughput/allocation; middleware-overhead-* measures per-layer Effect.Deep.match_with cost.@."
