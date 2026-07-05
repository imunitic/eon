type t = { mutable commands : Audio_command.t list [@atomic] }

let create ()  = { commands = [] }
let clear  buf = Atomic.Loc.set [%atomic.loc buf.commands] []
let to_list buf = List.rev (Atomic.Loc.get [%atomic.loc buf.commands])

let add buf cmd =
  let rec loop () =
    let before = Atomic.Loc.get [%atomic.loc buf.commands] in
    if not (Atomic.Loc.compare_and_set [%atomic.loc buf.commands] before (cmd :: before))
    then loop ()
  in
  loop ()

let resource_key = `Audio_command_buffer

let fetch world =
  match World.get_data world resource_key with
  | Some b -> b
  | None   -> raise Not_found

let fetch_opt world = World.get_data world resource_key

let store world buf = World.set_data world resource_key buf
