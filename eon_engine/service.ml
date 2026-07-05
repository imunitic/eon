module type S = sig
  type t
  val fetch    : [> World.ro] World.t -> t
  val register : World.rw World.t -> t -> unit
end

let key v = Obj.repr v

module Make (T : sig
  type t
  val key : Obj.t
end) : S with type t = T.t = struct
  type t = T.t
  let key : [> ] = Obj.magic T.key
  let fetch world = match World.get_service world key with Some v -> v | None -> raise Not_found
  let register world v = World.add_service world key v
end


