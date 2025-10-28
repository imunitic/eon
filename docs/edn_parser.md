# 🧩 Eon EDN Parser — Angstrom Implementation

A simple, extensible **EDN parser in OCaml** using the `Angstrom` combinator library.  
Supports:
- **Primitives:** numbers, booleans, strings, symbols, keywords  
- **Collections:** lists `()`, vectors `[]`, maps `{}`, sets `#{}`  
- **Tagged values:** `#eon/vec2 [1 2]`  
- **Metadata:** `^:meta {:a 1}`

This parser is minimal, self-contained, and designed for **Eon prefab definitions** —  
data-first, extensible, and modder-friendly.

---

## ⚙️ 1. Dependencies

Add to your `dune` or install manually:

```bash
opam install angstrom
```

---

## 🧱 2. Data Type (AST)

```ocaml
type t =
  | Int of int
  | Float of float
  | Bool of bool
  | String of string
  | Keyword of string
  | Symbol of string
  | List of t list
  | Vector of t list
  | Map of (t * t) list
  | Set of t list
  | Tagged of string * t
  | Meta of (t * t) list * t
```

---

## 🧠 3. The Parser

```ocaml
open Angstrom

(* --- Whitespace and utilities --- *)
let ws = skip_while (function ' ' | '\n' | '\t' | ',' -> true | _ -> false)
let lex p = p <* ws

(* --- Basic literals --- *)
let bool =
  choice
    [ string "true"  *> return (Bool true)
    ; string "false" *> return (Bool false)
    ]

let number =
  let num = take_while1 (function
      | '0'..'9' | '.' | '-' | '+' | 'e' | 'E' -> true
      | _ -> false)
  in
  num >>| fun s ->
  if String.contains s '.' || String.contains s 'e' || String.contains s 'E'
  then Float (float_of_string s)
  else Int (int_of_string s)

let escaped_char =
  char '\\' *> choice
    [ char 'n' *> return '\n'
    ; char '"' *> return '"'
    ; any_char >>| fun c -> c
    ]

let string_lit =
  char '"' *> many (escaped_char <|> satisfy ((<>) '"')) <* char '"'
  >>| fun chars -> String (String.of_seq (List.to_seq chars))

let keyword =
  char ':' *> take_while1 (function
      | ' ' | '\n' | '\t' | ')' | ']' | '}' -> false | _ -> true)
  >>| fun s -> Keyword s

let symbol =
  take_while1 (function
      | ' ' | '\n' | '\t' | '(' | ')' | '[' | ']' | '{' | '}' -> false
      | _ -> true)
  >>| fun s -> Symbol s
```

---

### Recursive value parser

```ocaml
let rec value () =
  ws *> choice
    [ bool
    ; number
    ; string_lit
    ; keyword
    ; list
    ; vector
    ; map
    ; set
    ; tagged
    ; metadata
    ; symbol
    ]

and list =
  char '(' *> ws *> many (value ()) <* char ')' >>| fun xs -> List xs

and vector =
  char '[' *> ws *> many (value ()) <* char ']' >>| fun xs -> Vector xs

and map =
  char '{' *> ws *>
  many ((value ()) >>= fun k -> ws *> (value ()) >>| fun v -> (k,v))
  <* char '}' >>| fun xs -> Map xs

and set =
  string "#{" *> ws *> many (value ()) <* char '}' >>| fun xs -> Set xs

and tagged =
  char '#' *> take_while1 (function
      | ' ' | '\n' | '\t' | '{' | '[' | '(' -> false
      | _ -> true)
  >>= fun tag ->
  ws *> (value ()) >>| fun v -> Tagged (tag, v)

and metadata =
  char '^' *> ws *> (value ()) >>= fun meta ->
  ws *> (value ()) >>| fun v ->
  let meta_map =
    match meta with
    | Keyword k -> [Keyword k, Bool true]
    | Map m -> m
    | _ -> failwith "Invalid metadata"
  in
  Meta (meta_map, v)
```

---

### Entry point

```ocaml
let parse str =
  match parse_string ~consume:Consume.All (value ()) str with
  | Ok v -> v
  | Error msg -> failwith msg
```

---

## 🧩 4. Tagged Values

EDN tagged literals have syntax:

```clojure
#tag payload
```

Examples:
```clojure
#uuid "550e8400-e29b-41d4-a716-446655440000"
#eon/vec2 [10 20]
#eon/color {:r 1 :g 0 :b 0}
```

The parser produces:

```ocaml
Tagged ("eon/vec2", Vector [Int 10; Int 20])
```

Attach **custom logic** to tags via a registry:

```ocaml
module Tag = struct
  type handler = t -> t
  let registry : (string, handler) Hashtbl.t = Hashtbl.create 8

  let register name fn = Hashtbl.replace registry name fn
  let apply name v =
    match Hashtbl.find_opt registry name with
    | Some f -> f v
    | None -> Tagged (name, v)
end
```

Example handler:

```ocaml
Tag.register "eon/vec2" (function
  | Vector [Int x; Int y] -> Symbol (Printf.sprintf "Vec2(%d,%d)" x y)
  | _ -> failwith "Invalid vec2");
```

Parsing:
```clojure
{:pos #eon/vec2 [3 5]}
```

→ produces:
```ocaml
Map [Keyword "pos", Symbol "Vec2(3,5)"]
```

---

## 🧠 5. Metadata (`^meta form`)

Metadata attaches *non-semantic information* to any value:

```clojure
^:editor/visible {:id 1 :pos [3 5]}
^{:id 42 :doc "info"} :symbol
```

Parser output:

```ocaml
Meta ([Keyword "editor/visible", Bool true],
     Map [Keyword "id", Int 1; Keyword "pos", Vector [Int 3; Int 5]])
```

Strip metadata when needed:

```ocaml
let rec strip_meta = function
  | Meta (_, v) -> strip_meta v
  | List xs -> List (List.map strip_meta xs)
  | Vector xs -> Vector (List.map strip_meta xs)
  | Map kvs -> Map (List.map (fun (k,v) -> (k, strip_meta v)) kvs)
  | Set xs -> Set (List.map strip_meta xs)
  | Tagged (t, v) -> Tagged (t, strip_meta v)
  | x -> x
```

---

## 🧩 6. Example Usage

```ocaml
let example = "^{:editor/visible true}
               {:name \"Portal\"
                :components
                {:Transform #eon/vec2 [0 0]
                 :Renderable #eon/sprite {:id :portal}}}"

let ast = parse example
```

Resulting AST (simplified):

```ocaml
Meta (
  [Keyword "editor/visible", Bool true],
  Map [
    Keyword "name", String "Portal";
    Keyword "components",
      Map [
        Keyword "Transform", Tagged ("eon/vec2", Vector [Int 0; Int 0]);
        Keyword "Renderable", Tagged ("eon/sprite", Map [Keyword "id", Keyword "portal"])
      ]
  ]
)
```

---

## ✅ 7. Summary

| Feature | Example | AST Result |
|----------|----------|------------|
| **Set** | `#{1 2 3}` | `Set [Int 1; Int 2; Int 3]` |
| **Tagged** | `#eon/vec2 [1 2]` | `Tagged ("eon/vec2", Vector [...])` |
| **Metadata** | `^:foo {:a 1}` | `Meta ([Keyword "foo", Bool true], Map [...])` |
| **Map** | `{:a 1 :b 2}` | `Map [(Keyword "a", Int 1); (Keyword "b", Int 2)]` |

---

### ✨ Eon Philosophy Alignment

EDN is the perfect match for **Eon ECS**:

- **Data-first**: everything is just data.  
- **Extensible**: tag literals plug into engine logic naturally.  
- **Human-friendly**: modders can write prefabs by hand.  
- **Composable**: maps, vectors, sets, and metadata combine cleanly.

**In short:** EDN turns prefab files into structured, extensible data  
that feels like a natural extension of your ECS and Lisp-inspired design philosophy.
