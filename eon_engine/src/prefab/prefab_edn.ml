module Make (Root : sig
  val path : string
end) =
  Prefab.Make (Edn_source.Make (Root)) (Edn_document)
