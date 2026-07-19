(* Companion example for docs/eon_engine chapter: Rendering. *)

open Eon_engine

let make_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

let color_example () =
  let red   = Color.create 1.0 0.0 0.0 1.0 in
  let semi  = Color.create 0.0 0.5 1.0 0.5 in
  let clear = Color.transparent in
  assert (red.r = 1.0);
  assert (semi.a = 0.5);
  assert (clear.a = 0.0);
  assert (Color.white.r = 1.0 && Color.white.g = 1.0);
  assert (Color.black.r = 0.0)

let render_commands_example () =
  let _clear : Render_commands.command = `Clear_background Color.black in

  let _camera : Render_commands.command =
    `Set_camera Render_commands.{
      position = (0.0, 0.0);
      zoom     = Some 1.0;
      rotation = None;
      target   = None;
      viewport = None;
    }
  in

  let _sprite : Render_commands.command =
    `Draw_texture Render_commands.{
      texture_id = "sprites/player.png";
      source     = Some (Math.Rect.create 0.0 0.0 16.0 16.0);
      dest       = Math.Rect.create 100.0 200.0 32.0 32.0;
      rotation   = None;
      origin     = None;
      tint       = None;
      layer      = 0;
    }
  in

  let _bar_bg : Render_commands.command =
    `Draw_rect Render_commands.{
      rect   = Math.Rect.create 10.0 10.0 100.0 8.0;
      color  = Color.black;
      filled = true;
      layer  = 10;
    }
  in

  let _bar_fill : Render_commands.command =
    `Draw_rect Render_commands.{
      rect   = Math.Rect.create 10.0 10.0 75.0 8.0;
      color  = Color.create 0.0 1.0 0.0 1.0;
      filled = true;
      layer  = 11;
    }
  in
  ()

(* Backends that need custom commands extend via polymorphic variant
   inclusion. The engine never sees the extended type. *)
type shader = { id : string }
type particle_system_cmd = { emitter : string; count : int }

type extended_command = [
  | Render_commands.command
  | `Apply_shader   of shader
  | `Draw_particles of particle_system_cmd
]

let extended_command_example () =
  let cmds : extended_command list =
    [ `Clear_background Color.black;
      `Apply_shader { id = "bloom" };
      `Draw_particles { emitter = "sparks"; count = 32 } ]
  in
  assert (List.length cmds = 3)

let render_stream_example () =
  let stream = Render_stream.create () in

  Render_stream.add_world stream (`Clear_background Color.black);
  Render_stream.add_world stream
    (`Set_camera Render_commands.{
       position = (0.0, 0.0); zoom = None;
       rotation = None; target = None; viewport = None });
  Render_stream.add_world stream
    (`Draw_texture Render_commands.{
       texture_id = "sprites/player.png"; source = None;
       dest = Math.Rect.create 100.0 200.0 32.0 32.0;
       rotation = None; origin = None; tint = None; layer = 0 });

  Render_stream.add_screen stream
    (`Draw_text Render_commands.{
       text = "HP: 100"; position = (8.0, 8.0);
       font_id = "fonts/ui.ttf"; size = 14.0;
       color = Color.white; layer = 0 });

  let world_count = ref 0 in
  let screen_count = ref 0 in
  Render_stream.iter_world  stream (fun _cmd -> incr world_count);
  Render_stream.iter_screen stream (fun _cmd -> incr screen_count);
  assert (!world_count = 3);
  assert (!screen_count = 1);

  Render_stream.clear stream;
  let after_clear = ref 0 in
  Render_stream.iter_world stream (fun _cmd -> incr after_clear);
  assert (!after_clear = 0)

(* Sprite is { texture_id; layer; flip_x; flip_y } — it does NOT carry a
   source rect or a size (no source_rect/w/h fields, despite the original
   doc using them). A real sprite renderer needs a size from somewhere
   else (an atlas lookup keyed by texture_id, a separate Size component,
   etc.) — this example uses a fixed placeholder size to keep the
   collector runnable without inventing an unshipped component. *)
let collect_camera (_world : World.ro World.t) stream =
  Render_stream.add_world stream
    (`Set_camera Render_commands.{
       position = (0.0, 0.0); zoom = None;
       rotation = None; target = None; viewport = None })

let sprite_size = 32.0

let collect_sprites (world : World.ro World.t) stream =
  Query.Default.from world
  |> Query.Default.having Components.Local_transform.name
  |> Query.Default.having Components.Sprite.name
  |> Query.Default.iter (fun view ->
       let lt     = View.get view (module Components.Local_transform) in
       let sprite = View.get view (module Components.Sprite) in
       Render_stream.add_world stream
         (`Draw_texture Render_commands.{
            texture_id = sprite.texture_id;
            source     = None;
            dest       = Math.Rect.create lt.position.x lt.position.y sprite_size sprite_size;
            rotation   = None; origin = None; tint = None;
            layer      = sprite.layer }))

let collect_hud (_world : World.ro World.t) stream =
  Render_stream.add_screen stream
    (`Draw_text Render_commands.{
       text = "HP: 100"; position = (8.0, 8.0);
       font_id = "fonts/ui.ttf"; size = 14.0;
       color = Color.white; layer = 0 })

let single_camera_collector_example () =
  let world = make_world () in
  let e = World.create_entity world in
  World.add_component world e Components.Local_transform.component
    ({ position = Math.Vec2.create 10.0 20.0; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world e Components.Sprite.component
    ({ texture_id = "sprites/player.png"; layer = 0; flip_x = false; flip_y = false }
     : Components.Sprite.t);

  let render_collector =
    Render_stream_collector.create ()
    |> Render_stream_collector.add_phase `Camera
    |> Render_stream_collector.add_phase `World  ~after:`Camera
    |> Render_stream_collector.add_collector `Camera collect_camera
    |> Render_stream_collector.add_collector `World  collect_sprites
  in

  let stream = Render_stream.create () in
  Render_stream_collector.collect render_collector (World.readonly world) stream;

  let cmds = ref [] in
  Render_stream.iter_world stream (fun cmd -> cmds := cmd :: !cmds);
  let cmds = List.rev !cmds in
  (match cmds with
   | [ `Set_camera _; `Draw_texture _ ] -> ()
   | _ -> assert false)

(* Multi-camera: each camera gets its own pair of phases, chained with
   ~after. Adding a third camera is two more add_phase lines. *)
let collect_main_camera (_world : World.ro World.t) stream =
  Render_stream.add_world stream
    (`Set_camera Render_commands.{
       position = (0.0, 0.0); zoom = None;
       rotation = None; target = None; viewport = None })

let collect_minimap_camera (_world : World.ro World.t) stream =
  Render_stream.add_world stream
    (`Set_camera Render_commands.{
       position = (0.0, 0.0); zoom = Some 0.1;
       rotation = None; target = None;
       viewport = Some (Math.Rect.create 500.0 10.0 128.0 128.0) })

let collect_minimap_icons (_world : World.ro World.t) stream =
  Render_stream.add_world stream
    (`Draw_circle Render_commands.{
       center = (0.0, 0.0); radius = 2.0; color = Color.white; filled = true; layer = 0 })

let multi_camera_collector_example () =
  let world = make_world () in
  let render_collector =
    Render_stream_collector.create ()
    |> Render_stream_collector.add_phase `Main_camera
    |> Render_stream_collector.add_phase `Main_world     ~after:`Main_camera
    |> Render_stream_collector.add_phase `Minimap_camera ~after:`Main_world
    |> Render_stream_collector.add_phase `Minimap_world  ~after:`Minimap_camera
    |> Render_stream_collector.add_phase `Screen         ~after:`Minimap_world
    |> Render_stream_collector.add_collector `Main_camera    collect_main_camera
    |> Render_stream_collector.add_collector `Main_world     collect_sprites
    |> Render_stream_collector.add_collector `Minimap_camera collect_minimap_camera
    |> Render_stream_collector.add_collector `Minimap_world  collect_minimap_icons
    |> Render_stream_collector.add_collector `Screen         collect_hud
  in
  let stream = Render_stream.create () in
  Render_stream_collector.collect render_collector (World.readonly world) stream;

  let world_cmds = ref 0 in
  let screen_cmds = ref 0 in
  Render_stream.iter_world  stream (fun _ -> incr world_cmds);
  Render_stream.iter_screen stream (fun _ -> incr screen_cmds);
  assert (!world_cmds = 3);   (* main camera + minimap camera + one minimap icon; no sprites this frame *)
  assert (!screen_cmds = 1)

(* Render_system: clears + repopulates the stream each tick, stores it in
   the world data plane. Register this system's phase after gameplay.
   Render_system.Make(B).make wires directly into Pipeline.Default. *)
module Null_render_system = Render_system.Make (Rendering_backend.Null)

let render_system_example () =
  let render_collector =
    Render_stream_collector.create ()
    |> Render_stream_collector.add_phase `Camera
    |> Render_stream_collector.add_phase `World ~after:`Camera
    |> Render_stream_collector.add_collector `Camera collect_camera
    |> Render_stream_collector.add_collector `World  collect_sprites
  in
  let render_system =
    Null_render_system.make ~render_stream_collector:render_collector
  in

  let world = make_world () in
  let e = World.create_entity world in
  World.add_component world e Components.Local_transform.component
    ({ position = Math.Vec2.zero; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world e Components.Sprite.component
    ({ texture_id = "sprites/player.png"; layer = 0; flip_x = false; flip_y = false }
     : Components.Sprite.t);

  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Render
    |> Pipeline.Default.add_system `Render render_system
  in
  Pipeline.Default.reset pipeline;
  Pipeline.Default.register_all pipeline world;
  let world = Pipeline.Default.run pipeline world (1.0 /. 60.0) in

  match Render_stream.fetch_opt (World.readonly world) with
  | None -> assert false
  | Some stream ->
    let count = ref 0 in
    Render_stream.iter_world stream (fun _ -> incr count);
    assert (!count = 2)   (* camera + one sprite *)

(* Bypassing Render_system: any Exclusive system can populate the stream
   and call Render_stream.store directly — the loop only looks for a
   value under the Render_stream resource, it doesn't care how it got
   there. Unqualified Exclusive resolves via type-directed
   disambiguation (see the queries-and-systems chapter); the qualified
   System.Exclusive form does not. Render_stream.store/fetch_opt are the
   typed facade — bypassing them with raw World.set_data/get_data and a
   bare `Render_stream tag, as the original doc did, does not use the
   same internal key Render_stream itself uses and will not round-trip. *)
let bypass_example () =
  let custom_render_system =
    System.Default.make
      (Exclusive (fun world _dt ->
        let stream =
          match Render_stream.fetch_opt (World.readonly world) with
          | Some s -> s
          | None -> Render_stream.create ()
        in
        Render_stream.add_world stream (`Clear_background Color.black);
        Render_stream.store world stream))
  in
  let pipeline =
    Pipeline.Default.create ()
    |> Pipeline.Default.add_phase `Render
    |> Pipeline.Default.add_system `Render custom_render_system
  in
  Pipeline.Default.reset pipeline;
  let world = make_world () in
  Pipeline.Default.register_all pipeline world;
  let world = Pipeline.Default.run pipeline world 0.0 in
  match Render_stream.fetch_opt (World.readonly world) with
  | None -> assert false
  | Some _ -> ()

let () =
  color_example ();
  render_commands_example ();
  extended_command_example ();
  render_stream_example ();
  single_camera_collector_example ();
  multi_camera_collector_example ();
  render_system_example ();
  bypass_example ()
