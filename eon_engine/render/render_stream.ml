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
