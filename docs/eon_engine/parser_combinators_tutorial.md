# 🧩 Understanding Parser Combinators (OCaml / Angstrom Edition)

This guide explains **parser combinators** like you’re five years old (but smart).  
It will help you understand **Angstrom** and similar libraries by *building up intuition from scratch*.

---

## 🧠 1. What is a parser?

A **parser** is a thing that *takes a string and returns meaning*.

Example:  
> Input: `"42"`  
> Meaning: the number 42

So conceptually:
```
parser : string -> result
```

---

## 🍬 2. What’s a combinator?

A **combinator** is just a function that *combines smaller things into bigger things*.

So a **parser combinator** is a small parser function that can be **combined** with others to make more complex parsers.

---

## 🪄 3. Let’s make our own toy parser type

We’ll build a **super tiny version** of what Angstrom does, using plain OCaml:

```ocaml
type 'a parser = string -> int -> ('a * int) option
```

- `'a` — what it returns (like `int`, `char`, `string`, etc.)
- `string` — the input text
- `int` — the current position (where we are in the string)
- returns either `Some (result, new_pos)` or `None` if parsing failed.

So, for example:

```ocaml
let parse_char c : char parser =
 fun input pos ->
   if pos < String.length input && input.[pos] = c then
     Some (c, pos + 1)
   else
     None
```

This checks one character — if it matches, move forward one step.

---

## 🪆 4. Tiny helper to run our parser

```ocaml
let run p input =
  match p input 0 with
  | Some (v, pos) -> Printf.sprintf "Parsed: %C, next pos: %d" v pos
  | None -> "Parse failed"
```

Now:
```ocaml
# run (parse_char 'a') "abc";;
- : string = "Parsed: a, next pos: 1"
```

---

## 🧩 5. Combine parsers: sequencing (`and_then`)

We can chain two parsers: first one, then another.

```ocaml
let and_then p1 p2 =
 fun input pos ->
   match p1 input pos with
   | Some (r1, pos') ->
       (match p2 input pos' with
        | Some (r2, pos'') -> Some ((r1, r2), pos'')
        | None -> None)
   | None -> None
```

Now we can do:

```ocaml
let parse_a_then_b = and_then (parse_char 'a') (parse_char 'b')
# run parse_a_then_b "abc";;
- : string = "Parsed: (a,b), next pos: 2"
```

🎉 We just made a **parser combinator**!

---

## 🔁 6. Choice combinator (`or_else`)

We also want to try one parser or another.

```ocaml
let or_else p1 p2 =
 fun input pos ->
   match p1 input pos with
   | Some _ as ok -> ok
   | None -> p2 input pos
```

```ocaml
let parse_a_or_b = or_else (parse_char 'a') (parse_char 'b')
# run parse_a_or_b "banana";;
(* Parsed: b, next pos: 1 *)
```

---

## 🧃 7. Mapping results (`map`)

Often we want to transform the result.  
Example: if we parse `'1'`, we want `1` (int), not `'1'`.

```ocaml
let map f p =
 fun input pos ->
   match p input pos with
   | Some (v, pos') -> Some (f v, pos')
   | None -> None
```

Example:
```ocaml
let digit_to_int c = int_of_char c - int_of_char '0'
let parse_digit = map digit_to_int (parse_char '3')
# run parse_digit "345";;
(* Parsed: 3, next pos: 1 *)
```

---

## 🧱 8. Repetition (`many`)

To parse several things in a row, like digits `"1234"`:

```ocaml
let rec many p =
 fun input pos ->
   match p input pos with
   | Some (v, pos') ->
       (match many p input pos' with
        | Some (vs, pos'') -> Some (v :: vs, pos'')
        | None -> Some ([v], pos'))
   | None -> Some ([], pos)
```

This never fails — it just collects as many matches as possible.

---

## 🌈 9. Combine everything: parsing a number

```ocaml
let is_digit c = c >= '0' && c <= '9'
let satisfy pred =
 fun input pos ->
   if pos < String.length input && pred input.[pos] then
     Some (input.[pos], pos + 1)
   else None

let digit = satisfy is_digit
let digits = many digit
let number = map (fun cs ->
  int_of_string (String.of_seq (List.to_seq cs))) digits

# run number "1234abc";;
(* Parsed: 1234, next pos: 4 *)
```

🎯 We’ve built a working number parser from scratch!

---

## ⚡️ 10. Now… Angstrom

Now that you understand the pattern, Angstrom just provides all of these as ready-made functions, but with much better performance and composability.

### Example in Angstrom:
```ocaml
open Angstrom

let number =
  take_while1 (function '0'..'9' -> true | _ -> false)
  >>| int_of_string

let pair =
  char '(' *> number <* char ',' >>= fun x ->
  number <* char ')' >>| fun y ->
  (x, y)
```

The operators mean:
| Operator | Meaning |
|-----------|----------|
| `*>` | run left, ignore its result, then right |
| `<*` | run left, then right, but keep left result |
| `>>=` | "and then" — like `and_then` |
| `>>|` | map result (like `map`) |

Example:
```ocaml
parse_string ~consume:All pair "(12,34)";;
- : (int * int, string) result = Ok (12, 34)
```

---

## 🧠 Summary — The Core Ideas

| Concept | OCaml Function | Meaning |
|----------|----------------|----------|
| `map` | `>>|` | Transform result |
| `and_then` | `>>=` | Sequence parsers |
| `or_else` | `<|>` | Try one, then another |
| `*>` / `<*` | sequence but ignore result |
| `many`, `many1` | loops | Repeat |
| `satisfy`, `char`, `string` | primitives | Base building blocks |

Parser combinators are **just little LEGO bricks** that you click together.  
Each one eats part of the input, and returns something new.

---

## 🧰 Key Takeaway

> A parser combinator library is like a **tiny functional programming language** for describing text.

You start with small “word” parsers, combine them into “sentences,”  
and end up describing an entire “grammar” — all using normal OCaml functions.

---

## 🚀 Next Step

Now that you’ve built intuition, you can explore:
- [Angstrom documentation](https://github.com/inhabitedtype/angstrom)
- [Learn OCaml parser combinators by examples (RWO)](https://dev.realworldocaml.org/parsing.html)
- Try building your own `.ini` or `.toml` parser — you already know enough!

---

**💡 TL;DR:**  
Parser combinators are functions that:
1. Read input step by step,  
2. Return structured results,  
3. Can be composed like LEGO.

Once you see them that way, Angstrom will feel like second nature.

