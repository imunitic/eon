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

let log_tags : handler = fun next ->
  let open Effect.Deep in
  let effc : type a. a Effect.t -> ((a, _) continuation -> _) option =
    fun eff ->
      match eff with
      | Tag (t, _) -> Printf.printf "[tag] #%s\n" t; None
      | _ -> None
  in
  match_with next () { retc = (fun v -> v); exnc = (fun e -> raise e); effc }

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
