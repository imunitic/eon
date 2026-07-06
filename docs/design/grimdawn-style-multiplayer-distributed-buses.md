# Multiplayer Architecture: Grim Dawn-Style Listen Server and Distributed Buses

## Status

**Exploratory.** No implementation is planned for the current game. This document records architectural thinking for future reference and establishes one forward-looking constraint on event design (§6).

## 1. Motivation and Scope

This document covers the multiplayer model that would be appropriate for the Eon game if multiplayer were ever added: a **Grim Dawn / Titan Quest-style listen server**, where one player hosts the session and other players connect to them directly. There are no dedicated servers, no server costs, and no capacity planning — the player provides the infrastructure.

This is explicitly **not** a Path of Exile-style architecture. PoE requires dedicated servers, server authority over a large player pool, client-side prediction with rollback, anti-cheat, and the full operational burden of a live service. That complexity is out of scope and unnecessary for a small co-op ARPG.

What this document also captures is a design insight about the Eon bus system: if game code is written to be **fully reactive** (all coordination through buses, all payloads plain data), then adding the listen server model later reduces primarily to implementing **distributed buses** — the game systems themselves do not change.

## 2. Render Stream Compatibility with Multiplayer

The render stream design (see `rendering_layer_design.md`) is already well-suited for multiplayer without any modification.

### 2.1 Server binary requires no renderer

The renderer is supplied at compile time via the `Platform.S` parameter of the engine loop. A server binary substitutes `Platform.Headless` (which contains a null renderer and null input backend) at that slot. All simulation code — systems, pipeline, progress, buses — is identical between client and server binaries. The rendering layer is never reached on the server.

### 2.2 Render_stream is derived data — never snapshot it

Client-side prediction and rollback require snapshotting and restoring world state. Because the `Render_stream` is computed *from* world state by `Render_system` during tick (not a source of truth), it is excluded from snapshots entirely. After rollback and re-simulation, the stream is re-derived automatically on the next frame.

### 2.3 Render_system is identifiable and skippable

During rollback re-simulation, only intermediate world states need to be computed — the intermediate frames are never rendered. Because rendering work lives in `Render_system` — a normal ECS system added to the pipeline at the `Render` phase — it can be skipped during re-simulation by not running the render phase. Only the final predicted frame runs the collector and renders.

### 2.4 Summary

The render stream boundary — `Render_system` populates it during tick, the engine loop reads it after drain and calls `Platform.Rendering_backend.render`, nothing else touches it — is exactly the right separation for any multiplayer model. Server = no renderer. Client = same simulation code + renderer.

## 3. Transport Layer: Wire-Compatible Pure OCaml ENet Port

ENet is a reliable UDP networking library widely used in games (Cube/Sauerbraten and many others). It provides reliable ordered delivery, unreliable sequenced delivery, channels, connection management, and fragmentation — all on top of UDP, avoiding TCP's head-of-line blocking.

### 3.1 Rationale for a pure OCaml port

There are no maintained OCaml bindings for ENet on opam. The options are:

| Approach | Tradeoff |
|---|---|
| Write ctypes bindings | One-time C FFI work; depends on ENet C library at runtime |
| Pure OCaml port | No C dependency; complete control; more initial work |
| Raw UDP + custom reliability | Reinventing ENet; weeks of work; easy to get wrong |
| TCP | Wrong for game networking; head-of-line blocking |

A pure OCaml port is the right call: ENet's C API is small and its protocol is documented in `protocol.h`. The result lives in `eon_engine` as a transport concern, not in `eon_ecs`.

### 3.2 Wire compatibility

The goal is **ENet wire protocol compatibility** — the same relationship as ScyllaDB to Apache Cassandra. The implementation speaks the exact ENet packet format and can interoperate with any existing ENet peer (C server, C# client, etc.). This is a stronger guarantee than "inspired by ENet" and preserves the option of mixed deployments.

Wire compatibility requires: byte-exact packet layout, big-endian byte order throughout, and the exact ENet handshake sequence. The exact struct layouts live in ENet's `protocol.h` and must be studied carefully before writing the codec.

### 3.3 Command subset needed

For a listen server with small player counts, only a subset of ENet commands is needed:

| Command | Purpose |
|---|---|
| `CONNECT` / `VERIFY_CONNECT` | Connection handshake |
| `DISCONNECT` | Clean teardown |
| `PING` | Heartbeat and keepalive |
| `ACKNOWLEDGE` | Acks for the reliable channel |
| `SEND_RELIABLE` | Ordered, retransmitted delivery |
| `SEND_UNRELIABLE` | Sequenced delivery, no retransmit |

Commands that can be skipped initially:

| Command | Why skippable |
|---|---|
| `SEND_FRAGMENT` / `SEND_UNRELIABLE_FRAGMENT` | Keep packets small by design |
| `BANDWIDTH_LIMIT` | Can be a no-op on receive |
| `THROTTLE_CONFIGURE` | Same |
| `SEND_UNSEQUENCED` | Not needed for game state sync |

### 3.4 Module structure (sketch)

```
eon_engine/net/
  enet_protocol.ml      (* wire codec: packet layout, big-endian marshalling *)
  enet_peer.ml          (* per-peer state machine: connecting → connected → disconnecting *)
  enet_host.ml          (* one host with N peer connections; poll via Unix.sendto/recvfrom *)
  enet_channel.ml       (* per-channel sequence numbers, ack tracking, retransmit queue *)
```

The transport layer is deliberately separate from the ECS. Network systems in the ECS pipeline call `Enet_host.service` to poll and send — they are ordinary systems, not special loop participants.

## 4. Grim Dawn-Style Listen Server

### 4.1 Architecture

```
Host process
├── Server systems   (authoritative simulation — physics, AI, input processing)
├── Client systems   (input capture, local rendering — for the host player)
└── Renderer         (host sees the game)
        ↕  direct in-process path (no serialization)

Remote client process
├── Client systems   (input capture, local view update)
└── Renderer
        ↕  ENet over network → host's server systems
```

The host player's "client" and "server" share the same process and the same world state. No serialization is needed for the host's own actions — their input goes directly onto the local Command bus. Remote clients communicate over ENet.

### 4.2 Binary configuration

One binary, a runtime flag:

- `--host`: registers server systems + client systems + renderer
- `--join <addr>`: registers client systems + renderer only

The ECS pipeline system set is the only thing that differs between the two roles. The ECS core, pipeline, progress, and loop are unchanged.

### 4.3 Operational properties

- No server infrastructure: players provide their own hardware and bandwidth
- No sunset problem: the game works forever; there is no server to shut down
- Session ends when the host quits — this is the accepted tradeoff for the genre
- Player count: 2–6; this is a small co-op session, not a raid or a MMO zone

## 5. Distributed Buses: The Elegant Path to Multiplayer

### 5.1 The core insight

The Eon bus system is already the coordination primitive for all game logic. Events happen, systems react, the frame advances. For a listen server, this extends naturally:

```
Remote player input:
  capture locally → serialize → ENet → host receives
  → deserialize → emit on host's Command bus
  → host simulation reacts as if the command was local

Host state delta:
  host simulation emits Event on host's Event bus
  → serialize → ENet → all remote clients receive
  → deserialize → emit on remote client's Event bus
  → remote client reacts as if the event was local
```

From any game system's perspective, **it does not know whether an event arrived from a local input or from the wire**. The bus is the bus. This is **location-transparent messaging** — the formal name for exactly this property.

### 5.2 What "adding multiplayer" would actually cost

If the game is written to be fully reactive (all coordination through buses, all payloads plain data — see §6), then adding Grim Dawn-style multiplayer reduces to:

1. **Implement distributed bus variants** — one-time work in `eon_engine`
2. **Wire up ENet transport** — one-time plumbing (§3)
3. **Switch the game to distributed buses** — swap at the functor application site

All game systems, all game logic, the entire ECS pipeline: **unchanged**.

### 5.3 Distributed bus variants (sketch)

**Listen server bus** (the straightforward model):

```
Remote client outgoing bus:
  on drain: serialize commands → enet_peer_send (reliable channel)

Host incoming bus:
  on collect: enet_host_service → deserialize → emit locally

Host outgoing bus:
  on drain: serialize state events → enet_host_broadcast

Remote client incoming bus:
  on collect: enet_host_service → deserialize → emit locally
```

**Lockstep bus** (if chosen over listen server):

```
All peers, each frame:
  1. Collect local input events, hold them
  2. Exchange input events with all peers via ENet (reliable channel)
  3. All peers emit all received inputs onto their local bus
  4. All peers advance frame N simultaneously
```

Lockstep maps especially cleanly onto the `Double_bus` (`Events`) semantics: the "next-frame" delay already accommodates one network round trip if the tick rate is modest (e.g., 20 Hz simulation). At 2–6 players over LAN or good internet, lockstep is viable and the bus abstraction holds almost perfectly.

### 5.4 The timing problem

The one place where "distributed buses = free multiplayer" breaks down is **frame time**. The ECS bus assumes a shared discrete "now" — frame N on one machine is frame N on every machine. The network breaks this: an event emitted by a remote peer arrives after some variable delay.

Every multiplayer architecture is an answer to this question:

| Architecture | Answer | Tradeoff |
|---|---|---|
| Lockstep | Wait for all inputs before advancing | Freezes if anyone lags |
| Listen server | Host's frame N is authoritative; late inputs applied to N+k or dropped | Host has zero-latency advantage |
| Client-side prediction | Client guesses, corrects later | Complex; overkill for this game type |

For the Grim Dawn model either lockstep or listen server is appropriate. At small player counts and good connectivity, the difference is rarely noticeable.

## 6. Forward-Looking Constraint: Events Must Be Plain Data

For the distributed buses model to work without modifying game code, every event and command payload must be **serializable over the wire**. This is the only design constraint that needs to be respected upfront — even if multiplayer is never shipped.

**What this means in practice:**

- Event and command payloads must be plain algebraic data types: no closures, no function values, no file handles, no world references, no mutable state
- This is good practice regardless of multiplayer (closures in event payloads make testing and reasoning harder)
- It does not require writing a serializer now — just keeping the door open

**What it does not mean:**

- No need to define a wire format now
- No need to version events now
- No need to think about schema evolution now

If payloads are kept as plain data from the start, every event type written for the single-player game is automatically multiplayer-ready — not because multiplayer was built, but because the constraint was respected.

## 7. Summary

| Concern | Decision |
|---|---|
| Multiplayer model | Grim Dawn-style listen server — host provides server + client in one process |
| Transport | Wire-compatible pure OCaml ENet port — no C dependencies, interoperable with ENet ecosystem |
| Abstraction | Distributed buses — game code unchanged, only bus implementations differ |
| Coordination model | Lockstep or listen server; both map onto existing bus semantics |
| Forward-looking constraint | All event/command payloads must be plain algebraic data (no closures, no world refs) |
| Current status | No implementation planned; this document records the design for future reference |

The render stream design, the bus architecture, and the ECS pipeline are already the right foundation. If multiplayer ever happens, it is an additive concern that slots in at the bus and transport layers — not a rearchitecture.
