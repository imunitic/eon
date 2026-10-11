let magic = "EDNB"
let version = 1

let tag_nil = 0x00
let tag_false = 0x01
let tag_true = 0x02
let tag_number = 0x03
let tag_string = 0x04
let tag_list = 0x05
let tag_vector = 0x06
let tag_map = 0x07
let tag_symbol = 0x08
let tag_keyword = 0x09
let tag_tagged = 0x0A
let tag_meta = 0x0B

let rec add_varint b n =
  if n < 0 then invalid_arg "Edn_wire.add_varint"
  else if n < 0x80 then Buffer.add_uint8 b n
  else begin
    Buffer.add_uint8 b (n land 0x7f lor 0x80);
    add_varint b (n lsr 7)
  end
