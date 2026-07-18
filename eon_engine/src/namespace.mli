(** Flat world directory for cross-world access.

    [Namespace.t] is a plain value — create it, populate it at startup, and
    keep it wherever makes sense (module-level value, stored as a service,
    captured in a closure). The engine does not prescribe where it lives.

    Cross-world access composes [named] with [Resource.fetch] / [Service.fetch]:
    {[
      Resource.fetch (Namespace.named "global" ns) (module Raw_input_frame)
      Service.fetch  (Namespace.named "global" ns) (module Steam_api)
    ]} *)

exception Unknown_namespace of string

type t

val create : unit -> t
(** Empty directory. *)

val attach : t -> string -> World.rw World.t -> unit
(** Register a world under a name. Intended for startup before the loop. *)

val named : string -> t -> World.rw World.t
(** Look up a world by name. Raises [Unknown_namespace] if not found. *)
