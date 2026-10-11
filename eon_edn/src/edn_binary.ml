open Edn_effects

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
    Edn_wire.add_varint b (String.length s);
    Buffer.add_string b s

  let rec write b = function
    | VNil -> Buffer.add_uint8 b Edn_wire.tag_nil
    | VBool false -> Buffer.add_uint8 b Edn_wire.tag_false
    | VBool true -> Buffer.add_uint8 b Edn_wire.tag_true
    | VNumber f ->
        Buffer.add_uint8 b Edn_wire.tag_number;
        Buffer.add_int64_le b (Int64.bits_of_float f)
    | VString s -> Buffer.add_uint8 b Edn_wire.tag_string; add_string b s
    | VSymbol s -> Buffer.add_uint8 b Edn_wire.tag_symbol; add_string b s
    | VKeyword s -> Buffer.add_uint8 b Edn_wire.tag_keyword; add_string b s
    | VList vs -> write_seq b Edn_wire.tag_list vs
    | VVector vs -> write_seq b Edn_wire.tag_vector vs
    | VMap kvs ->
        Buffer.add_uint8 b Edn_wire.tag_map;
        Edn_wire.add_varint b (List.length kvs);
        List.iter (fun (k, v) -> write b k; write b v) kvs
    | VTagged (t, v) ->
        Buffer.add_uint8 b Edn_wire.tag_tagged;
        add_string b t;
        write b v
    | VMeta (m, v) ->
        Buffer.add_uint8 b Edn_wire.tag_meta;
        write b m;
        write b v

  and write_seq b tag vs =
    Buffer.add_uint8 b tag;
    Edn_wire.add_varint b (List.length vs);
    List.iter (write b) vs

  let encode v =
    let b = Buffer.create 64 in
    Buffer.add_string b Edn_wire.magic;
    Buffer.add_uint8 b Edn_wire.version;
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
        let magic_len = String.length Edn_wire.magic in
        if len < magic_len + 1 || String.sub s 0 magic_len <> Edn_wire.magic then
          failf "not an EDN binary document (bad magic)";
        if Char.code s.[magic_len] <> Edn_wire.version then
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
            let tag = byte () in
            if tag = Edn_wire.tag_nil then VNil
            else if tag = Edn_wire.tag_false then VBool false
            else if tag = Edn_wire.tag_true then VBool true
            else if tag = Edn_wire.tag_number then begin
              if remaining () < 8 then failf "unexpected end of input"
              else begin
                let f = Int64.float_of_bits (String.get_int64_le s !pos) in
                pos := !pos + 8;
                VNumber f
              end
            end
            else if tag = Edn_wire.tag_string then VString (text ())
            else if tag = Edn_wire.tag_symbol then VSymbol (text ())
            else if tag = Edn_wire.tag_keyword then VKeyword (text ())
            else if tag = Edn_wire.tag_list then VList (elements depth)
            else if tag = Edn_wire.tag_vector then VVector (elements depth)
            else if tag = Edn_wire.tag_map then begin
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
            end
            else if tag = Edn_wire.tag_tagged then begin
              let name = text () in
              let v = value (depth + 1) in
              Effect.perform (Tag (name, v))
            end
            else if tag = Edn_wire.tag_meta then begin
              let m = value (depth + 1) in
              let v = value (depth + 1) in
              Effect.perform (Meta (m, v))
            end
            else failf "unknown tag byte 0x%02x" tag
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
