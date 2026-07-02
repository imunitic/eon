# Audio System Design — `eon_engine`

## Status

**DRAFT** (no task assigned yet). Design decisions captured from architecture
discussion. Implementation task to be created later.

---

## 1. Scope

This document specifies the audio layer for `eon_engine`. It covers:

- `Audio_backend.S` — the platform seam, completing the Platform.S trifecta
- `Audio_command` — the vocabulary game code sends to the backend
- `Audio_command_buffer` — the per-frame accumulator; the handoff point between game systems and the loop
- Loop and Platform.S integration — when the buffer is cleared, when submit is called
- What NOT to do

The design follows the same philosophy as the rendering layer: the engine defines
the seam and the accumulator; game code decides which components to use and which
systems write audio commands. The engine ships no audio systems and no audio
components — it cannot know how a game models spatial audio, music state, or sound
triggers. The recommended default backend is `Raylib_audio` (backed by miniaudio
internally).

---

## 2. Why Audio is Different from Rendering and Input

Audio runs on a fundamentally different schedule than the game. The game runs at
60fps (~16ms per frame). The audio hardware needs samples continuously at 44100 Hz
or 48000 Hz — roughly 2756 times per frame — regardless of what the game is doing.
These two clocks are independent and cannot be synchronized.

Most audio APIs (SDL, miniaudio, OpenAL, raylib) express this via a **callback
model**: the OS/driver calls your function saying "give me N samples right now" and
you must return them immediately. That callback runs on a thread controlled by the
audio hardware, not the game loop.

**The real-time safety constraint** — the audio callback is subject to hard rules:

- No memory allocation (`malloc`/`free`)
- No mutex locks (can cause priority inversion — audio thread waits for game thread,
  audio drops out)
- No file I/O, no system calls that can block

This is why the engine does not call audio functions directly. It accumulates
commands during the game tick and submits them to the backend at the end of the
frame. The engine sees none of the threading or buffering detail.

**Every realistic backend library handles all of this for you.** raylib (miniaudio),
OpenAL Soft, FMOD, SoLoud, and SDL_mixer all own the callback thread, the ring
buffer, the mixer, and the streaming decoder internally. From the OCaml side,
`submit` is just a loop over library calls made from the game thread — no OCaml
Domains, no lock-free data structures, no real-time constraints on your code.
The real-time safety rules above are the library's problem, not yours.

The only way to run into those constraints is to use a raw platform audio API
(WASAPI, CoreAudio, ALSA) directly — which are what the above libraries sit on
top of. There is no reason to do this for a game.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ game tick (60fps)                                           │
│                                                             │
│  any system — combat, skills, UI, spatial audio, music ...  │
│    appends Audio_commands to Audio_command_buffer           │
│    (stored in world data plane; cleared each frame)         │
│                                                             │
└──────────────────────────┬──────────────────────────────────┘
                           │ collect → tick → drain
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ engine loop (after drain)                                   │
│                                                             │
│  reads Audio_command_buffer from world data plane           │
│  calls Platform.Audio_backend.submit commands               │
│  clears Audio_command_buffer for next frame                 │
└──────────────────────────┬──────────────────────────────────┘
                           │ Audio_command list (once per frame)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Audio_backend (Raylib_audio / Null_audio)                   │
│                                                             │
│  submit: translates commands → library API calls            │
│  (everything below this line is the C library's concern)    │
│  ·  mixer running in audio callback at hardware rate        │
│  ·  lock-free ring buffer bridging game thread ↔ audio      │
│  ·  streaming decoder on a dedicated thread for music       │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Audio Backend

### 4.1 Contract

The entire backend contract is one function:

```ocaml
module type S = sig
  val init     : (module Asset_lookup.S) -> unit
  val submit   : Audio_command.t list -> unit
  val shutdown : unit -> unit
end
```

`init` opens the audio device and scans the asset lookup to pre-load sound effects
(WAV files as PCM buffers; OGG music paths stored for streaming). The backend
resolves string identifiers to internal handles once at startup — game code never
touches backend handles. `submit` is called once per frame with the accumulated
command list; it translates each command to a library call (`PlaySound`,
`SetSoundVolume`, etc.) made from the game thread. The library handles all
threading and buffering internally. `shutdown` stops playback and closes the
device.

### 4.2 Concrete backends

```ocaml
(* Raylib — backed by miniaudio; default platform backend *)
module Raylib_audio : Audio_backend.S = struct
  let init (module Assets : Asset_lookup.S) =
    InitAudioDevice ();
    Assets.iter (fun logical_id path -> preload_sound logical_id path)
  let submit commands = List.iter apply_command commands
  let shutdown ()     = CloseAudioDevice ()
end

(* Null — silent; lives inside audio_backend.ml, same pattern as Input_backend.Null *)
module Null : S = struct
  let init _assets  = ()
  let submit _      = ()
  let shutdown ()   = ()
end
```

---

## 5. Audio Command Vocabulary

The command list is the DSL of the audio layer — analogous to `Input_mapping` for
the input system and the `Render_stream` command language for rendering. The engine
sends commands; the backend executes them.

```ocaml
type audio_command =
  (* one-shot and looping sounds *)
  | Play_sound  of {
      id          : string;        (* asset id — resolved by backend via Asset_lookup.S *)
      instance_id : string option; (* caller-provided tag for later control; None = fire-and-forget *)
      volume      : float;         (* 0.0–1.0 *)
      pitch       : float;         (* 1.0 = normal *)
      pan         : float;         (* -1.0 left .. 1.0 right; 0.0 centre *)
      loop        : bool;
    }
  | Stop_sound  of string          (* instance_id *)
  | Set_volume  of string * float  (* instance_id, volume *)
  | Set_pitch   of string * float  (* instance_id, pitch *)
  | Set_pan     of string * float  (* instance_id, pan *)

  (* music streaming — separate voice budget from SFX *)
  | Play_music  of { id: string; volume: float; loop: bool }
  | Stop_music
  | Set_music_volume of float
  | Crossfade_music  of { id: string; duration: float }

  (* global *)
  | Set_master_volume of float
  | Pause_all
  | Resume_all
  | Stop_all
```

The backend maintains two internal lookup tables, both hidden from the public API:

- **`asset_table : sound_id → buffer_handle`** — static. Built once at `init` by
  walking `Asset_lookup.S` and never modified again. Each `sound_id` string (e.g.
  `"sounds/growl.wav"`) is resolved to a pre-loaded PCM buffer or a streaming path.
  Game code never touches these handles.
- **`voice_table : instance_id → voice_slot`** — dynamic. Updated every frame by
  `submit` as emitters come and go. When `Play_sound { instance_id = Some
  "emitter:42"; ... }` arrives, the backend allocates a voice slot and records the
  mapping. `Stop_sound "emitter:42"` looks up that string, stops the slot, and
  removes the entry. The caller only ever uses the string it chose; voice slot
  numbers never leave the backend.

For fire-and-forget one-shot sounds, `instance_id = None` — the backend manages
the voice lifetime and the caller never needs to reference it again. For looping or
spatial sounds that need stopping or updating, the caller provides a stable string
(typically derived from the entity id) and reuses it across frames.

---

## 6. Audio_command_buffer

`Audio_command_buffer` is the handoff point between game systems and the engine
loop — the audio equivalent of `Render_stream`. Any system that wants to produce
sound appends commands to it during tick. The loop reads it once after drain,
calls `Platform.Audio_backend.submit`, then clears it for the next frame.

```ocaml
(* audio_command_buffer.mli *)
type t

val create  : unit -> t
val clear   : t -> unit
val add     : t -> Audio_command.t -> unit
val to_list : t -> Audio_command.t list
```

The buffer is created once and stored in the world data plane. Game code accesses
it via `World.get_data world \`Audio_command_buffer`.

### Lock-free concurrent appends

The `commands` field is declared `[@atomic]` (OCaml 5.4), making `add` a
lock-free CAS loop. Because there is no central audio system, any number of
parallel systems can append to the same buffer concurrently with no mutex and
no serialization point:

```ocaml
(* audio_command_buffer.ml *)
type t = { mutable commands : Audio_command.t list [@atomic] }

let add buf cmd =
  let rec loop () =
    let before = Atomic.Loc.get [%atomic.loc buf.commands] in
    if not (Atomic.Loc.compare_and_set [%atomic.loc buf.commands] before (cmd :: before))
    then loop ()
  in
  loop ()
```

`clear` and `to_list` are called only from the loop (single-threaded, after
drain), so they use plain `Atomic.Loc.set` / `Atomic.Loc.get` without CAS.

### Frame flow

```
collect — Signals → Events → Commands
tick    — Progress.tick; any system calls Audio_command_buffer.add
drain   — Signals → Commands → Events
loop    — Platform.Rendering_backend.render stream ~dt
          Platform.Audio_backend.submit (Audio_command_buffer.to_list buf)
          Audio_command_buffer.clear buf
```

The buffer is cleared *after* submit, not before tick, so the loop always submits
the commands accumulated during the current frame.

### Any system can write to it

There is no dedicated engine-level audio system. Any game system that detects a
trigger appends the appropriate command:

```ocaml
(* combat system detects a hit *)
let buf = World.get_data world `Audio_command_buffer in
Audio_command_buffer.add buf (Play_sound { id="hit_01"; instance_id=None;
                                           volume=0.9; pitch=1.0; pan=0.0; loop=false })

(* spatial audio system updates a looping emitter *)
Audio_command_buffer.add buf (Set_volume (iid, attenuated_vol));
Audio_command_buffer.add buf (Set_pan    (iid, computed_pan))
```

### Voice budget prioritization

The backend has a finite voice budget (typically 32–64 simultaneous sounds).
If needed, a dedicated prioritization system can run after all audio-producing
systems, read the buffer via `to_list`, cull low-priority commands, and replace
the buffer contents before the loop calls submit. This system sees all requests
for the frame in one place — the same property the old single-system design relied
on, now achieved through the shared buffer.

---

## 7. Example: Game-layer Audio

The engine ships no audio components and no audio systems. The examples below
illustrate what game code might look like — they are not part of `eon_engine`.

### Spatial audio (example)

A game that wants distance-attenuated looping sounds might define its own
`Sound_emitter` and `Sound_listener` components and a system that queries them:

```ocaml
let emitter_instance_id view =
  "emitter:" ^ Entity_id.to_string (View.entity view)

let update world _dt =
  let buf      = World.get_data world `Audio_command_buffer in
  let listener = World.get_data world Sound_listener.key in
  Query.from world
  |> Query.having Sound_emitter.name
  |> Query.iter (fun view ->
       let emitter = View.get view (module Sound_emitter) in
       let pos     = View.get view (module Position) in
       let iid     = emitter_instance_id view in
       let dist    = distance listener.position pos in
       if dist > emitter.range then begin
         if emitter.playing then
           Audio_command_buffer.add buf (Stop_sound iid)
       end else begin
         let vol = emitter.volume *. attenuation dist emitter.range in
         let pan = compute_pan listener.position pos in
         if not emitter.playing then
           Audio_command_buffer.add buf
             (Play_sound { id=emitter.sound_id; instance_id=Some iid;
                           volume=vol; pitch=1.0; pan; loop=true })
         else begin
           Audio_command_buffer.add buf (Set_volume (iid, vol));
           Audio_command_buffer.add buf (Set_pan    (iid, pan))
         end
       end)
```

### One-shot SFX (example)

Any system reacting to an event appends directly — no dedicated audio system needed:

```ocaml
let on_enemy_died world =
  let buf = World.get_data world `Audio_command_buffer in
  Audio_command_buffer.add buf
    (Play_sound { id="death_01"; instance_id=None;
                  volume=0.8; pitch=1.0; pan=0.0; loop=false })
```

One-shot sounds use `instance_id = None` — fire-and-forget. The backend manages
the voice lifetime.

---

## 8. Bus Integration

Audio commands are plain data and can be appended to `Audio_command_buffer` from
any context — signal handlers, system updates, or direct game logic. The trigger
mechanism is a game decision:

| Trigger | Example | Where the append happens |
|---------|---------|--------------------------|
| Event-driven | Skill SFX, death sound, UI click | Signal handler or system reacting to an event |
| Polled / spatial | Monster growl, ambient fire | System querying position each frame |
| Global state change | Music track change | System reading a music resource |

One-shot audio Signals are **local-only** and never cross the network — same rule
as input Signals. Remote clients receive the game state event that caused the sound
(`Enemy_died`, `Skill_used`) and their local systems append the sound independently.
Audio is never replicated; only game state is.

---

## 9. Sound Effects vs Music

| | Sound Effects | Music |
|---|---|---|
| Length | Short (< 5s) | Long (minutes) |
| Memory | Loaded fully into RAM as PCM | Streamed from disk, decoded in chunks |
| Voices | Regular voice slot | Separate streaming voice |
| Decoding | At load time | On a dedicated streaming thread |
| Format | WAV preferred (no decode cost) | OGG preferred (compression) |

The backend handles the streaming/decoding difference internally. The engine always
sends the same `Play_music` / `Play_sound` commands regardless.

---

## 10. Loop and Platform.S Integration

`Audio_backend` completes the Platform.S trifecta:

```ocaml
module type S = sig
  type t
  module Rendering_backend : Rendering_backend.S
  module Input_backend     : Input_backend.S
  module Audio_backend     : Audio_backend.S    (* ← completes the trifecta *)
end

module Raylib_platform : Platform.S = struct
  type t = [ `Raylib ]
  module Rendering_backend = Raylib_rendering_backend
  module Input_backend     = Raylib_input_backend
  module Audio_backend     = Raylib_audio
end

module Headless : Platform.S = struct
  type t = [ `Headless ]
  module Rendering_backend = Null_rendering_backend
  module Input_backend     = Null_input_backend
  module Audio_backend     = Audio_backend.Null   (* silent; CI runs without a sound device *)
end
```

`Loop.Make` calls `Platform.Audio_backend.init (module Assets)` at startup and
`Platform.Audio_backend.shutdown ()` on exit. After drain each frame, the loop
reads `Audio_command_buffer` from the world data plane, calls
`Platform.Audio_backend.submit (Audio_command_buffer.to_list buf)`, then clears
the buffer.

---

## 11. Module Layout

```
eon_engine/
  audio/
    audio_backend.ml/.mli        (* module type S = sig val init / submit / shutdown end *)
    audio_command.ml/.mli        (* command type: Play_sound, Stop_sound, Play_music, ... *)
    audio_command_buffer.ml/.mli (* per-frame accumulator; stored in world data plane *)
    audio_backend.ml/.mli        (* module type S + Null submodule — mirrors Input_backend pattern *)
    (* raylib.ml — in game layer, not engine; wraps InitAudioDevice / PlaySound *)
  input/
    ...                          (* existing: key, mouse_button, gamepad_button, raw_input_frame, input_backend *)
  render/
    ...                          (* future *)

(* game layer — not part of eon_engine *)
game/
  components/
    sound_emitter.ml           (* example: looping / spatial sounds on entities *)
    sound_listener.ml          (* example: player position for spatial attenuation *)
    music_state.ml             (* example: world resource for current track *)
  systems/
    spatial_audio_system.ml    (* example: queries emitters, appends to Audio_command_buffer *)
```

---

## 12. What NOT to Do

- **Do not call audio functions from the game loop directly.** The audio backend
  owns the callback thread. Calling `PlaySound` from a system is safe in raylib
  but is an implementation accident — route everything through the command list so
  the backend seam is respected.

- **Do not block in the audio callback.** If you implement a custom backend, the
  callback must return immediately. No allocations, no locks, no I/O. Violating
  this causes audio dropouts that are platform-specific and nearly impossible to
  reproduce.

- **Do not replicate audio over the network.** Audio is local. Game state
  (`Enemy_died`, `Skill_used`) is replicated; each client's AudioSystem plays
  sounds independently. Sending audio commands over the network wastes bandwidth
  and causes desync.

- **Do not call `Audio_backend.submit` from game systems directly.** All commands
  go through `Audio_command_buffer`. The loop owns the single `submit` call each
  frame. Systems that bypass the buffer break the frame ordering and make
  prioritization impossible.

- **Do not load music fully into memory.** A 5-minute OGG file is hundreds of MB
  uncompressed. Use `Play_music` (streaming) not `Play_sound` (in-memory) for
  anything longer than a few seconds.

- **Do not hardcode sound ids in systems.** Sound ids belong in data — component
  fields, mapping tables, or EDN config. Systems should not contain string literals
  for asset names.

---

## 13. Key Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Backend contract | `init / submit / shutdown` | Minimal seam; backend owns callback, mixer, ring buffer |
| Backend implementation | Wrap raylib/miniaudio | Real-time audio is treacherous to implement correctly; existing libs handle platform fragmentation |
| Command accumulator | `Audio_command_buffer` in world data plane | Mirrors `Render_stream`; any system appends, loop submits once per frame |
| Engine ships no audio systems or components | Game layer responsibility | Engine cannot know game's component structure; same philosophy as rendering collectors |
| Voice prioritization | Optional game-layer system reading the buffer before submit | Buffer collects all frame requests in one place; a single prioritization pass sees everything |
| Network boundary | Audio is local-only | Game state is replicated; each client's systems append sounds independently |
| Platform.S trifecta | Rendering_backend + Input_backend + Audio_backend | Compiler-enforced porting checklist; Headless bundles all no-ops |
