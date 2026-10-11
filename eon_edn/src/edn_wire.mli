(** Wire constants and primitives of the default binary format, shared by
    {!Edn_binary}'s encoder and decoder.

    A document is the {!magic} bytes, one {!version} byte, then a single
    value. Every value starts with one tag byte (the [tag_*] constants);
    lengths and counts are unsigned LEB128 varints; numbers are IEEE-754
    float64, little-endian. *)

val magic : string
(** ["EDNB"]. *)

val version : int
(** Format version, written as one byte. Starts at [1]. *)

val tag_nil : int
val tag_false : int
val tag_true : int
val tag_number : int
val tag_string : int
val tag_list : int
val tag_vector : int
val tag_map : int
val tag_symbol : int
val tag_keyword : int
val tag_tagged : int
val tag_meta : int

val add_varint : Buffer.t -> int -> unit
(** Appends a non-negative int as an unsigned LEB128 varint. Raises
    [Invalid_argument] on a negative int. *)
