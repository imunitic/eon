[@@@warning "-67"]

(** {!Prefab.Source} reading [.edn] files from a directory — same shape
    as {!Asset_lookup.Dir}'s parameter, so a game points it at its own
    prefabs directory. *)

module Make (Root : sig
  val path : string
end) : Prefab.Source with type raw_data = Eon_edn.Edn_effects.value
(** [load name] reads [<Root.path>/<name>.edn] and parses it. Raises
    [Sys_error] if the file doesn't exist, or the parser's [Failure] on
    malformed EDN. *)
