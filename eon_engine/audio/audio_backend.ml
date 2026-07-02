module type S = sig
  val init     : (module Asset_lookup.S) -> unit
  val submit   : Audio_command.t list -> unit
  val shutdown : unit -> unit
end

module Null = struct
  let init _assets = ()
  let submit _     = ()
  let shutdown ()  = ()
end
