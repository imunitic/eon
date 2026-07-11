open Eon_edn.Edn_effects
open Eon_edn.Edn_middleware

(* --- A test-local printer, matching the eon_edn grammar. Not part of
   eon_edn's public API — exists only to construct valid EDN strings from
   generated [value] trees for the round-trip property below. The
   generator deliberately restricts strings/symbols/keywords/numbers to
   ranges that print without needing escaping, so this printer can stay
   trivial. VTagged/VMeta are out of scope here (round-tripping those
   meaningfully requires middleware, exercised separately below). --- *)
let rec print_value = function
  | VNil -> "nil"
  | VBool true -> "true"
  | VBool false -> "false"
  | VNumber n -> Printf.sprintf "%.4f" n
  | VString s -> "\"" ^ s ^ "\""
  | VSymbol s -> s
  | VKeyword s -> ":" ^ s
  | VList vs -> "(" ^ String.concat " " (List.map print_value vs) ^ ")"
  | VVector vs -> "[" ^ String.concat " " (List.map print_value vs) ^ "]"
  | VMap kvs ->
      "{" ^ String.concat " " (List.map (fun (k, v) -> print_value k ^ " " ^ print_value v) kvs) ^ "}"
  | VTagged _ | VMeta _ -> invalid_arg "print_value: generator never produces VTagged/VMeta"

(* --- Generators --- *)

let letters =
  List.init 26 (fun i -> Char.chr (Char.code 'a' + i))
  @ List.init 26 (fun i -> Char.chr (Char.code 'A' + i))

let digits = List.init 10 (fun i -> Char.chr (Char.code '0' + i))

let gen_ident : string QCheck.Gen.t =
  let open QCheck.Gen in
  map2
    (fun c cs -> String.make 1 c ^ String.concat "" (List.map (String.make 1) cs))
    (oneof_list letters)
    (list_size (int_bound 6) (oneof_list (letters @ digits @ [ '_'; '-' ])))

(* symbols must not collide with the reserved words nil/true/false *)
let gen_symbol_string : string QCheck.Gen.t =
  QCheck.Gen.map
    (fun s -> match s with "nil" | "true" | "false" -> s ^ "x" | s -> s)
    gen_ident

(* printable ASCII excluding '"' and '\\' and control chars — avoids
   needing any escaping logic in [print_value] *)
let gen_string_content : string QCheck.Gen.t =
  let open QCheck.Gen in
  map
    (fun cs -> String.concat "" (List.map (String.make 1) cs))
    (list_size (int_bound 8)
       (map Char.chr (int_range 32 126 >>= fun c -> if c = 34 || c = 92 then return 97 else return c)))

let gen_number : value QCheck.Gen.t =
  let open QCheck.Gen in
  map2
    (fun whole frac -> VNumber (float_of_int whole +. (float_of_int frac /. 10000.0)))
    (int_range (-100000) 100000)
    (int_range 0 9999)

let rec gen_value depth : value QCheck.Gen.t =
  let open QCheck.Gen in
  let scalar =
    oneof_weighted
      [
        1, pure VNil;
        1, map (fun b -> VBool b) bool;
        3, gen_number;
        2, map (fun s -> VString s) gen_string_content;
        2, map (fun s -> VSymbol s) gen_symbol_string;
        2, map (fun s -> VKeyword s) gen_ident;
      ]
  in
  if depth <= 0 then scalar
  else
    oneof_weighted
      [
        4, scalar;
        1, map (fun vs -> VList vs) (list_size (int_bound 3) (gen_value (depth - 1)));
        1, map (fun vs -> VVector vs) (list_size (int_bound 3) (gen_value (depth - 1)));
        1,
        map (fun kvs -> VMap kvs)
          (list_size (int_bound 3) (pair (gen_value 0) (gen_value (depth - 1))));
      ]

let arb_value = QCheck.make ~print:print_value (gen_value 3)

(* --- Property 1: round trip --- *)

let prop_round_trip =
  QCheck.Test.make ~name:"parse (print v) = v" ~count:500 arb_value (fun v ->
      Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value (print_value v) = v)

(* --- Property 2: observe-only middleware never changes the resolved
   value, regardless of how many are inserted --- *)

let observing : handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff -> match eff with Tag _ -> None | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

let prop_middleware_forwarding =
  QCheck.Test.make ~name:"observe-only handlers never change the resolved value"
    ~count:200
    (QCheck.make ~print:string_of_int QCheck.Gen.(int_bound 10))
    (fun n ->
      register_tag_handler "uuid" (fun _ v ->
          match v with VString s -> VTagged ("uuid", VString (String.uppercase_ascii s)) | v -> v);
      let baseline =
        run_with_middleware (fun () -> Eon_edn.Edn_parser.value ()) {|#uuid "abc"|}
      in
      let with_observers =
        run_with_middleware ~handlers:(List.init n (fun _ -> observing))
          (fun () -> Eon_edn.Edn_parser.value ())
          {|#uuid "abc"|}
      in
      baseline = with_observers)

(* --- Property 3: strict_tags forwards iff the tag is in the allowed
   list, for arbitrary tag names and allowed lists, not just the doc's
   two hand-picked examples --- *)

let prop_strict_tags =
  QCheck.Test.make ~name:"strict_tags forwards iff tag is in allowed list" ~count:300
    (QCheck.pair (QCheck.make gen_ident) (QCheck.list_small (QCheck.make gen_ident)))
    (fun (tag, allowed) ->
      let input = Printf.sprintf "#%s 1" tag in
      let resolved =
        try
          let _ =
            run_with_middleware ~handlers:[ strict_tags allowed ]
              (fun () -> Eon_edn.Edn_parser.value ())
              input
          in
          true
        with Failure _ -> false
      in
      resolved = List.mem tag allowed)

let tests =
  [
    QCheck_alcotest.to_alcotest prop_round_trip;
    QCheck_alcotest.to_alcotest prop_middleware_forwarding;
    QCheck_alcotest.to_alcotest prop_strict_tags;
  ]
