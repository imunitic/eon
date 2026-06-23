module type S = sig
  type 'msg t
  val create  : unit -> 'msg t
  val on      : 'msg t -> ('msg -> unit) -> unit
  val emit    : 'msg t -> 'msg -> unit
  val collect : 'msg t -> unit
  val drain   : 'msg t -> unit
end
