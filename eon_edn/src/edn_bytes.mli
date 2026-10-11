(** An encoded EDN document.

    Not text: never hand one to {!Edn_parser}. The representation is a plain
    string — reading one costs nothing through the coercion [(b :> string)] —
    but values can only be built through {!of_string}, so encoded binary and
    EDN text cannot be swapped by accident. *)

type t = private string

val of_string : string -> t
(** Unchecked identity. A decoder validates its input; this does not. *)
