module type S = sig
  val now : unit -> float
end

module Mtime : S
