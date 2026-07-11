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
