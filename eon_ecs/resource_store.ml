module Type_id = struct
  type t = string
  let of_typename name = name
end

type packed = Pack : 'a * (unit -> string) -> packed

type t = (Type_id.t, packed) Hashtbl.t

let create () : t =
  Hashtbl.create 32

let add store key v = 
  Hashtbl.replace store key (Pack (v, fun () -> key))

let get store key = 
  match Hashtbl.find_opt store key with
  | Some (Pack (v, _)) -> Some (Obj.magic v)
  | None -> None

let remove store key =
  Hashtbl.remove store key

let clear store =
  Hashtbl.clear store

let list_keys store =
  Hashtbl.to_seq_keys store |> List.of_seq

let of_typename = Type_id.of_typename
