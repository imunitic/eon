(** Wire constants and primitives of the default binary format, shared by
    {!Edn_binary}'s encoder and decoder.

    A document is the {!magic} bytes, one {!version} byte, then a single
    value. Every value starts with one {!tag} byte; lengths and counts are
    unsigned LEB128 varints; numbers are IEEE-754 float64, little-endian. *)

val magic : string
(** ["EDNB"]. *)

val version : int
(** Format version, written as one byte. Starts at [1]. *)

(** The byte that starts every value. *)
type tag =
  | Nil  (** [0x00] *)
  | False  (** [0x01] *)
  | True  (** [0x02] *)
  | Number  (** [0x03] — float64 follows *)
  | String  (** [0x04] — length, UTF-8 bytes *)
  | List  (** [0x05] — count, elements *)
  | Vector  (** [0x06] — count, elements *)
  | Map  (** [0x07] — pair count, then key and value per pair *)
  | Symbol  (** [0x08] — length, bytes *)
  | Keyword  (** [0x09] — length, bytes *)
  | Tagged  (** [0x0A] — tag name (length, bytes), then the value *)
  | Meta  (** [0x0B] — meta value, then the value *)

val to_byte : tag -> int

val of_byte : int -> tag option
(** [None] for a byte that is not a tag. [of_byte (to_byte t) = Some t]. *)

val add_varint : Buffer.t -> int -> unit
(** Appends a non-negative int as an unsigned LEB128 varint. Raises
    [Invalid_argument] on a negative int. *)
