(** Core EDN AST type and the algebraic effects the reader/middleware are
    built on. *)

(** A parsed EDN value. *)
type value =
  | VNil
  | VBool of bool
  | VNumber of float
  | VString of string
  | VList of value list
  | VVector of value list
  | VMap of (value * value) list
  | VSymbol of string
  | VKeyword of string
  | VTagged of string * value
  | VMeta of value * value

type _ Effect.t +=
  | Peek : char option Effect.t
      (** Look at the next input character without consuming it. *)
  | Read : char Effect.t
      (** Consume and return the next input character. *)
  | Fail : string -> 'a Effect.t
      (** Abort parsing with an error message. *)
  | Tag : (string * value) -> value Effect.t
      (** [#tag value] encountered — payload is [(tag_name, value)]. *)
  | Meta : (value * value) -> value Effect.t
      (** [^meta value] encountered — payload is [(meta, value)]. *)

val failf : ('a, unit, string, 'b) format4 -> 'a
(** [failf fmt ...] performs {!Fail} with the formatted message. *)
