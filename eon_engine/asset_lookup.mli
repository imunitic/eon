[@@@warning "-67"]

(** Asset lookup — maps logical string ids to absolute file paths.

    Backends receive a [module Asset_lookup.S] at [init] time and walk it
    once to pre-load assets into internal handles. Game code never sees
    those handles — it uses the same logical string ids forever.

    The directory structure is the manifest: drop a file in the right folder
    and it is immediately available with its relative path as the logical id.

    {[
      assets/
        sounds/hit.wav   →  logical_id: "sounds/hit.wav"
        music/theme.ogg  →  logical_id: "music/theme.ogg"
    ]} *)

module type S = sig
  val iter : (string -> string -> unit) -> unit
  (** [iter f] calls [f logical_id absolute_path] for every asset. *)
end

(** Scans [Root.path] recursively. The logical id is the path relative to
    the root. Safe to apply at module init time; the directory is re-scanned
    on every [iter] call so hot-reloading works without code changes. *)
module Dir (Root : sig val path : string end) : S

(** Always empty — no assets. Use in CI and tests that need no real files. *)
module Null : S

(** Hand-maintained list of [(logical_id, absolute_path)] pairs.
    Use in tests that need precise control over which assets are visible. *)
module Scripted : sig
  include S
  val set : (string * string) list -> unit
end
