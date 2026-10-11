let magic = "EDNB"
let version = 1

type tag =
  | Nil
  | False
  | True
  | Number
  | String
  | List
  | Vector
  | Map
  | Symbol
  | Keyword
  | Tagged
  | Meta

let to_byte = function
  | Nil -> 0x00
  | False -> 0x01
  | True -> 0x02
  | Number -> 0x03
  | String -> 0x04
  | List -> 0x05
  | Vector -> 0x06
  | Map -> 0x07
  | Symbol -> 0x08
  | Keyword -> 0x09
  | Tagged -> 0x0A
  | Meta -> 0x0B

let of_byte = function
  | 0x00 -> Some Nil
  | 0x01 -> Some False
  | 0x02 -> Some True
  | 0x03 -> Some Number
  | 0x04 -> Some String
  | 0x05 -> Some List
  | 0x06 -> Some Vector
  | 0x07 -> Some Map
  | 0x08 -> Some Symbol
  | 0x09 -> Some Keyword
  | 0x0A -> Some Tagged
  | 0x0B -> Some Meta
  | _ -> None

let rec add_varint b n =
  if n < 0 then invalid_arg "Edn_wire.add_varint"
  else if n < 0x80 then Buffer.add_uint8 b n
  else begin
    Buffer.add_uint8 b (n land 0x7f lor 0x80);
    add_varint b (n lsr 7)
  end
