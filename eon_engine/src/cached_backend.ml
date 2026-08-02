module Make
    (W : World.S)
    (B : Query_backend.S with type 'perm world = 'perm W.t)
  : Query_backend.S with type 'perm world = 'perm W.t
= struct
  type 'perm world = 'perm W.t

  (* Normalized signature: sorted + deduped, so having_all [A; B] and
     having_all [B; A] hit the same cache entry regardless of call-site
     argument order. *)
  type key = string list * string list

  type entry = {
    mutable entities : Eon_ecs.Entity_id.t list;
    (* One generation snapshot per component name involved (required and
       excludes both -- an excluded component's membership change can also
       change the match set), taken at the last fill. *)
    mutable generations : (string * int) list;
  }

  let normalize names = List.sort_uniq String.compare names

  let key_of ~required ~excludes : key = (normalize required, normalize excludes)

  (* One table, shared by every backend built from this functor application
     -- same "module-level mutable state created once at instantiation"
     pattern Single_bus/Double_bus already use. *)
  let cache : (key, entry) Hashtbl.t = Hashtbl.create 16

  let cache_signature ~required ~excludes =
    let k = key_of ~required ~excludes in
    if not (Hashtbl.mem cache k) then
      Hashtbl.add cache k { entities = []; generations = [] }

  let uncache_signature ~required ~excludes =
    Hashtbl.remove cache (key_of ~required ~excludes)

  (* Fresh iff every involved component's live generation still matches
     what was snapshotted at the last fill. *)
  let is_fresh world entry names =
    List.for_all
      (fun name ->
         match List.assoc_opt name entry.generations with
         | None -> false
         | Some snapshot -> snapshot = W.component_generation world name)
      names

  let refill world entry ~required ~excludes =
    let matches = ref [] in
    B.iter_entities world ~required ~excludes (fun e -> matches := e :: !matches);
    entry.entities <- !matches;
    entry.generations <-
      List.map
        (fun name -> (name, W.component_generation world name))
        (required @ excludes)

  (* Shared by iter_entities and count: look the signature up, refill if
     missing or stale, then hand the (now-fresh, or absent) entry to the
     caller. [on_uncached] is exactly the wrapped backend's own behaviour --
     a signature nobody called [cache_signature] on is untouched. *)
  let with_entry world ~required ~excludes ~on_cached ~on_uncached =
    match Hashtbl.find_opt cache (key_of ~required ~excludes) with
    | None -> on_uncached ()
    | Some entry ->
      if not (is_fresh world entry (required @ excludes)) then
        refill world entry ~required ~excludes;
      on_cached entry

  let iter_entities world ~required ~excludes f =
    with_entry world ~required ~excludes
      ~on_uncached:(fun () -> B.iter_entities world ~required ~excludes f)
      ~on_cached:(fun entry -> List.iter f entry.entities)

  let count world ~required ~excludes =
    with_entry world ~required ~excludes
      ~on_uncached:(fun () -> B.count world ~required ~excludes)
      ~on_cached:(fun entry -> List.length entry.entities)
end
