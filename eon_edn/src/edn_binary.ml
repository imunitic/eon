open Edn_effects

module W = Edn_wire

type format = unit

module type LIMITS = sig
  val max_size : int
  val max_depth : int
end

module type S = sig
  module Encode : Edn_codec.ENCODE with type format = format
  module Decode : Edn_codec.DECODE with type format = format
end

module Encoder = struct
  type nonrec format = format

  let add_string b s =
    W.add_varint b (String.length s);
    Buffer.add_string b s

  let add_tag b tag = Buffer.add_uint8 b (W.to_byte tag)

  let rec write b = function
    | VNil -> add_tag b W.Nil
    | VBool false -> add_tag b W.False
    | VBool true -> add_tag b W.True
    | VNumber f ->
        add_tag b W.Number;
        Buffer.add_int64_le b (Int64.bits_of_float f)
    | VString s -> add_tag b W.String; add_string b s
    | VSymbol s -> add_tag b W.Symbol; add_string b s
    | VKeyword s -> add_tag b W.Keyword; add_string b s
    | VList vs -> write_seq b W.List vs
    | VVector vs -> write_seq b W.Vector vs
    | VMap kvs ->
        add_tag b W.Map;
        W.add_varint b (List.length kvs);
        List.iter (fun (k, v) -> write b k; write b v) kvs
    | VTagged (t, v) ->
        add_tag b W.Tagged;
        add_string b t;
        write b v
    | VMeta (m, v) ->
        add_tag b W.Meta;
        write b m;
        write b v

  and write_seq b tag vs =
    add_tag b tag;
    W.add_varint b (List.length vs);
    List.iter (write b) vs

  let encode v =
    let b = Buffer.create 64 in
    Buffer.add_string b W.magic;
    Buffer.add_uint8 b W.version;
    write b v;
    Edn_bytes.of_string (Buffer.contents b)
end

module Make (L : LIMITS) : S = struct
  module Encode = Encoder

  module Decode = struct
    type nonrec format = format

    let decode (bytes : Edn_bytes.t) =
      let s = (bytes :> string) in
      let len = String.length s in
      handle_fail (fun () ->
        if len > L.max_size then
          failf "document of %d bytes exceeds max_size %d" len L.max_size;
        let magic_len = String.length W.magic in
        if len < magic_len + 1 || String.sub s 0 magic_len <> W.magic then
          failf "not an EDN binary document (bad magic)";
        if Char.code s.[magic_len] <> W.version then
          failf "unsupported format version %d" (Char.code s.[magic_len]);
        let pos = ref (magic_len + 1) in
        let remaining () = len - !pos in
        let byte () =
          if !pos >= len then failf "unexpected end of input"
          else begin
            let c = Char.code (String.unsafe_get s !pos) in
            incr pos;
            c
          end
        in
        (* Unsigned LEB128, at most 9 groups so the shift stays below 63. *)
        let varint () =
          let rec go acc shift =
            if shift > 56 then failf "varint too long"
            else begin
              let b = byte () in
              let acc = acc lor ((b land 0x7f) lsl shift) in
              if b land 0x80 = 0 then acc else go acc (shift + 7)
            end
          in
          let n = go 0 0 in
          if n < 0 then failf "varint overflow" else n
        in
        (* Every string byte and every element takes at least one byte of
           input, so a length or count above the remaining input is invalid;
           this bounds allocation by the input size. *)
        let length () =
          let n = varint () in
          if n > remaining () then
            failf "length %d exceeds remaining input (%d)" n (remaining ())
          else n
        in
        let text () =
          let n = length () in
          let r = String.sub s !pos n in
          pos := !pos + n;
          r
        in
        let rec value depth =
          if depth > L.max_depth then
            failf "nesting deeper than max_depth %d" L.max_depth
          else begin
            let b = byte () in
            match W.of_byte b with
            | None -> failf "unknown tag byte 0x%02x" b
            | Some W.Nil -> VNil
            | Some W.False -> VBool false
            | Some W.True -> VBool true
            | Some W.Number ->
                if remaining () < 8 then failf "unexpected end of input"
                else begin
                  let f = Int64.float_of_bits (String.get_int64_le s !pos) in
                  pos := !pos + 8;
                  VNumber f
                end
            | Some W.String -> VString (text ())
            | Some W.Symbol -> VSymbol (text ())
            | Some W.Keyword -> VKeyword (text ())
            | Some W.List -> VList (elements depth)
            | Some W.Vector -> VVector (elements depth)
            | Some W.Map ->
                let n = length () in
                if n > remaining () / 2 then
                  failf "map of %d pairs exceeds remaining input (%d)" n (remaining ())
                else begin
                  let acc = ref [] in
                  for _ = 1 to n do
                    let k = value (depth + 1) in
                    let v = value (depth + 1) in
                    acc := (k, v) :: !acc
                  done;
                  VMap (List.rev !acc)
                end
            | Some W.Tagged ->
                let name = text () in
                let v = value (depth + 1) in
                Effect.perform (Tag (name, v))
            | Some W.Meta ->
                let m = value (depth + 1) in
                let v = value (depth + 1) in
                Effect.perform (Meta (m, v))
          end
        and elements depth =
          let n = length () in
          let acc = ref [] in
          for _ = 1 to n do
            acc := value (depth + 1) :: !acc
          done;
          List.rev !acc
        in
        let v = value 0 in
        if remaining () <> 0 then failf "%d trailing bytes after value" (remaining ());
        v)
  end
end

module Default_limits = struct
  let max_size = 16 * 1024 * 1024
  let max_depth = 256
end

include Make (Default_limits)
