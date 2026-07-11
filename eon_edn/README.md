# eon-edn

A minimal, extensible [EDN](https://github.com/edn-format/edn) reader for OCaml 5, built on algebraic effects.

## What it is

`eon-edn` parses EDN — the data format Clojure reads and writes — into a
plain, closed variant tree (`Eon_edn.Edn_effects.value`). It knows nothing
about `eon-ecs` or `eon-engine`; it's a standalone package with one job.
`eon-engine`'s [prefab loader](../docs/design/prefab_system_design.md) is
the first consumer, but the parser has no dependency in that direction —
you can use `eon-edn` on its own for config files, save data, or anything
else you'd reach for a small structured-data format for.

Primitives, strings, symbols, keywords, lists `()`, vectors `[]`, maps
`{}`, tagged values (`#tag ...`), and metadata (`^meta ...`) are all
supported. Getting from the generic `value` tree to a real OCaml type (a
config record, a component) is a few lines of ordinary pattern matching
that you write once per type — see the worked example below.

## Why algebraic effects

Most EDN-shaped readers you'll find are hand-rolled recursive-descent
parsers threading a "current position" or a mutable cursor through every
function. That works, but the moment you need to make one part of the
grammar behave differently — resolve a `#tag`, reject an unknown one, log
what you see — you're back in the same function, adding a parameter or a
callback that every other call site now has to thread through too.

Algebraic effects split those concerns cleanly. The reader (`Edn_parser`)
performs `Peek`/`Read`/`Fail` to walk the input, and separately performs
`Tag`/`Meta` whenever it hits `#tag ...` or `^meta ...` — it doesn't
resolve either one itself. Handling is a separate, composable layer
(`Edn_middleware`) that you attach *outside* the reader, with zero changes
to the parsing code:

```ocaml
(* plain data — no handler needed *)
let v = Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value {|{:name "Crab"}|}

(* tagged data — same reader, wrapped by a middleware chain *)
let v =
  Eon_edn.Edn_middleware.run_with_middleware
    ~handlers:Eon_edn.Edn_middleware.[ log_tags; strict_tags [ "uuid" ] ]
    (fun () -> Eon_edn.Edn_parser.value ())
    {|#uuid "abc"|}
```

Each middleware handler can fully resolve an effect or forward it to the
next one — the reader itself never needs to know how many handlers are
stacked on top, or in what order. That's the part effects genuinely buy
you here: extension without threading, and a reader that stays readable
because it only ever talks about grammar, never about policy.

## Quick start

```ocaml
let v =
  Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value
    {|{:name "Crab" :position [1 2] :alive true}|}
in
match v with
| Eon_edn.Edn_effects.VMap _ -> print_endline "parsed a map"
| _ -> assert false
```

`Eon_edn.Edn_parser.run` drives the reader over an input string and
returns the parsed `Eon_edn.Edn_effects.value`. This is enough for plain
EDN. Tagged values (`#tag ...`) and metadata (`^meta ...`) need the
middleware layer — see below.

## Core concepts

### The value type

`Eon_edn.Edn_effects.value` is the whole AST — a plain, closed variant, no
abstract types to work around:

```ocaml
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
```

Pattern-match on it directly — there's no accessor API to learn.

### The reader

`Eon_edn.Edn_parser.value` is the grammar entry point;
`Eon_edn.Edn_parser.run` supplies the low-level effects (`Peek`/`Read`/`Fail`)
that drive it over a string. `run` deliberately does **not** handle `Tag`
or `Meta` — parsing a document containing `#tag ...` or `^meta ...` via
`run` alone raises an unhandled-effect error. That's intentional: tag/meta
resolution is a separate, composable concern, not baked into the reader.

### Tags and middleware

A tagged value (`#eon/vec2 [1 2]`) performs `Tag` with `(tag_name, value)`.
Drive the parser with `Eon_edn.Edn_middleware.run_with_middleware` instead
of plain `run` to resolve it:

```ocaml
let v =
  Eon_edn.Edn_middleware.run_with_middleware
    (fun () -> Eon_edn.Edn_parser.value ())
    {|#uuid "abc"|}
(* v = VTagged ("uuid", VString "abc") — no handler registered for "uuid",
   so it falls back to wrapping the tag name and value as-is *)
```

Register a handler to transform the tagged value instead of leaving it
wrapped:

```ocaml
let () =
  Eon_edn.Edn_middleware.register_tag_handler "uuid" (fun _ v ->
      match v with
      | Eon_edn.Edn_effects.VString s ->
          Eon_edn.Edn_effects.VTagged ("uuid", VString (String.uppercase_ascii s))
      | v -> v)

let v =
  Eon_edn.Edn_middleware.run_with_middleware
    (fun () -> Eon_edn.Edn_parser.value ())
    {|#uuid "abc"|}
(* v = VTagged ("uuid", VString "ABC") *)
```

### Composing middleware

`Eon_edn.Edn_middleware.run_with_middleware`'s `?handlers` takes a
`Eon_edn.Edn_middleware.handler` list. Each handler can fully resolve a
tag or forward it (`None`) to the next one — either another handler in
the list, or `Eon_edn.Edn_middleware.default_handler` (the registry
lookup above), which always sits outermost. Two ready-made handlers:

- `Eon_edn.Edn_middleware.log_tags` — logs every tag, then forwards.
- `Eon_edn.Edn_middleware.strict_tags` — rejects any tag not in an
  allow-list; allowed tags forward.

```ocaml
let v =
  Eon_edn.Edn_middleware.run_with_middleware
    ~handlers:Eon_edn.Edn_middleware.[ log_tags; strict_tags [ "uuid" ] ]
    (fun () -> Eon_edn.Edn_parser.value ())
    {|#uuid "abc"|}
in
ignore v
```

Refusal order runs from the **last** element of `handlers` (nearest the
reader, first crack at each effect) to the **first** (nearest
`default_handler`, last crack among the middleware) — in the example
above, `strict_tags` is asked before `log_tags`. Writing a custom handler
follows the same shape: match on `Eon_edn.Edn_effects.Tag`, return `Some`
to terminate the effect or `None` to forward it.

## Worked example: loading a config file into a typed record

Everything above stops at `Eon_edn.Edn_effects.value` — a generic tree.
Getting from there to a real OCaml type (a config record, a component, a
save file) isn't part of `eon-edn` itself; it's a few lines of ordinary
pattern matching that you write once per type. If you're used to
schema-driven or reflection-based (de)serialization from other languages,
this is the part with no equivalent — there's no annotation, no code
generation, no reflection. You write a small function, it's plain code,
you can step through it in a debugger like anything else.

Say you want this EDN file:

```clojure
{:name "My Game"
 :width 1920
 :height 1080
 :fullscreen false
 :volume 0.8}
```

to become this type:

```ocaml
type config = {
  name : string;
  width : int;
  height : int;
  fullscreen : bool;
  volume : float;
}
```

First, small helpers — one to look up a keyword in a map, one per scalar
shape you expect. Both fail loudly (raise) rather than silently
defaulting, so a config file with a missing or wrong-typed field is
caught at load time, not three functions later as a mysterious `0`:

```ocaml
open Eon_edn.Edn_effects

let field kvs name =
  match List.assoc_opt (VKeyword name) kvs with
  | Some v -> v
  | None -> failwith (Printf.sprintf "config: missing field %S" name)

let as_string = function VString s -> s | _ -> failwith "config: expected a string"
let as_int = function VNumber n -> int_of_float n | _ -> failwith "config: expected a number"
let as_bool = function VBool b -> b | _ -> failwith "config: expected a boolean"
let as_float = function VNumber n -> n | _ -> failwith "config: expected a number"
```

Then the conversion itself — this is the part that's genuinely "yours":

```ocaml
let config_of_value = function
  | VMap kvs ->
      { name = as_string (field kvs "name")
      ; width = as_int (field kvs "width")
      ; height = as_int (field kvs "height")
      ; fullscreen = as_bool (field kvs "fullscreen")
      ; volume = as_float (field kvs "volume")
      }
  | _ -> failwith "config: expected a top-level map"
```

And finally, reading it from an actual file — `Eon_edn.Edn_parser.run`
only needs the file's contents as a string, so this is just an ordinary
`In_channel` read followed by the conversion above:

```ocaml
let load_config path =
  let contents = In_channel.with_open_bin path In_channel.input_all in
  Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value contents
  |> config_of_value
```

```ocaml
let cfg = load_config "game.edn" in
Printf.printf "%s: %dx%d\n" cfg.name cfg.width cfg.height
```

That's the whole pattern, and it's the same shape regardless of how
complex the type gets: one small `as_*`/`field` toolkit, one `_of_value`
function per type, composed by hand for nested types (a config with a
sub-record just calls another `_of_value` function on the sub-map). No
macro, no deriving, no build-time codegen step — the tradeoff for that is
exactly this: you write the glue, but the glue is short, obvious, and
entirely under your control.

## Build and test

Use `just` from the repo root:

```sh
just build
just run-tests
just test eon_edn/test/test_main.exe
just edn-bench edn_parser
```

## API reference

Full odoc reference: `just open-docs`, then browse to `eon-edn`. The
composition root is `eon_edn/eon_edn.ml`; the public contract is
`eon_edn/eon_edn.mli`.
