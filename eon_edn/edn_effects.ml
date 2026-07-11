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
  | Read : char Effect.t
  | Fail : string -> 'a Effect.t
  | Tag : (string * value) -> value Effect.t
  | Meta : (value * value) -> value Effect.t

let failf fmt = Printf.ksprintf (fun msg -> Effect.perform (Fail msg)) fmt
