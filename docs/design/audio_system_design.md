# Audio System Design — `eon_engine`

## Status

**DRAFT** (no task assigned yet). Design decisions captured from architecture
discussion. Implementation task to be created later.

---

## 1. Scope

This document specifies the audio system for `eon_engine`. It covers:

- `Audio_backend.S` — the platform seam, completing the PLATFORM trifecta
- `Audio_command` — the vocabulary the engine sends to the backend
- Audio components — `Audio_emitter`, `Audio_listener`, `Music_state`
- `AudioSystem` — queries components, reacts to Signals, sends commands to backend
- Voice budget and prioritization — why one system must see all requests at once
- Bus integration — Signals for one-shot SFX, components for looping/spatial
- Loop and PLATFORM integration
- What NOT to do

The design follows the same philosophy as the renderer and input system: engine
defines the seam, backend fills it, one function is the entire contract, porting
means implementing that function. The recommended default backend is `Raylib_audio`
(backed by miniaudio internally).

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
│ eon_engine (game tick — 60fps)                              │
│                                                             │
│  AudioSystem (World.ro — parallel)                          │
│    queries Audio_emitter components → distance / pan        │
│    reads   Audio_listener resource  → player position       │
│    reads   Music_state resource     → current track         │
│    reacts  to Signals bus           → one-shot SFX          │
│    accumulates Audio_command list                           │
│    → Audio_backend.submit commands                            │
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

(* Null — silent; used in Headless platform for CI and tests *)
module Null_audio : Audio_backend.S = struct
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

`instance_id` is a stable, caller-provided string that the backend maps to an
internal voice slot. The backend owns voice allocation entirely — no handle leaks
into the public API. Game code uses string identifiers throughout; the backend
resolves them to internal handles via `Asset_lookup.S` at `init` time.

For fire-and-forget one-shot sounds, `instance_id = None` — the backend manages
the voice lifetime and the caller never needs to reference it again. For looping or
spatial sounds that need stopping or updating, the caller provides a stable string
(typically derived from the entity id) and reuses it across frames.

---

## 6. Audio Components

### 6.1 `Audio_emitter`

Attached to any entity that produces continuous or looping sound — monsters,
ambient sources, fire, traps:

```ocaml
type t = {
  sound_id : string;
  volume   : float;
  range    : float;   (* world units; beyond this distance: silent *)
  loop     : bool;
  playing  : bool;   (* AudioSystem tracks this; drives play/stop commands *)
}
```

The AudioSystem queries all emitters each frame, computes distance and pan from
the listener position, and starts/stops/updates the corresponding backend voice.
The instance id for each emitter is derived from the entity id — `"emitter:" ^
Entity_id.to_string (View.entity view)` — so the backend can be addressed without
storing any backend-opaque state in the component.

### 6.2 `Audio_listener`

Typically on the player entity or the camera entity. The AudioSystem reads this
to compute spatial attenuation and pan for all emitters:

```ocaml
type t = {
  position    : float * float;   (* world space *)
}
```

There should be exactly one `Audio_listener` in the world at any time. If none is
present, the AudioSystem skips spatial audio and plays all emitters at full volume
with centred pan.

### 6.3 `Music_state` (world resource)

Global, not per-entity. The AudioSystem reads this resource and manages track
transitions:

```ocaml
type transition =
  | Hard_cut
  | Crossfade of float   (* duration in seconds *)

type t = {
  current_track : string option;
  next_track    : string option;
  transition    : transition;
  volume        : float;
}
```

Game systems write to `Music_state` to request track changes. The AudioSystem
detects the change and issues the appropriate backend command.

---

## 7. The AudioSystem

### 7.1 Structure

The AudioSystem has two parts — same ro/rw split as every other eon system:

- **`update` (World.ro, parallel)** — queries emitters, reads listener, reads
  `Music_state`, accumulates the command list. Does not write to the world.
- **`on_signal` handlers (World.rw, sequential)** — react to game Signals for
  one-shot SFX. Write handles back into components if needed.

### 7.2 The polling path — looping and spatial sounds

Each frame, the spatial update:

```ocaml
let emitter_instance_id view =
  "emitter:" ^ Entity_id.to_string (View.entity view)

let update world _dt =
  let listener = World.get_data world Audio_listener in
  let commands = Buffer.create 16 in
  Query.from world
  |> Query.having Audio_emitter.name
  |> Query.iter (fun view ->
       let emitter = View.get view (module Audio_emitter) in
       let pos     = View.get view (module Position) in
       let iid     = emitter_instance_id view in
       let dist    = distance listener.position pos in
       if dist > emitter.range then begin
         if emitter.playing then
           Buffer.add commands (Stop_sound iid)
       end else begin
         let vol = emitter.volume *. attenuation dist emitter.range in
         let pan = compute_pan listener.position pos in
         if not emitter.playing then
           Buffer.add commands (Play_sound { id=emitter.sound_id; instance_id=Some iid;
                                             volume=vol; pitch=1.0; pan; loop=true })
         else begin
           Buffer.add commands (Set_volume (iid, vol));
           Buffer.add commands (Set_pan    (iid, pan))
         end
       end);
  Audio_backend.submit (Buffer.contents commands)
```

### 7.3 The reactive path — one-shot SFX

Game events trigger sounds via the Signals bus. The AudioSystem subscribes to
relevant signals and fires play commands. The audio system does not need to know
about game entities — it just maps signal → sound:

```ocaml
let on_signal _world = function
  | `Enemy_died    -> Audio_backend.submit [Play_sound { id="death_01"; instance_id=None;
                                           volume=0.8; pitch=1.0; pan=0.0; loop=false }]
  | `Skill_used id -> Audio_backend.submit [Play_sound { id=sfx_for_skill id;
                                           instance_id=None; volume=1.0;
                                           pitch=1.0; pan=0.0; loop=false }]
  | `Player_hit    -> Audio_backend.submit [Play_sound { id="hit_grunt"; instance_id=None;
                                           volume=0.9; pitch=1.0; pan=0.0; loop=false }]
  | _              -> ()
```

One-shot sounds are fire-and-forget — `instance_id = None` because there is no
need to stop them; they finish on their own. The backend manages the voice lifetime.

### 7.4 Voice budget and prioritization

The audio backend has a finite voice budget — typically 32–64 simultaneous sounds.
Exceeding it means the backend must evict a voice. This is why **one AudioSystem
must see all sound requests in the same frame** — split systems cannot prioritize
across each other.

When the frame produces more play commands than available voices, the AudioSystem
culls by priority before calling `submit`:

1. Music — never culled
2. Player sounds (hit, skill) — highest SFX priority
3. Nearby emitters — sorted by distance, closest kept
4. Far emitters — dropped first

This prioritization logic lives in the AudioSystem, not the backend. The backend
just executes what it receives.

---

## 8. Bus Integration

Same hybrid as the input system — two modalities, two mechanisms:

| Modality | Example | Mechanism |
|----------|---------|-----------|
| Continuous / spatial | Monster growl, ambient fire | `Audio_emitter` component, polled every frame |
| One-shot | Skill SFX, death sound, UI click | Signal on local bus → `on_signal` handler |
| Global state | Background music, master volume | `Music_state` / global resource |

One-shot audio Signals are **local-only** and never cross the network — same rule
as input Signals. Remote clients receive the game command that caused the sound
(`Enemy_died`, `Skill_used`) and their local AudioSystem plays the sound
independently. Audio is never replicated; only game state is.

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

## 10. Loop and PLATFORM Integration

The AudioSystem is a regular ECS system registered in the pipeline. `Audio_backend`
completes the PLATFORM trifecta:

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
  module Audio_backend     = Null_audio   (* silent; CI runs without a sound device *)
end
```

`Loop.Make` calls `Platform.Audio_backend.init (module Assets)` at startup (after
the asset lookup is constructed) and `Platform.Audio_backend.shutdown ()` on exit.
The AudioSystem calls `Platform.Audio_backend.submit` at the end of each tick.

---

## 11. Module Layout

```
eon_engine/
  audio_backend.ml/.mli       (* module type S = sig val init / submit / shutdown end *)
  audio_command.ml/.mli       (* command type: Play_sound, Stop_sound, Play_music, ... *)
  audio_components/
    audio_emitter.ml/.mli     (* looping / spatial sounds on entities *)
    audio_listener.ml/.mli    (* player position for spatial attenuation *)
    music_state.ml/.mli       (* world resource: current track, transition *)
  audio_system.ml/.mli        (* World.ro update + on_signal handlers *)
  audio_backends/
    null.ml                   (* Null_audio — silent, for Headless platform *)
    (* raylib.ml — in game layer, not engine; wraps InitAudioDevice / PlaySound *)
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

- **Do not split audio into multiple systems without a shared prioritization step.**
  The voice budget is global. Two systems that each independently decide to play
  sounds cannot prioritize against each other. One AudioSystem sees all requests.

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
| Command delivery | Accumulated list, submitted once per frame | Matches game tick cadence; allows prioritization before submit |
| One-shot SFX | Signals bus → `on_signal` | Fire-and-forget; decoupled from game entities |
| Looping/spatial | `Audio_emitter` component, polled | Needs per-frame position update and distance attenuation |
| Music | `Music_state` world resource | Global, not per-entity; engine manages streaming lifecycle |
| Voice prioritization | Single AudioSystem sees all requests | Voice budget is global; split systems cannot cross-prioritize |
| Network boundary | Audio is local-only | Game state is replicated; each client plays sounds independently |
| Platform.S trifecta | Rendering_backend + Input_backend + Audio_backend | Compiler-enforced porting checklist; Headless bundles all no-ops |
