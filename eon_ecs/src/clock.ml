module type S = sig
  val now : unit -> float
end

module Mtime : S = struct
  let counter = Mtime_clock.counter ()

  let now () =
    let span = Mtime_clock.count counter in
    Mtime.Span.to_float_ns span /. 1e9
end
