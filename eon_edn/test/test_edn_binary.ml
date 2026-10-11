open Alcotest
open Eon_edn.Edn_effects

let encode v = (Eon_edn.Binary.Encode.encode v :> string)

(* Every document starts with the magic bytes and the version byte. *)
let header = "EDNB\x01"

let check_doc msg expected v = check string msg (header ^ expected) (encode v)

let float_le f =
  let b = Buffer.create 8 in
  Buffer.add_int64_le b (Int64.bits_of_float f);
  Buffer.contents b

let test_header () =
  check string "magic and version" header (String.sub (encode VNil) 0 5)

let test_scalars () =
  check_doc "nil" "\x00" VNil;
  check_doc "false" "\x01" (VBool false);
  check_doc "true" "\x02" (VBool true);
  check_doc "number is float64 little-endian"
    ("\x03" ^ "\x00\x00\x00\x00\x00\x00\xf0\x3f")
    (VNumber 1.0)

let test_number_bits_preserved () =
  check_doc "negative zero keeps its sign bit" ("\x03" ^ float_le (-0.0)) (VNumber (-0.0));
  check_doc "nan keeps its payload" ("\x03" ^ float_le nan) (VNumber nan);
  check bool "0.0 and -0.0 encode differently" true
    (encode (VNumber 0.0) <> encode (VNumber (-0.0)))

let test_text_kinds () =
  check_doc "string" "\x04\x02hi" (VString "hi");
  check_doc "symbol" "\x08\x02hi" (VSymbol "hi");
  check_doc "keyword" "\x09\x02hi" (VKeyword "hi");
  check_doc "empty string" "\x04\x00" (VString "")

let test_varint_lengths () =
  let s127 = String.make 127 'a' and s128 = String.make 128 'a' in
  check_doc "length 127 is one byte" ("\x04\x7f" ^ s127) (VString s127);
  check_doc "length 128 is two bytes" ("\x04\x80\x01" ^ s128) (VString s128);
  let s300 = String.make 300 'a' in
  check_doc "length 300 = 0xAC 0x02" ("\x04\xac\x02" ^ s300) (VString s300)

let test_collections () =
  check_doc "list" "\x05\x02\x00\x02" (VList [ VNil; VBool true ]);
  check_doc "vector" "\x06\x01\x00" (VVector [ VNil ]);
  check_doc "empty vector" "\x06\x00" (VVector []);
  check_doc "map keeps entry order" "\x07\x02\x09\x01b\x00\x09\x01a\x02"
    (VMap [ (VKeyword "b", VNil); (VKeyword "a", VBool true) ])

let test_list_vs_vector_distinct () =
  check bool "list and vector differ" true
    (encode (VList [ VNil ]) <> encode (VVector [ VNil ]));
  check bool "string and keyword differ" true
    (encode (VString "a") <> encode (VKeyword "a"))

let test_tagged_and_meta () =
  check_doc "tagged: name then value" "\x0a\x03foo\x00" (VTagged ("foo", VNil));
  check_doc "meta: meta then value" "\x0b\x09\x01m\x06\x00"
    (VMeta (VKeyword "m", VVector []))

(* --- decoding ----------------------------------------------------- *)

module B = Eon_edn.Binary
module M = Eon_edn.Edn_middleware

let raw s = Eon_edn.Edn_bytes.of_string s

(* Bit-exact float equality, so NaN payloads and signed zero count. *)
let rec same a b =
  match (a, b) with
  | VNumber x, VNumber y -> Int64.equal (Int64.bits_of_float x) (Int64.bits_of_float y)
  | VList xs, VList ys | VVector xs, VVector ys ->
      List.length xs = List.length ys && List.for_all2 same xs ys
  | VMap xs, VMap ys ->
      List.length xs = List.length ys
      && List.for_all2 (fun (k, v) (k', v') -> same k k' && same v v') xs ys
  | VTagged (t, v), VTagged (t', v') -> t = t' && same v v'
  | VMeta (m, v), VMeta (m', v') -> same m m' && same v v'
  | (VNil | VBool _ | VString _ | VSymbol _ | VKeyword _), _ -> a = b
  | _ -> false

let value_testable = testable (fun fmt _ -> Format.pp_print_string fmt "<value>") same
let check_value = check value_testable

(* [~resolve:false] keeps tags unresolved, whatever other tests registered
   globally. *)
let decode_with (module C : Eon_edn.Binary.S) b =
  M.with_middleware ~resolve:false (fun () -> C.Decode.decode b)

let decode b = decode_with (module B) b
let roundtrip v = decode (B.Encode.encode v)

let fails msg thunk =
  match thunk () with
  | exception Failure _ -> ()
  | _ -> fail (msg ^ ": expected Failure")

let samples =
  [ VNil; VBool true; VBool false; VNumber 0.0; VNumber (-0.0); VNumber nan
  ; VNumber infinity; VNumber 1e308; VString ""; VString "h\xc3\xa9llo \xe2\x9c\x93"
  ; VString (String.make 1000 'x'); VSymbol "foo/bar"; VKeyword "k"
  ; VList []; VVector []; VMap []
  ; VList [ VNil; VVector [ VNumber 1.; VNumber 2. ] ]
  ; VMap [ (VKeyword "b", VNumber 2.); (VKeyword "a", VNumber 1.); (VString "s", VNil) ]
  ; VTagged ("inst", VString "2020"); VMeta (VKeyword "m", VVector [ VNil ])
  ; VTagged ("a", VTagged ("b", VMeta (VNil, VList [ VTagged ("c", VNil) ]))) ]

let test_roundtrip () =
  List.iter (fun v -> check_value "round trip" v (roundtrip v)) samples

let nested n =
  header ^ String.concat "" (List.init n (fun _ -> "\x06\x01")) ^ "\x00"

let test_malformed () =
  fails "empty" (fun () -> decode (raw ""));
  fails "bad magic" (fun () -> decode (raw "NOPE\x01\x00"));
  fails "bad version" (fun () -> decode (raw "EDNB\x02\x00"));
  fails "missing value" (fun () -> decode (raw header));
  fails "unknown tag byte" (fun () -> decode (raw (header ^ "\x7f")));
  fails "trailing byte" (fun () -> decode (raw (header ^ "\x00\x00")));
  fails "short number" (fun () -> decode (raw (header ^ "\x03\x00\x00")));
  fails "overlong varint"
    (fun () -> decode (raw (header ^ "\x04" ^ String.make 10 '\xff' ^ "\x01")))

(* Only bytes 0x00-0x0B start a value; every other byte is rejected as an
   unknown tag, whatever follows. *)
let test_tag_bytes () =
  for b = 0 to 255 do
    let doc = raw (header ^ String.make 1 (Char.chr b)) in
    let unknown =
      match decode doc with
      | exception Failure msg ->
          String.length msg >= 15 && String.sub msg 0 15 = "unknown tag byt"
      | _ -> false
    in
    check bool (Printf.sprintf "byte 0x%02x" b) (b > 0x0b) unknown
  done

let test_truncation_always_fails () =
  List.iter
    (fun v ->
      let s = (B.Encode.encode v :> string) in
      for k = 0 to String.length s - 1 do
        fails (Printf.sprintf "prefix %d of %d" k (String.length s))
          (fun () -> decode (raw (String.sub s 0 k)))
      done)
    samples

let test_hostile_lengths () =
  (* Claimed sizes far beyond the actual input must fail before allocating. *)
  let huge = "\x80\x80\x80\x80\x80\x80\x80\x01" in
  fails "huge string" (fun () -> decode (raw (header ^ "\x04" ^ huge)));
  fails "huge list" (fun () -> decode (raw (header ^ "\x05" ^ huge)));
  fails "huge vector" (fun () -> decode (raw (header ^ "\x06" ^ huge)));
  fails "huge map" (fun () -> decode (raw (header ^ "\x07" ^ huge)));
  fails "huge tag name" (fun () -> decode (raw (header ^ "\x0a" ^ huge)));
  fails "count above remaining" (fun () -> decode (raw (header ^ "\x05\x05\x00\x00")));
  fails "map pairs above remaining/2" (fun () -> decode (raw (header ^ "\x07\x02\x00\x00\x00")))

let test_default_depth_limit () =
  ignore (decode (raw (nested 256)));
  fails "257 levels" (fun () -> decode (raw (nested 257)));
  fails "very deep" (fun () -> decode (raw (nested 100_000)))

module Tight = Eon_edn.Binary.Make (struct
  let max_size = 32
  let max_depth = 2
end)

let test_custom_limits () =
  let dec b = decode_with (module Tight) b in
  ignore (dec (raw (nested 2)));
  fails "depth 3 over max_depth 2" (fun () -> dec (raw (nested 3)));
  let big = (B.Encode.encode (VString (String.make 100 'a')) :> string) in
  fails "over max_size" (fun () -> dec (raw big));
  check_value "default limits accept it" (VString (String.make 100 'a'))
    (decode (raw big))

(* Encoder and decoder from different [Make] applications still pair, since
   they share the [format] type; only the limits differ. *)
let test_pairing_by_format () =
  let bytes = Tight.Encode.encode (VVector [ VNil ]) in
  check_value "encoded by Tight, decoded by default" (VVector [ VNil ]) (decode bytes)

(* --- middleware --------------------------------------------------- *)

let parse_text s () = Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value s

let test_decode_matches_text_through_middleware () =
  M.register_tag_handler "bin_shout" (fun _ v ->
      match v with VString s -> VString (String.uppercase_ascii s) | v -> v);
  let text = {|{:a #bin_shout "x" :b ^:m [1 #unregistered 2 #bin_shout #bin_shout "y"]}|} in
  let via_text = M.run_with_middleware (fun () -> Eon_edn.Edn_parser.value ()) text in
  (* Compile: resolve:false keeps the tree independent of the registry. *)
  let tree = M.with_middleware ~resolve:false (parse_text text) in
  check bool "reified tree keeps the tags" true (tree <> via_text);
  let bytes = B.Encode.encode tree in
  let via_binary = M.with_middleware (fun () -> B.Decode.decode bytes) in
  check_value "binary through middleware = text through middleware" via_text via_binary

let test_strict_tags_on_binary () =
  let bytes = B.Encode.encode (VVector [ VTagged ("evil", VNil) ]) in
  (match
     M.with_middleware ~handlers:[ M.strict_tags [ "ok" ] ] (fun () -> B.Decode.decode bytes)
   with
  | exception Failure msg -> check string "rejected" "Unknown tag: #evil" msg
  | _ -> fail "expected strict_tags to reject");
  let ok = B.Encode.encode (VTagged ("ok", VNil)) in
  ignore (M.with_middleware ~handlers:[ M.strict_tags [ "ok" ] ] (fun () -> B.Decode.decode ok))

let test_tag_effects_are_bottom_up () =
  let seen = ref [] in
  let observe : M.handler = fun next ->
    let open Effect.Deep in
    let effc : type a. a Effect.t -> ((a, _) continuation -> _) option = fun eff ->
      match eff with
      | Tag (t, _) -> seen := t :: !seen; None
      | _ -> None
    in
    match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }
  in
  let bytes = B.Encode.encode (VTagged ("outer", VTagged ("inner", VNil))) in
  ignore (M.with_middleware ~handlers:[ observe ] (fun () -> B.Decode.decode bytes));
  check (list string) "inner resolved before outer" [ "outer"; "inner" ] !seen

let tests = [
  test_case "header" `Quick test_header;
  test_case "scalars" `Quick test_scalars;
  test_case "number bits preserved" `Quick test_number_bits_preserved;
  test_case "text kinds" `Quick test_text_kinds;
  test_case "varint lengths" `Quick test_varint_lengths;
  test_case "collections" `Quick test_collections;
  test_case "list/vector and string/keyword stay distinct" `Quick test_list_vs_vector_distinct;
  test_case "tagged and meta" `Quick test_tagged_and_meta;
  test_case "decode: round trip" `Quick test_roundtrip;
  test_case "decode: malformed input raises Failure" `Quick test_malformed;
  test_case "decode: only 0x00-0x0b are tag bytes" `Quick test_tag_bytes;
  test_case "decode: every truncation raises Failure" `Quick test_truncation_always_fails;
  test_case "decode: hostile lengths and counts" `Quick test_hostile_lengths;
  test_case "decode: default depth limit" `Quick test_default_depth_limit;
  test_case "decode: custom limits via Make" `Quick test_custom_limits;
  test_case "decode: pairing is by format alone" `Quick test_pairing_by_format;
  test_case "decode: matches text through middleware" `Quick test_decode_matches_text_through_middleware;
  test_case "decode: strict_tags guards binary input" `Quick test_strict_tags_on_binary;
  test_case "decode: tag effects are bottom-up" `Quick test_tag_effects_are_bottom_up;
]
