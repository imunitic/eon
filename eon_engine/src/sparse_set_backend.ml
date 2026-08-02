module Make (W : World.S) : Query_backend.S with type 'perm world = 'perm W.t = struct
  type 'perm world = 'perm W.t

  let iter_entities world ~required ~excludes f =
    W.iter_entities world required (fun entity ->
      if not (List.exists (W.has_component world entity) excludes) then
        f entity)

  let count world ~required ~excludes =
    let n = ref 0 in
    iter_entities world ~required ~excludes (fun _ -> incr n);
    !n

  let cache_signature ~required:_ ~excludes:_ = ()
  let uncache_signature ~required:_ ~excludes:_ = ()
end

module Default = Make (World)
