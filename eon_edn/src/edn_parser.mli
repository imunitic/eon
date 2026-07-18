(** EDN reader — parses a single {!Edn_effects.value} from a string.

    Handles only the reader-level effects ({!Edn_effects.Peek},
    {!Edn_effects.Read}, {!Edn_effects.Fail}) when driven via {!run}.
    {!Edn_effects.Tag} and {!Edn_effects.Meta} are deliberately left
    unhandled here so they propagate to {!Edn_middleware.run_with_middleware}. *)

val value : unit -> Edn_effects.value
(** Parse a single EDN value from the effect-driven input stream. Must be
    run inside a handler that supplies {!Edn_effects.Peek}/{!Edn_effects.Read}
    (see {!run}). *)

val run : (unit -> 'a) -> string -> 'a
(** [run parser input] installs a handler for
    {!Edn_effects.Peek}/{!Edn_effects.Read}/{!Edn_effects.Fail} backed by
    [input], then runs [parser ()]. Typical usage: [run value input].

    Does not handle {!Edn_effects.Tag}/{!Edn_effects.Meta} — a parser that
    encounters a tagged or meta value must be run via
    {!Edn_middleware.run_with_middleware} instead, or those effects go
    unhandled. *)
