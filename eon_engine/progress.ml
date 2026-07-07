include Eon_ecs.Progress

module Make_with_time
    (P : Eon_ecs.Pipeline.S
           with type kind = [ `Fixed | `Variable ]
            and type world = World.rw World.t)
    (T : Time.S)
= struct
  module Base = Eon_ecs.Progress.Make(P)
  include Base

  let tick t ~world ~dt =
    T.write world dt;
    Base.tick t ~world ~dt
end
