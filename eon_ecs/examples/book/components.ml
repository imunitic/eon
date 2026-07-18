(* Shared component modules used by every book chapter's examples.

   Each component is a real module carrying its own [type t], a unique
   [name], and a fixed [id] — the two things [World.register_component]
   needs. [register] wraps that call so every chapter registers the
   components it uses the same way a real game would: once, by name,
   before spawning any entity that carries it. *)

module Position = struct
  type t = { x : float; y : float }

  let name = "Position"
  let id = 0

  let register world = ignore (Eon_ecs.World.register_component world ~name ~id)
end

module Velocity = struct
  type t = { dx : float; dy : float }

  let name = "Velocity"
  let id = 1

  let register world = ignore (Eon_ecs.World.register_component world ~name ~id)
end

module Health = struct
  type t = { current : int; max : int }

  let name = "Health"
  let id = 2

  let register world = ignore (Eon_ecs.World.register_component world ~name ~id)
end
