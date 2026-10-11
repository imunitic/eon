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

(* --- Property 4: refusal order — the *last* element of [handlers] is
   closest to the reader and gets first crack, for arbitrary chain length,
   not just the docs' one hand-picked 2-handler example
   ([log_tags; strict_tags [...]]). [prop_strict_tags] above already covers
   a single handler's own accept/reject behavior; a chain of homogeneous
   [strict_tags] handlers can't actually distinguish order from an AND
   across their allow-lists (all must allow for anything to resolve,
   regardless of order) — so this needs handlers that are individually
   distinguishable when they resolve. Each [label_handler idx] always
   resolves a tag to [VString (string_of idx)], never forwarding; a chain
   of them must always resolve to the *last* index, since propagation
   never reaches anything before it. *)

let label_handler idx : handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff -> match eff with
      | Tag (_, _) -> Some (fun k -> continue k (VString (string_of_int idx)))
      | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

let prop_refusal_order_is_last_element_first =
  QCheck.Test.make ~name:"the last element of handlers is nearest the reader and resolves first"
    ~count:200
    (QCheck.make ~print:string_of_int QCheck.Gen.(int_range 1 8))
    (fun n ->
      let resolved =
        run_with_middleware
          ~handlers:(List.init n label_handler)
          (fun () -> Eon_edn.Edn_parser.value ())
          {|#anytag 1|}
      in
      resolved = VString (string_of_int (n - 1)))

(* --- Binary codec properties ---------------------------------------

   Unlike the text round trip above, the binary generator is unrestricted:
   every float bit pattern (NaN payloads, signed zero, infinities), arbitrary
   bytes in strings, VTagged/VMeta, empty collections. *)

module Binary = Eon_edn.Binary

let gen_bits_float : float QCheck.Gen.t = QCheck.Gen.map Int64.float_of_bits QCheck.Gen.int64

let gen_raw_string : string QCheck.Gen.t =
  QCheck.Gen.string_size ~gen:QCheck.Gen.char (QCheck.Gen.int_bound 12)

let rec gen_full depth : value QCheck.Gen.t =
  let open QCheck.Gen in
  let scalar =
    oneof_weighted
      [
        1, pure VNil;
        1, map (fun b -> VBool b) bool;
        3, map (fun f -> VNumber f) gen_bits_float;
        2, map (fun s -> VString s) gen_raw_string;
        1, map (fun s -> VSymbol s) gen_raw_string;
        1, map (fun s -> VKeyword s) gen_raw_string;
      ]
  in
  if depth <= 0 then scalar
  else
    let sub = gen_full (depth - 1) in
    oneof_weighted
      [
        4, scalar;
        1, map (fun vs -> VList vs) (list_size (int_bound 4) sub);
        1, map (fun vs -> VVector vs) (list_size (int_bound 4) sub);
        1, map (fun kvs -> VMap kvs) (list_size (int_bound 4) (pair sub sub));
        1, map2 (fun t v -> VTagged (t, v)) gen_raw_string sub;
        1, map2 (fun m v -> VMeta (m, v)) sub sub;
      ]

let rec show = function
  | VNil -> "VNil"
  | VBool b -> Printf.sprintf "VBool %b" b
  | VNumber f -> Printf.sprintf "VNumber(0x%Lx)" (Int64.bits_of_float f)
  | VString s -> Printf.sprintf "VString %S" s
  | VSymbol s -> Printf.sprintf "VSymbol %S" s
  | VKeyword s -> Printf.sprintf "VKeyword %S" s
  | VList vs -> "VList [" ^ String.concat "; " (List.map show vs) ^ "]"
  | VVector vs -> "VVector [" ^ String.concat "; " (List.map show vs) ^ "]"
  | VMap kvs ->
      "VMap [" ^ String.concat "; " (List.map (fun (k, v) -> "(" ^ show k ^ ", " ^ show v ^ ")") kvs) ^ "]"
  | VTagged (t, v) -> Printf.sprintf "VTagged (%S, %s)" t (show v)
  | VMeta (m, v) -> Printf.sprintf "VMeta (%s, %s)" (show m) (show v)

let arb_full = QCheck.make ~print:show (gen_full 4)

let prop_binary_round_trip =
  QCheck.Test.make ~name:"decode (encode v) = v, bit-exact" ~count:1000 arb_full (fun v ->
      Test_edn_binary.same v (Test_edn_binary.roundtrip v))

(* Hostile or damaged input: the decoder returns a value or raises Failure,
   never any other exception (no Invalid_argument, Out_of_memory,
   Stack_overflow, Not_found, ...). *)
let only_failure_escapes decode s =
  match decode (Eon_edn.Edn_bytes.of_string s) with
  | _ -> true
  | exception Failure _ -> true
  | exception _ -> false

let gen_mutated : string QCheck.Gen.t =
  let open QCheck.Gen in
  gen_full 3 >>= fun v ->
  let s = (Binary.Encode.encode v :> string) in
  let n = String.length s in
  int_bound (n - 1) >>= fun i ->
  oneof
    [
      map (fun c -> String.mapi (fun j x -> if j = i then c else x) s) char;
      pure (String.sub s 0 i);
      map (fun c -> String.sub s 0 i ^ String.make 1 c ^ String.sub s i (n - i)) char;
      map (fun suffix -> s ^ suffix) (string_size ~gen:char (int_range 1 4));
    ]

let arb_mutated = QCheck.make ~print:(Printf.sprintf "%S") gen_mutated

let arb_headed_noise =
  QCheck.make ~print:(Printf.sprintf "%S")
    (QCheck.Gen.map (fun s -> "EDNB\x01" ^ s)
       (QCheck.Gen.string_size ~gen:QCheck.Gen.char (QCheck.Gen.int_bound 64)))

module Tight = Binary.Make (struct
  let max_size = 48
  let max_depth = 3
end)

let prop_mutated_input =
  QCheck.Test.make ~name:"mutated documents raise only Failure" ~count:2000 arb_mutated
    (fun s -> only_failure_escapes Test_edn_binary.decode s)

let prop_mutated_input_tight_limits =
  QCheck.Test.make ~name:"mutated documents raise only Failure under tight limits"
    ~count:1000 arb_mutated
    (fun s -> only_failure_escapes (Test_edn_binary.decode_with (module Tight)) s)

let prop_noise_after_header =
  QCheck.Test.make ~name:"noise behind a valid header raises only Failure" ~count:2000
    arb_headed_noise
    (fun s -> only_failure_escapes Test_edn_binary.decode s)

let prop_arbitrary_bytes =
  QCheck.Test.make ~name:"arbitrary bytes raise only Failure" ~count:1000 QCheck.string
    (fun s -> only_failure_escapes Test_edn_binary.decode s)

let tests =
  [
    QCheck_alcotest.to_alcotest prop_round_trip;
    QCheck_alcotest.to_alcotest prop_middleware_forwarding;
    QCheck_alcotest.to_alcotest prop_strict_tags;
    QCheck_alcotest.to_alcotest prop_refusal_order_is_last_element_first;
    QCheck_alcotest.to_alcotest prop_binary_round_trip;
    QCheck_alcotest.to_alcotest prop_mutated_input;
    QCheck_alcotest.to_alcotest prop_mutated_input_tight_limits;
    QCheck_alcotest.to_alcotest prop_noise_after_header;
    QCheck_alcotest.to_alcotest prop_arbitrary_bytes;
  ]
