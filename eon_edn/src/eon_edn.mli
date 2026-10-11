(** Eon EDN public API.

    Standalone EDN reader built on OCaml 5 algebraic effects. Knows
    nothing about [eon-ecs] or [eon-engine] — just EDN syntax in, a
    generic {!Edn_effects.value} tree out.

    See the {{!page-index} tutorial} for a walkthrough of the reader and
    middleware composition. *)

module Edn_effects : sig
  (** Core EDN AST type and the algebraic effects the reader/middleware
      are built on. *)
  include module type of Edn_effects
end

module Edn_parser : sig
  (** EDN reader — parses a single {!Edn_effects.value} from a string. *)
  include module type of Edn_parser
end

module Edn_middleware : sig
  (** Composable resolution of tagged/meta values left unhandled by
      {!Edn_parser}. *)
  include module type of Edn_middleware
end

module Edn_bytes : sig
  (** An encoded EDN document — see the codec guide. *)
  include module type of Edn_bytes
end

module Edn_codec : sig
  (** Signatures for EDN value codecs. *)
  include module type of Edn_codec
end

module type ENCODE = Edn_codec.ENCODE
(** See {!Edn_codec.ENCODE}. *)

module type DECODE = Edn_codec.DECODE
(** See {!Edn_codec.DECODE}. *)

module Binary : sig
  (** The default binary codec. *)
  include module type of Edn_binary
end
