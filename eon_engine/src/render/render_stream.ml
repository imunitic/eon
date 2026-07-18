type 'command t = {
  world  : 'command Dynarray.t;
  screen : 'command Dynarray.t;
}

let create () = { world = Dynarray.create (); screen = Dynarray.create () }

let clear t =
  Dynarray.clear t.world;
  Dynarray.clear t.screen

let add_world  t cmd = Dynarray.add_last t.world  cmd
let add_screen t cmd = Dynarray.add_last t.screen cmd

let iter_world  t f = Dynarray.iter f t.world
let iter_screen t f = Dynarray.iter f t.screen

let key = `Render_stream

let fetch world =
  match World.get_data world key with
  | Some s -> s
  | None   -> raise Not_found

let fetch_opt world = World.get_data world key

let store world s = World.set_data world key s
