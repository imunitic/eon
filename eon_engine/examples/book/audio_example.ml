(* Companion example for docs/eon_engine chapter: Audio. *)

open Eon_engine

let make_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

let audio_backend_example () =
  Audio_backend.Null.init ();
  Audio_backend.Null.submit
    [ Audio_command.Play_sound
        { id = "hit_01"; instance_id = None;
          volume = 0.9; pitch = 1.0; pan = 0.0; loop = false } ];
  Audio_backend.Null.shutdown ()

let buffer_example () =
  let world = make_world () in
  let buf = Audio_command_buffer.create () in
  Audio_command_buffer.store world buf;

  (* combat system detects a hit *)
  let on_hit world =
    let buf = Audio_command_buffer.fetch (World.readonly world) in
    Audio_command_buffer.add buf
      (Audio_command.Play_sound
         { id = "hit_01"; instance_id = None;
           volume = 0.9; pitch = 1.0; pan = 0.0; loop = false })
  in

  (* spatial audio system updates a looping emitter each frame *)
  let update_emitter world iid ~volume ~pan =
    let buf = Audio_command_buffer.fetch (World.readonly world) in
    Audio_command_buffer.add buf (Audio_command.Set_volume (iid, volume));
    Audio_command_buffer.add buf (Audio_command.Set_pan    (iid, pan))
  in

  on_hit world;
  update_emitter world "emitter:1" ~volume:0.5 ~pan:0.0;

  assert (List.length (Audio_command_buffer.to_list buf) = 3);
  Audio_command_buffer.clear buf;
  assert (Audio_command_buffer.to_list buf = [])

(* Worked example: spatial audio. Sound_emitter/Sound_listener are
   game-defined components (not shipped by the engine) — plain component
   descriptors via Eon_engine.component, same pattern as chapter 1's
   Health example. Sound_listener is world-scoped, one-per-world state, so
   it's a Resource (Resource.Make), not a per-entity component — reached
   via Resource.fetch, which returns the value directly (not an option),
   unlike the raw World.get_data the original doc used. *)
module Sound_emitter = struct
  type t = {
    sound_id : string;
    range    : float;
    volume   : float;
    playing  : bool;
  }
  let component : t Components.t = Eon_engine.component "Sound_emitter"
  let name = Components.name component
end

type sound_listener = { position : Math.Vec2.t }

module Sound_listener = Resource.Make (struct
  type t = sound_listener
  let key = Resource.key `Sound_listener
end)

(* Eon_ecs.Entity_id has no to_string — only index/generation accessors. *)
let emitter_instance_id view =
  let e = View.entity view in
  Printf.sprintf "emitter:%d:%d" (Eon_ecs.Entity_id.index e) (Eon_ecs.Entity_id.generation e)

let update_spatial_audio (world : World.ro World.t) _dt =
  let buf      = Audio_command_buffer.fetch world in
  let listener = Sound_listener.fetch world in
  Query.Default.from world
  |> Query.Default.having Sound_emitter.name
  |> Query.Default.iter (fun view ->
       let emitter = View.get view (module Sound_emitter) in
       let pos     = View.get view (module Components.Local_transform) in
       let iid     = emitter_instance_id view in
       let dist    = Math.Vec2.distance listener.position pos.position in
       if dist > emitter.range then begin
         if emitter.playing then
           Audio_command_buffer.add buf (Audio_command.Stop_sound iid)
       end else begin
         let vol = emitter.volume *. (1.0 -. (dist /. emitter.range)) in
         if not emitter.playing then
           Audio_command_buffer.add buf
             (Audio_command.Play_sound
                { id = emitter.sound_id; instance_id = Some iid;
                  volume = vol; pitch = 1.0; pan = 0.0; loop = true })
         else
           Audio_command_buffer.add buf (Audio_command.Set_volume (iid, vol))
       end)

let spatial_audio_example () =
  let world = make_world () in
  let _ = World.register world Sound_emitter.component in
  Sound_listener.store world { position = Math.Vec2.zero };

  let near = World.create_entity world in
  World.add_component world near Components.Local_transform.component
    ({ position = Math.Vec2.create 5.0 0.0; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world near Sound_emitter.component
    ({ sound_id = "fire"; range = 10.0; volume = 1.0; playing = false } : Sound_emitter.t);

  let far = World.create_entity world in
  World.add_component world far Components.Local_transform.component
    ({ position = Math.Vec2.create 500.0 0.0; rotation = 0.0; scale = Math.Vec2.one }
     : Components.Local_transform.t);
  World.add_component world far Sound_emitter.component
    ({ sound_id = "growl"; range = 10.0; volume = 1.0; playing = false } : Sound_emitter.t);

  let buf = Audio_command_buffer.create () in
  Audio_command_buffer.store world buf;

  update_spatial_audio (World.readonly world) 0.0;

  let cmds = Audio_command_buffer.to_list buf in
  (* near emitter starts playing; far emitter is out of range and wasn't
     playing, so nothing is emitted for it *)
  assert (List.length cmds = 1);
  match cmds with
  | [ Audio_command.Play_sound { id; _ } ] -> assert (id = "fire")
  | _ -> assert false

let () =
  audio_backend_example ();
  buffer_example ();
  spatial_audio_example ()
