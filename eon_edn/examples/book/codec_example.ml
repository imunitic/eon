(* Transcribed into doc/codec.mld — keep in sync by hand. *)

open Eon_edn.Edn_effects
module Binary = Eon_edn.Binary
module M = Eon_edn.Edn_middleware

let round_trip () =
  let v =
    VMap [ (VKeyword "name", VString "Crab"); (VKeyword "pos", VVector [ VNumber 1.; VNumber 2. ]) ]
  in
  let bytes = Binary.Encode.encode v in
  (* [bytes] is an [Edn_bytes.t]: a [private string], so it reads as a
     string through a coercion. *)
  assert (String.length (bytes :> string) > 0);
  assert (Binary.Decode.decode bytes = v)

let register_shout () =
  M.register_tag_handler "shout" (fun _ v ->
      match v with VString s -> VString (String.uppercase_ascii s) | v -> v)

let tags_resolve_on_decode () =
  register_shout ();
  let bytes = Binary.Encode.encode (VTagged ("shout", VString "hi")) in
  (* [Decode] performs a [Tag] effect for the tagged node, so run it inside
     the same middleware stack the text reader uses. *)
  let v = M.with_middleware (fun () -> Binary.Decode.decode bytes) in
  assert (v = VString "HI")

let compile_text () =
  register_shout ();
  let text = {|#shout "x"|} in
  let parse () = Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value text in
  (* [reify] leaves tags unresolved, so the compiled tree depends only on
     the text, not on whatever handlers happen to be registered. *)
  let tree = M.with_middleware ~handlers:[ M.reify ] parse in
  assert (tree = VTagged ("shout", VString "x"));
  let bytes = Binary.Encode.encode tree in
  let from_binary = M.with_middleware (fun () -> Binary.Decode.decode bytes) in
  let from_text = M.run_with_middleware (fun () -> Eon_edn.Edn_parser.value ()) text in
  assert (from_binary = from_text)

let untrusted_input () =
  let bytes = Binary.Encode.encode (VTagged ("evil", VNil)) in
  match
    M.with_middleware ~handlers:[ M.strict_tags [ "shout" ] ] (fun () ->
        Binary.Decode.decode bytes)
  with
  | exception Failure _ -> ()
  | _ -> assert false

module Small = Eon_edn.Binary.Make (struct
  let max_size = 1024
  let max_depth = 8
end)

let rec nest n = if n = 0 then VNil else VVector [ nest (n - 1) ]

let custom_limits () =
  (* The encoder ignores limits; only the decoder enforces them. *)
  let bytes = Small.Encode.encode (nest 20) in
  (match Small.Decode.decode bytes with
   | exception Failure _ -> ()
   | _ -> assert false);
  (* Pairing is by [format] alone, so the default decoder accepts it. *)
  assert (Binary.Decode.decode bytes = nest 20)

(* A consumer that needs both halves pairs them by [format]: the compiler
   rejects an encoder and decoder that do not share a wire format. *)
module Round_trip (E : Eon_edn.ENCODE) (D : Eon_edn.DECODE with type format = E.format) =
struct
  let go v = D.decode (E.encode v)
end

module Binary_round_trip = Round_trip (Binary.Encode) (Binary.Decode)

let paired_codecs () = assert (Binary_round_trip.go (VList [ VNil ]) = VList [ VNil ])

let () =
  round_trip ();
  tags_resolve_on_decode ();
  compile_text ();
  untrusted_input ();
  custom_limits ();
  paired_codecs ()
