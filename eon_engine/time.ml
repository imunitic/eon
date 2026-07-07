module type S = sig
  type t = { delta : float; elapsed : float; frame : int }
  include Resource.S with type t := t
  val zero  : t
  val write : World.rw World.t -> float -> unit
end

type t = { delta : float; elapsed : float; frame : int }

let key = `Time

let fetch world =
  match World.get_data world key with
  | Some v -> v
  | None   -> raise Not_found

let store world v = World.set_data world key v

let zero = { delta = 0.; elapsed = 0.; frame = 0 }

let write world dt =
  let prev = try fetch world with Not_found -> zero in
  store world { delta = dt; elapsed = prev.elapsed +. dt; frame = prev.frame + 1 }
