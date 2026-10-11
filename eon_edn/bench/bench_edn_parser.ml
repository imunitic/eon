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

(* Binary codec vs text parse, on the same documents. [parse-*] above is the
   bare reader; here the text path also runs through the middleware stack
   (what [Edn_source.load] does) so it is comparable with [decode+middleware].
   Documents contain no tags, so [decode] alone is valid too. *)

module Binary = Eon_edn.Binary

let prefab_doc =
  {|{:extends "goblin_base"
 :components {:position {:x 10.0 :y 20.0}
              :velocity {:dx 1.0 :dy 0.0}
              :health {:max 150 :current 150}
              :sprite {:texture "goblin.png" :frame 3 :flip-x false}
              :collider {:w 16.0 :h 16.0}
              :tags [:enemy :melee :goblin]}
 :children [{:components {:position {:x 2.0 :y 0.0} :sprite {:texture "club.png" :frame 0}}}]}|}

let text_docs =
  [ "prefab", prefab_doc
  ; "nested-100", nested_doc 100
  ; "nested-1000", nested_doc 1_000
  ]

let mk_codec_benchmarks (label, text) =
  let tree = Edn_parser.run Edn_parser.value text in
  let bytes = Binary.Encode.encode tree in
  let parse_mw () =
    Edn_middleware.run_with_middleware (fun () -> Edn_parser.value ()) text
  in
  let decode_mw () =
    Eon_edn.Edn_middleware.with_middleware (fun () -> Binary.Decode.decode bytes)
  in
  [ Test.make ~name:(label ^ "-parse+middleware") (stage (fun () -> ignore (parse_mw ())))
  ; Test.make ~name:(label ^ "-decode") (stage (fun () -> ignore (Binary.Decode.decode bytes)))
  ; Test.make ~name:(label ^ "-decode+middleware") (stage (fun () -> ignore (decode_mw ())))
  ; Test.make ~name:(label ^ "-encode") (stage (fun () -> ignore (Binary.Encode.encode tree)))
  ]

let codec_suite =
  Test.make_grouped ~name:"edn_codec"
    (List.concat_map mk_codec_benchmarks text_docs)

(* Allocation per call, measured directly with the GC counters over many
   iterations. Bechamel's regression reads 0 for small allocations, so it
   cannot be trusted for these documents. Words are 8 bytes. A word is
   counted once: minor-heap allocations, plus allocations that went straight
   to the major heap (large blocks). *)

let alloc_runs = 10_000

let words_per_run f =
  ignore (Sys.opaque_identity (f ()));
  Gc.full_major ();
  let minor0, promoted0, major0 = Gc.counters () in
  for _ = 1 to alloc_runs do
    ignore (Sys.opaque_identity (f ()))
  done;
  let minor1, promoted1, major1 = Gc.counters () in
  let direct_major = (major1 -. promoted1) -. (major0 -. promoted0) in
  ((minor1 -. minor0) +. direct_major) /. float_of_int alloc_runs

let allocation_report () =
  Format.printf "@.== allocation per run (words; 1 word = 8 bytes) ==@.";
  List.iter
    (fun (label, text) ->
       let tree = Edn_parser.run Edn_parser.value text in
       let bytes = Binary.Encode.encode tree in
       let parse () = Edn_parser.run Edn_parser.value text in
       let parse_mw () =
         Edn_middleware.run_with_middleware (fun () -> Edn_parser.value ()) text
       in
       let decode () = Binary.Decode.decode bytes in
       let decode_mw () =
         Eon_edn.Edn_middleware.with_middleware (fun () -> Binary.Decode.decode bytes)
       in
       let encode () = Binary.Encode.encode tree in
       Format.printf "  %s: text %d B, binary %d B@." label (String.length text)
         (String.length (bytes :> string));
       List.iter
         (fun (name, f) ->
            let words = words_per_run f in
            Format.printf "    %-18s %12.0f words (%.1f KiB)@." name words
              (words *. 8. /. 1024.))
         [ "parse", (fun () -> ignore (parse ()))
         ; "parse+middleware", (fun () -> ignore (parse_mw ()))
         ; "decode", (fun () -> ignore (decode ()))
         ; "decode+middleware", (fun () -> ignore (decode_mw ()))
         ; "encode", (fun () -> ignore (encode ()))
         ])
    text_docs

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
    [ parser_suite; middleware_suite; codec_suite ];
  allocation_report ();
  Format.printf "@.Hint: parse-* measures reader throughput/allocation; middleware-overhead-* measures per-layer Effect.Deep.match_with cost; edn_codec-* compares text parse (+middleware) with binary decode (+middleware) and encode on the same documents.@."
