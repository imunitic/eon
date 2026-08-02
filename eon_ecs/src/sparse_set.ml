module type INDEXED_KEY = sig
  type t
  val index : t -> int
end

module type S = sig
  type key
  type 'a t

  val create : ?capacity:int -> unit -> 'a t
  val capacity : 'a t -> int
  val size : 'a t -> int
  val version : 'a t -> int
  val grow : 'a t -> unit
  val contains : 'a t -> key -> bool
  val get : 'a t -> key -> 'a option
  val get_exn : 'a t -> key -> 'a
  val add : 'a t -> key -> 'a -> unit
  val set_value : 'a t -> key -> 'a -> unit
  val remove : 'a t -> key -> unit
  val iter : (int -> 'a -> unit) -> 'a t -> unit
end

module Make (Key : INDEXED_KEY) : S with type key = Key.t = struct
  type key = Key.t

  type 'a t = {
      mutable sparse : int array;
      mutable dense  : int array;
      mutable values : 'a array;
      mutable count  : int;
      mutable version : int;
    }

  let create ?(capacity = 128) () =
    {
      sparse = Array.make capacity (-1);
      dense  = Array.make capacity (-1);
      values = Array.make capacity (Obj.magic ());
      count  = 0;
      version = 0;
    }

  let capacity set = Array.length set.dense
  let size set = set.count
  let version set = set.version

  let grow set =
    let old_cap = capacity set in
    let new_cap = max (old_cap * 2) 1 in
    let grow_int a =
      let b = Array.make new_cap (-1) in
      Array.blit a 0 b 0 old_cap;
      b
    in
    let grow_val a =
      let b = Array.make new_cap (Obj.magic ()) in
      Array.blit a 0 b 0 old_cap;
      b
    in
    set.sparse <- grow_int set.sparse;
    set.dense  <- grow_int set.dense;
    set.values <- grow_val set.values

  let ensure_capacity set idx =
    while idx >= capacity set do
      grow set
    done

  let contains set key =
    let idx = Key.index key in
    idx < capacity set && set.sparse.(idx) <> -1

  let get set key =
    let idx = Key.index key in
    if idx < capacity set then
      let dense_idx = set.sparse.(idx) in
      if dense_idx <> -1 then Some set.values.(dense_idx) else None
    else
      None

  let get_exn set key =
    let idx = Key.index key in
    if idx < capacity set then
      let dense_idx = set.sparse.(idx) in
      if dense_idx <> -1 then set.values.(dense_idx)
      else raise Not_found
    else
      raise Not_found

  let add set key value =
    let idx = Key.index key in
    ensure_capacity set idx;
    if set.sparse.(idx) <> -1 then
      set.values.(set.sparse.(idx)) <- value
    else (
      let dense_idx = set.count in
      set.sparse.(idx) <- dense_idx;
      set.dense.(dense_idx) <- idx;
      set.values.(dense_idx) <- value;
      set.count <- dense_idx + 1;
      set.version <- set.version + 1
    )

  let set_value set key value =
    let idx = Key.index key in
    ensure_capacity set idx;
    let dense_idx = set.sparse.(idx) in
    if dense_idx <> -1 then
      set.values.(dense_idx) <- value
    else
      add set key value

  let remove set key =
    let idx = Key.index key in
    if idx < capacity set then
      let dense_idx = set.sparse.(idx) in
      if dense_idx <> -1 then (
        let last = set.count - 1 in
        let last_key = set.dense.(last) in
        set.dense.(dense_idx) <- last_key;
        set.values.(dense_idx) <- set.values.(last);
        set.sparse.(last_key) <- dense_idx;
        set.sparse.(idx) <- -1;
        set.count <- last;
        set.version <- set.version + 1
      )

  let iter f set =
    for i = 0 to set.count - 1 do
      f set.dense.(i) set.values.(i)
    done
end

module Entity = Make(Eon_ecs__Entity_id)

type 'a t = 'a Entity.t

let create = Entity.create
let capacity = Entity.capacity
let size = Entity.size
let version = Entity.version
let grow = Entity.grow
let contains = Entity.contains
let get = Entity.get
let get_exn = Entity.get_exn
let add = Entity.add
let set_value = Entity.set_value
let remove = Entity.remove
let iter = Entity.iter

module Int = Make(struct
  type t = int
  let index x = x
end)
