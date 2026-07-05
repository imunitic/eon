exception Unknown_namespace of string

type t = (string, World.rw World.t) Hashtbl.t

let create () = Hashtbl.create 8

let attach ns name world = Hashtbl.replace ns name world

let named name ns =
  match Hashtbl.find_opt ns name with
  | Some w -> w
  | None   -> raise (Unknown_namespace name)
