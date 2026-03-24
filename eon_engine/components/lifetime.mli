(** Lifetime component for Eon Engine.

    Tracks how many seconds remain before an entity should be destroyed.
    A lifetime system decrements [ttl] by [dt] each frame and calls
    [World.destroy_entity] when it reaches zero.

    {b Runtime policy:}
    Component type registration happens at boot time only. The component
    registry is immutable during gameplay. Hot-loading of component types is
    not supported in v1; use a fast full-reload workflow instead.
*)

type t = {
  ttl : float;  (** Time to live in seconds. *)
}

val component : t Component_descriptor.t

val name : string
