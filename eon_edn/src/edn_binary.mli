(** The default binary codec for {!Edn_effects.value}.

    Handwritten and specialised to the closed value ADT. The format keeps
    AST semantics, not source text: list vs vector and string vs keyword stay
    distinct, map entry order is preserved, floats are preserved
    bit-for-bit. See {!Edn_wire} for the byte layout. *)

type format
(** Identity of this wire format; shared by every encoder and decoder of it,
    whatever their {!LIMITS}. *)

(** Bounds enforced by the decoder, because the input may be hostile (mod
    files, network data). *)
module type LIMITS = sig
  val max_size : int
  (** Largest accepted document, in bytes; checked once before decoding. *)

  val max_depth : int
  (** Deepest accepted nesting. The top-level value is at depth 0 and every
      container, tagged or meta value puts its contents one level deeper. *)
end

module type S = sig
  module Encode : Edn_codec.ENCODE with type format = format
  (** Total; ignores limits. *)

  module Decode : Edn_codec.DECODE with type format = format
  (** Reads the {!Edn_bytes.t} directly. Performs {!Edn_effects.Tag} and
      {!Edn_effects.Meta} for tagged and meta nodes — it must run inside
      {!Edn_middleware.with_middleware} — and raises [Failure] on malformed
      or over-limit input: bad magic or version, an unknown tag byte, a
      length or count larger than the remaining input, truncated input,
      trailing bytes after the value, or a {!LIMITS} violation. *)
end

module Make (_ : LIMITS) : S
(** A codec whose decoder enforces the given limits. The encoder and decoder
    pair by {!format} alone: a limits mismatch between them is the caller's
    responsibility. *)

module Default_limits : LIMITS
(** [max_size] 16 MiB, [max_depth] 256. *)

include S
(** [Make (Default_limits)]. *)
