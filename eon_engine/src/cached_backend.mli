(** Optional, selective query-result cache.

    Wraps another {!Query_backend.S} and serves [iter_entities]/[count] for
    registered signatures from a cached match list instead of re-scanning
    the wrapped backend every call, refilling only when one of the
    signature's components' membership has actually changed (via
    [World.S.component_generation]). A signature nobody called
    [cache_signature] on behaves identically to the wrapped backend --
    caching is opt-in per signature, never automatic.

    Intended for the sparse-set adversarial worst case: a multi-component
    query whose smallest involved set is still large in absolute terms but
    yields very few matches, so a query re-run every frame wastes a full
    scan for a handful of results.

    {[
      module Q = Query.Make (Cached_backend.Make (World) (Sparse_set_backend.Default))

      let () = Q.cache_signature ~required:["Province"; "Infrastructure"] ~excludes:[]
    ]}
*)

(* [B]'s own module type doesn't leak into the result signature below (only
   [W]'s does), even though [B] is genuinely used for its runtime values
   (iter_entities/count) inside the implementation -- a known-imprecise
   case for warning 67, not a sign the parameter is actually dead. *)
[@@@warning "-67"]

module Make
    (W : World.S)
    (B : Query_backend.S with type 'perm world = 'perm W.t)
  : Query_backend.S with type 'perm world = 'perm W.t
