module type S = sig
  val init     : unit -> unit
  val submit   : Audio_command.t list -> unit
  val shutdown : unit -> unit
end

module Null = struct
  let init ()     = ()
  let submit _    = ()
  let shutdown () = ()
end
