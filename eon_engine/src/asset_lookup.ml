module type S = sig
  val iter : (string -> string -> unit) -> unit
end

module Dir (Root : sig val path : string end) = struct
  let iter f =
    let prefix = Root.path ^ Filename.dir_sep in
    let prefix_len = String.length prefix in
    let rec scan dir =
      Array.iter (fun entry ->
        let abs = Filename.concat dir entry in
        if Sys.is_directory abs then scan abs
        else
          let logical = String.sub abs prefix_len (String.length abs - prefix_len) in
          f logical abs
      ) (Sys.readdir dir)
    in
    if Sys.file_exists Root.path && Sys.is_directory Root.path then
      scan Root.path
end

module Null = struct
  let iter _ = ()
end

module Scripted = struct
  let entries : (string * string) list ref = ref []
  let set pairs = entries := pairs
  let iter f = List.iter (fun (id, path) -> f id path) !entries
end
