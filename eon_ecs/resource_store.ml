type packed = Pack : 'a * (unit -> string) -> packed

type t = {
  services : (int, packed) Hashtbl.t;
  data : packed Sparse_set.t;
  data_ids : (int, int) Hashtbl.t;
  mutable next_id : int;
}

let hash_key key =
  Hashtbl.hash key land Stdlib.max_int

let resolve_or_alloc store key =
  match Hashtbl.find_opt store.data_ids key with
  | Some id -> id
  | None ->
      let id = store.next_id in
      store.next_id <- id + 1;
      Hashtbl.add store.data_ids key id;
      id

let create () = {
  services = Hashtbl.create 16;
  data = Sparse_set.create ();
  data_ids = Hashtbl.create 16;
  next_id = 0;
}

(* --- Services ------------------------------------------------------------- *)

let add_service store key value =
  let id = hash_key key in
  Hashtbl.replace store.services id (Pack (value, fun () -> "service"))

let get_service store key =
  let id = hash_key key in
  match Hashtbl.find_opt store.services id with
  | Some (Pack (v, _)) -> Some (Obj.magic v)
  | None -> None

let remove_service store key =
  Hashtbl.remove store.services (hash_key key)

let list_services store =
  Hashtbl.to_seq_keys store.services |> List.of_seq

(* --- Data ----------------------------------------------------------------- *)

let add_data store id value =
  let key = hash_key id in
  let resolved = resolve_or_alloc store key in
  let entity = Entity_id.make resolved 0 in
  Sparse_set.set_value store.data entity (Pack (value, fun () -> "data"))

let get_data store id =
  let key = hash_key id in
  match Hashtbl.find_opt store.data_ids key with
  | Some resolved ->
      let entity = Entity_id.make resolved 0 in
      (match Sparse_set.get store.data entity with
       | Some (Pack (v, _)) -> Some (Obj.magic v)
       | None -> None)
  | None -> None

let remove_data store id =
  let key = hash_key id in
  match Hashtbl.find_opt store.data_ids key with
  | Some resolved ->
      let entity = Entity_id.make resolved 0 in
      Sparse_set.remove store.data entity
  | None -> ()

let iter_data f store =
  Sparse_set.iter (fun id (Pack (v, _)) -> f id (Obj.magic v)) store.data

let count_data store =
  Sparse_set.size store.data
