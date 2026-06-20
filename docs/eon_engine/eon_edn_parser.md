# 🧠 EDN Parser Library (Algebraic Effects Version)

> **Syntax note:** This document uses the OCaml 5.0/5.1 effect declaration
> syntax (`effect Foo : type`). On OCaml 5.2+ (our baseline is 5.4) the
> correct form is a GADT extension:
> `type _ Effect.t += Peek : char option Effect.t`. The handler pattern
> `| effect Foo k ->` becomes `Effect.Deep.match_with` / `Effect.Deep.try_with`.
> The code below is a design sketch — adapt the declarations before
> compiling.

This document defines a minimal **EDN parser library written in OCaml 5.x** using **algebraic effects**.  
It’s designed for loading **prefabs**, **configs**, and **modding data** in the **Eon ECS** or **Eon Engine** project.

---

## 📂 Directory Structure

```
edn/
├── dune
├── edn_effects.ml
├── edn_parser.ml
├── edn_middleware.ml
└── main.ml
```

---

## ⚙️ Dune Configuration

```lisp
(library
 (name edn)
 (public_name edn)
 (modules edn_effects edn_parser edn_middleware))

(executable
 (name main)
 (modules main)
 (libraries edn))
```

---

## 🧩 Module: edn_effects.ml

```ocaml
(** Core effects and EDN AST types *)

effect Peek  : char option
effect Read  : char
effect Fail  : string -> 'a
effect Tag   : string * value -> value
effect Meta  : value * value -> value

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

let failf fmt = Printf.ksprintf (fun msg -> perform (Fail msg)) fmt
```

---

## 🧠 Module: edn_parser.ml

```ocaml
open Edn_effects

let peek () = perform Peek
let read () = perform Read

let rec skip_ws () =
  match peek () with
  | Some (' ' | '\t' | '\n' | ',') -> ignore (read ()); skip_ws ()
  | _ -> ()

let expect c =
  match peek () with
  | Some x when x = c -> ignore (read ())
  | Some x -> failf "expected '%c' got '%c'" c x
  | None -> failf "unexpected end of input"

let take_while p =
  let b = Buffer.create 16 in
  let rec loop () =
    match peek () with
    | Some c when p c -> Buffer.add_char b c; ignore (read ()); loop ()
    | _ -> Buffer.contents b
  in
  loop ()

let rec value () =
  skip_ws ();
  match peek () with
  | None      -> failf "EOF"
  | Some '"'  -> string ()
  | Some '['  -> vector ()
  | Some '('  -> list ()
  | Some '{'  -> map ()
  | Some ':'  -> keyword ()
  | Some '^'  -> meta ()
  | Some '#'  -> tag ()
  | Some c when (c >= '0' && c <= '9') || c = '-' -> number ()
  | _         -> symbol ()

and string () =
  expect '"';
  let b = Buffer.create 16 in
  let rec loop () =
    match read () with
    | '"' -> VString (Buffer.contents b)
    | '\\' ->
        (match read () with
         | 'n' -> Buffer.add_char b '\n'
         | 't' -> Buffer.add_char b '\t'
         | '"' -> Buffer.add_char b '"'
         | c   -> Buffer.add_char b c);
        loop ()
    | c -> Buffer.add_char b c; loop ()
  in
  loop ()

and number () =
  let s = take_while (function '0'..'9' | '.' | '-' -> true | _ -> false) in
  try VNumber (float_of_string s)
  with _ -> failf "invalid number: %s" s

and symbol () =
  let s = take_while (fun c ->
      not (List.mem c [' '; '\t'; '\n'; ','; '('; ')'; '['; ']'; '{'; '}'])) in
  match s with
  | "nil"   -> VNil
  | "true"  -> VBool true
  | "false" -> VBool false
  | _       -> VSymbol s

and keyword () =
  ignore (read ());
  let s = take_while (fun c ->
      not (List.mem c [' '; '\t'; '\n'; ','; '('; ')'; '['; ']'; '{'; '}'])) in
  VKeyword s

and list () =
  expect '(';
  let rec loop acc =
    skip_ws ();
    match peek () with
    | Some ')' -> ignore (read ()); VList (List.rev acc)
    | None     -> failf "unterminated list"
    | _        -> let v = value () in loop (v :: acc)
  in
  loop []

and vector () =
  expect '[';
  let rec loop acc =
    skip_ws ();
    match peek () with
    | Some ']' -> ignore (read ()); VVector (List.rev acc)
    | None     -> failf "unterminated vector"
    | _        -> let v = value () in loop (v :: acc)
  in
  loop []

and map () =
  expect '{';
  let rec loop acc =
    skip_ws ();
    match peek () with
    | Some '}' -> ignore (read ()); VMap (List.rev acc)
    | None     -> failf "unterminated map"
    | _ ->
        let k = value () in skip_ws ();
        let v = value () in loop ((k,v)::acc)
  in
  loop []

and tag () =
  ignore (read ());
  let tag = take_while (fun c -> not (List.mem c [' '; '\n'])) in
  skip_ws ();
  let v = value () in
  perform (Tag (tag, v))

and meta () =
  ignore (read ());
  skip_ws ();
  let m = value () in
  skip_ws ();
  let v = value () in
  perform (Meta (m, v))

let run parser input handle_tag handle_meta =
  let pos = ref 0 and len = String.length input in
  let rec exec thunk =
    match thunk () with
    | v -> v
    | effect Peek k ->
        continue k (if !pos < len then Some input.[!pos] else None) |> exec
    | effect Read k ->
        let c =
          if !pos < len then (let c = input.[!pos] in incr pos; c)
          else failwith "EOF"
        in
        continue k c |> exec
    | effect (Tag (t,v)) k -> continue k (handle_tag t v) |> exec
    | effect (Meta (m,v)) k -> continue k (handle_meta m v) |> exec
    | effect (Fail msg) _ -> failwith msg
  in
  exec parser
```

---

## 🧱 Module: edn_middleware.ml

```ocaml
open Edn_effects
open Edn_parser

type tag_handler = string -> value -> value
type meta_handler = value -> value -> value

let tag_registry : (string, tag_handler) Hashtbl.t = Hashtbl.create 16

let register_tag_handler name fn =
  Hashtbl.replace tag_registry name fn

let find_tag name =
  match Hashtbl.find_opt tag_registry name with
  | Some fn -> fn
  | None -> (fun _ v -> VTagged (name, v))

let default_meta m v = VMeta (m, v)

type 'a handler = (unit -> 'a) -> 'a
let compose a b = fun thunk -> a (fun () -> b thunk)

let log_tags : value handler = fun next ->
  match next () with
  | effect (Tag (t,v)) k ->
      Printf.printf "[tag] #%s\n" t;
      continue k (VTagged (t,v)) |> next
  | v -> v

let strict_tags allowed : value handler = fun next ->
  match next () with
  | effect (Tag (t,v)) k ->
      if List.mem t allowed then continue k (VTagged (t,v)) |> next
      else failwith ("Unknown tag: #" ^ t)
  | v -> v

let run_with_middleware ?(handlers=[]) parser input =
  let tag_handler t v = (find_tag t) t v
  and meta_handler = default_meta in
  let base = fun () -> run parser input tag_handler meta_handler in
  List.fold_right compose handlers (fun () -> base ()) ()
```

---

## 🚀 Example: main.ml

```ocaml
open Edn_effects
open Edn_parser
open Edn_middleware

let () =
  register_tag_handler "uuid" (fun _ (VString s) ->
      VTagged ("uuid", VString (String.uppercase_ascii s)));

  let input = {|
    ^:foo {:id #uuid "abc"
           :name "Crab"
           :position [12.5 7.8]
           :stats {:hp 100 :attack 15}}
  |} in

  let parsed =
    run_with_middleware
      ~handlers:[log_tags; strict_tags ["uuid"; "inst"]]
      (fun () -> value ())
      input
  in

  let rec interpret v =
    match v with
    | VMap kvs ->
        List.iter (fun (k,v) ->
          match k with
          | VKeyword "id" ->
              (match v with
               | VTagged ("uuid", VString id) ->
                   Printf.printf "Entity UUID=%s\n" id
               | _ -> ())
          | VKeyword "name" ->
              (match v with
               | VString n -> Printf.printf "Name=%s\n" n
               | _ -> ())
          | VKeyword "position" ->
              (match v with
               | VVector [VNumber x; VNumber y] ->
                   Printf.printf "Position=(%.1f, %.1f)\n" x y
               | _ -> ())
          | VKeyword "stats" ->
              (match v with
               | VMap stats ->
                   List.iter (fun (sk, sv) ->
                     match (sk, sv) with
                     | (VKeyword "hp", VNumber hp) ->
                         Printf.printf "HP=%g\n" hp
                     | (VKeyword "attack", VNumber atk) ->
                         Printf.printf "ATK=%g\n" atk
                     | _ -> ()) stats
               | _ -> ())
          | _ -> ())
          kvs
    | VMeta (_, v) -> interpret v
    | _ -> ()
  in

  print_endline "\n--- Interpreting entity ---";
  interpret parsed
```
