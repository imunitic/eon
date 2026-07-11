# 🧠 EDN Parser Library (Algebraic Effects Version)

## Status

**ACCEPTED**

---

This document defines a minimal **EDN parser library written in OCaml 5.x** using **algebraic effects**.  
It’s designed for loading **prefabs**, **configs**, and **modding data** in the **Eon ECS** or **Eon Engine** project.

---

## 📂 Directory Structure

```
eon_edn/
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
 (name eon_edn)
 (public_name eon-edn)
 (modules edn_effects edn_parser edn_middleware))

(executable
 (name main)
 (modules main)
 (libraries eon_edn))
```

---

## 🧩 Module: edn_effects.ml

```ocaml
(** Core effects and EDN AST types *)

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
```

`value` must be declared before the effect type — the `Tag`/`Meta` effects
refer to it as their payload/answer type.

---

## 🧠 Module: edn_parser.ml

```ocaml
open Edn_effects

let peek () = Effect.perform Peek
let read () = Effect.perform Read

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
  Effect.perform (Tag (tag, v))

and meta () =
  ignore (read ());
  skip_ws ();
  let m = value () in
  skip_ws ();
  let v = value () in
  Effect.perform (Meta (m, v))

(** Handles only the reader-level effects ([Peek]/[Read]/[Fail]).
    [Tag]/[Meta] are deliberately left unhandled here (the [effc] falls
    through to [None] for them) so they propagate to whatever handler
    wraps this call — see [Edn_middleware.run_with_middleware]. Bundling
    Tag/Meta resolution into this same handler would make it the innermost
    (and therefore first-priority) handler for those effects, permanently
    shadowing any outer middleware. *)
let run parser input =
  let pos = ref 0 and len = String.length input in
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff ->
      match eff with
      | Peek ->
          Some (fun k -> continue k (if !pos < len then Some input.[!pos] else None))
      | Read ->
          Some (fun k ->
            let c =
              if !pos < len then (let c = input.[!pos] in incr pos; c)
              else failwith "EOF"
            in
            continue k c)
      | Fail msg -> Some (fun k -> discontinue k (Failure msg))
      | _ -> None
  in
  match_with parser () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }
```

`Effect.Deep.match_with` is a *deep* handler — resumed computation stays
inside the same handler context automatically, so unlike the old `| effect
... k -> ... |> exec` pattern there's no need to manually loop/re-enter.

`run` no longer takes `handle_tag`/`handle_meta` callbacks. Earlier drafts
of this doc had `run` handle `Tag`/`Meta` directly (see the middleware
section below for why that was wrong) — annotating those callbacks
explicitly was needed then to work around a GADT-escape error, but the
right fix was to not have `run` touch `Tag`/`Meta` at all.

---

## 🧱 Module: edn_middleware.ml

```ocaml
open Edn_effects

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

type handler = (unit -> value) -> value

let compose (a : handler) (b : handler) : handler =
  fun thunk -> a (fun () -> b thunk)

(** The outermost, last-resort handler: resolves [Tag] via the
    [tag_registry] and [Meta] via [default_meta]. It must wrap *outside*
    every user middleware (see [run_with_middleware]) so a middleware
    handler always gets first refusal on an effect, forwarding (`None`)
    to let this handler compute the actual value. *)
let default_handler : handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff ->
      match eff with
      | Tag (t, v) -> Some (fun k -> continue k ((find_tag t) t v))
      | Meta (m, v) -> Some (fun k -> continue k (default_meta m v))
      | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

(** Logs every tag as a side effect, then forwards (`None`) so a later
    handler still resolves the actual value. *)
let log_tags : handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff ->
      match eff with
      | Tag (t, _) -> Printf.printf "[tag] #%s\n" t; None
      | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

(** Rejects any tag not in [allowed]; allowed tags are forwarded (`None`)
    so a later handler still resolves the actual value. *)
let strict_tags (allowed : string list) : handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff ->
      match eff with
      | Tag (t, _) ->
          if List.mem t allowed then None
          else Some (fun k -> discontinue k (Failure ("Unknown tag: #" ^ t)))
      | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

let identity : handler = fun next -> next ()

let run_with_middleware ?(handlers = []) parser input =
  let base () = Edn_parser.run parser input in
  let middleware_chain = List.fold_right compose handlers identity in
  default_handler (fun () -> middleware_chain base)
```

This is a real redesign, not just a syntax port — the original sketch had
`Edn_parser.run` resolve `Tag`/`Meta` directly via `handle_tag`/
`handle_meta` callbacks, with `run_with_middleware` supposedly layering
`log_tags`/`strict_tags` on top. That never worked, even conceptually:
`Effect.Deep`'s `effc` picks the *dynamically innermost* handler for an
effect, and since `run`'s own handler sat closest to the raw parser (it
wraps `parser` directly) and always fully handled `Tag`/`Meta` (`Some` in
every case, never `None`), it consumed every tag before any outer
middleware could see it. `log_tags`/`strict_tags` were dead code — proven
by actually running the old version: no `[tag] #...` line ever printed,
and `strict_tags` never rejected anything, regardless of list order.

The fix has two parts:

1. `Edn_parser.run` no longer touches `Tag`/`Meta` at all — its `effc`
   returns `None` for them, so they propagate out of the reader
   immediately. `run` dropped the `handle_tag`/`handle_meta` parameters
   entirely; that responsibility isn't the reader's to own.
2. Tag/Meta resolution moved to `default_handler`, which must be installed
   as the **outermost** wrapper — outside the whole middleware chain, not
   folded in as its seed. `identity` (a *frame-less* passthrough, installs
   no handler at all) is the correct fold seed instead; `default_handler`
   wraps the result of `middleware_chain base`, not the other way round.
3. `log_tags`/`strict_tags` must return `None` (not `Some`) when they
   don't need to terminate the effect, so it keeps propagating outward to
   whichever handler is next — either another middleware, or eventually
   `default_handler`.

With this, `~handlers:[log_tags; strict_tags [...]]` genuinely chains: a
tag effect hits `strict_tags` first (nearer the reader), which forwards if
allowed or rejects outright; if forwarded, `log_tags` observes and
forwards again; `default_handler` — now truly the last resort — resolves
the value via the registry. Verified below, including a case that proves
`strict_tags` actually rejects.

---

## 🚀 Example: main.ml

```ocaml
open Edn_effects
open Edn_middleware

let () =
  register_tag_handler "uuid" (fun _ v ->
      match v with
      | VString s -> VTagged ("uuid", VString (String.uppercase_ascii s))
      | _ -> v);

  let input = {|
    ^:foo {:id #uuid "abc"
           :name "Crab"
           :position [12.5 7.8]
           :stats {:hp 100 :attack 15}}
  |} in

  let parsed =
    run_with_middleware
      ~handlers:[log_tags; strict_tags ["uuid"; "inst"]]
      (fun () -> Edn_parser.value ())
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
  interpret parsed;

  print_endline "\n--- Rejecting an unlisted tag ---";
  (try
     let _ =
       run_with_middleware
         ~handlers:[log_tags; strict_tags ["inst"]]
         (fun () -> Edn_parser.value ())
         {| #uuid "xyz" |}
     in
     print_endline "did not raise (unexpected)"
   with Failure msg -> Printf.printf "rejected: %s\n" msg)
```

The tag handler is a full `match` rather than the old `fun _ (VString s) ->
...` — that was a partial pattern in a function argument (compiles with a
non-exhaustive-match warning, not an error, but worth cleaning up since
this is the doc's canonical example). The second block (`~handlers:[log_tags;
strict_tags ["inst"]]`, no `"uuid"` in the allowed list) exists specifically
to prove `strict_tags` actually fires now.

Actual output when run:

```
[tag] #uuid

--- Interpreting entity ---
Entity UUID=ABC
Name=Crab
Position=(12.5, 7.8)
HP=100
ATK=15

--- Rejecting an unlisted tag ---
rejected: Unknown tag: #uuid
```

`[tag] #uuid` now prints (from `log_tags`, forwarding correctly), the
value still resolves through the registry (`UUID=ABC`, uppercased — proof
`default_handler` ran too), and the second call is rejected by
`strict_tags` as expected.
