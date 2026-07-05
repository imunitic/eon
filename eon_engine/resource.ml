module type S = sig
  type t
  val fetch : [> World.ro] World.t -> t
  val store : World.rw World.t -> t -> unit
end

let key v = Obj.repr v

module Make (T : sig
  type t
  val key : Obj.t
end) : S with type t = T.t = struct
  type t = T.t
  let key : [> ] = Obj.magic T.key
  let fetch world = match World.get_data world key with Some v -> v | None -> raise Not_found
  let store world v = World.set_data world key v
end


