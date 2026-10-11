(** Signatures for EDN value codecs.

    A codec is split into {!ENCODE} and {!DECODE} so a sender can depend only
    on the former and a receiver only on the latter. Each declares an
    abstract [format]; a consumer that needs both requires
    [DECODE with type format = ENCODE.format], which makes the compiler
    reject a pair that does not share a wire-format identity. The type has no
    runtime representation. It proves that both modules claim the same
    format, not that their implementations agree. *)

(** Turns a value into an encoded document. *)
module type ENCODE = sig
  type format

  val encode : Edn_effects.value -> Edn_bytes.t
  (** Total over {!Edn_effects.value}; performs no effects. [VTagged] and
      [VMeta] nodes are written as plain data. *)
end

(** Turns an encoded document back into a value. *)
module type DECODE = sig
  type format

  val decode : Edn_bytes.t -> Edn_effects.value
  (** Performs {!Edn_effects.Tag}/{!Edn_effects.Meta} for tagged and meta
      nodes, bottom-up as the parser does, so it must run inside
      {!Edn_middleware.with_middleware} (or an equivalent handler). Raises
      [Failure] on malformed or over-limit input. *)
end
