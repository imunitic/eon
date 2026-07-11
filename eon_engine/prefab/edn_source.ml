module Make (Root : sig
  val path : string
end) =
struct
  type raw_data = Eon_edn.Edn_effects.value

  let load name =
    let file_path = Filename.concat Root.path (name ^ ".edn") in
    let ic = open_in_bin file_path in
    let contents = really_input_string ic (in_channel_length ic) in
    close_in ic;
    (* [Edn_parser.run] alone never resolves [Tag]/[Meta] effects (by
       design — see eon_edn_parser.md). A prefab document may embed
       [#tag ...] values inline in a component's data; those must
       resolve here via the registry ([default_handler]), or loading
       raises Effect.Unhandled the moment a tag is encountered. *)
    Eon_edn.Edn_middleware.run_with_middleware
      (fun () -> Eon_edn.Edn_parser.value ())
      contents
end
