type 'command t = 'command Render_stream.t

let key = `Render_stream

let fetch world =
  match World.get_data world key with
  | Some s -> s
  | None   -> raise Not_found

let fetch_opt world = World.get_data world key

let store world s = World.set_data world key s
