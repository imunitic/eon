module type S = sig
  val run_all : (unit -> unit) list -> unit
end

module Sequential = struct
  let run_all jobs = List.iter (fun f -> f ()) jobs
end
