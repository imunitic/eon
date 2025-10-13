module Type_id = struct
  type t = string
  let of_typename name = name
end

type packed = Pack : 'a * (unit -> string) -> packed

type t = {
  services : (Type_id.t, packed) Hashtbl.t;
  data : packed Sparse_set.t;
}

let create () = {
  services = Hashtbl.create 16;
  data = Sparse_set.create ();
}

(* --- Services ------------------------------------------------------------- *)

let add_service store key value =
  Hashtbl.replace store.services key (Pack (value, fun () -> key))

let get_service store key =
  match Hashtbl.find_opt store.services key with
  | Some (Pack (v, _)) -> Some (Obj.magic v)
  | None -> None

let remove_service store key =
  Hashtbl.remove store.services key

let list_services store =
  Hashtbl.to_seq_keys store.services |> List.of_seq

(* --- Data ----------------------------------------------------------------- *)

let add_data store id value =
  let entity = Entity_id.make id 0 in
  Sparse_set.add store.data entity (Pack (value, fun () -> "data"))

let get_data store id =
  let entity = Entity_id.make id 0 in
  match Sparse_set.get store.data entity with
  | Some (Pack (v, _)) -> Some (Obj.magic v)
  | None -> None

let remove_data store id =
  let entity = Entity_id.make id 0 in
  Sparse_set.remove store.data entity

let iter_data f store =
  Sparse_set.iter (fun id (Pack (v, _)) -> f id (Obj.magic v)) store.data

let count_data store =
  Sparse_set.size store.data

let of_typename = Type_id.of_typename
