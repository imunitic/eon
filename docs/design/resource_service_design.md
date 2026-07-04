# Resource.S and Service.S Design — `eon_engine`

## Status

**DRAFT**. Design decisions captured for review. Implementation task to be
created after design is finalised.

---

## 1. Motivation

The current world data plane and service plane use open polymorphic variants
as keys:

```ocaml
World.get_data world `Raw_input_frame
World.get_service world `Steam_api
```

This works but has two weaknesses:

- **The key and the type are not formally connected.** Nothing prevents
  `get_data world \`Raw_input_frame` from returning an `Audio_command_buffer.t`
  if someone stored the wrong type under that key. The connection lives in
  convention, not the type system.
- **No access semantics.** `get_data` accepts any `'perm World.t` regardless
  of whether the call site is a parallel system (should only read) or an
  exclusive system (may write). The `ro`/`rw` distinction is enforced for
  components but not for resources or services.

`Resource.S` and `Service.S` solve both. Each module carries its own typed
`fetch` and `store` functions, with phantom-type constraints that make
read-only access available everywhere and writes exclusive to `rw` worlds.
`World.t` here means `Eon_engine.World.t` — the phantom-typed wrapper around
`Eon_ecs.World.t` described in `data_service_plane_namespacing.md`.

---

## 2. Resource.S

A resource is per-frame mutable world data — written by the loop or by
exclusive systems, read by any system. Examples: `Raw_input_frame`,
`Audio_command_buffer`, a per-frame delta time record.

```ocaml
module type Resource.S = sig
  type t

  val fetch : [> World.ro] World.t -> t
  (** Available on both [ro] and [rw] worlds — any system can read. *)

  val store : World.rw World.t -> t -> unit
  (** Only available on [rw] worlds — exclusive systems and the loop. *)
end
```

### Access semantics

`World.ro = [ \`R ]` and `World.rw = [ \`R | \`W ]`. The constraint
`[> World.ro]` means "at least `\`R`" — satisfied by both `ro` and `rw`.
`store` requires exactly `rw`.

Consequence: a parallel system holding `World.ro World.t` can call `fetch`
on any resource. The compiler physically prevents it from calling `store`.
No runtime check, no guard — a type error at the call site.

```ocaml
(* parallel system — ro world *)
let update (world : World.ro World.t) _dt =
  let frame = Raw_input_frame.fetch world in   (* ok *)
  Raw_input_frame.store world frame            (* type error — rw required *)

(* exclusive system — rw world *)
let update (world : World.rw World.t) _dt =
  let frame = Raw_input_frame.fetch world in   (* ok — rw satisfies [> ro] *)
  Raw_input_frame.store world frame            (* ok *)
```

### Implementation pattern

Each resource module keeps its own private polymorphic variant key. The
`Resource.S` interface is a typed facade over the existing storage — the
internal representation does not change:

```ocaml
(* raw_input_frame.ml *)
type t = { keys_down : Key.Set.t; ... }

let key = `Raw_input_frame

let fetch world =
  match World.get_data world key with
  | Some f -> f
  | None   -> empty

let store world frame = World.set_data world key frame
```

`World.get_data` and `World.set_data` are the underlying primitives.
`Resource.S` is a module-level contract, not a new storage layer. Keys are
private — nothing outside the module can construct a correctly typed access
to this resource's slot.

---

## 3. Service.S

A service is a long-lived singleton registered at startup and never mutated
by game systems. Examples: `Steam_api`, a physics world handle, a network
session context.

```ocaml
module type Service.S = sig
  type t

  val fetch : [> World.ro] World.t -> t
  (** Available on both [ro] and [rw] worlds. *)

  val register : World.rw World.t -> t -> unit
  (** Called once at startup before the loop starts. Not intended for
      use inside pipeline systems. *)
end
```

`register` exists in the interface so the module is self-contained, but it
is semantically a startup operation — calling it from inside a running
system is wrong even if the type allows it. The distinction between
`Resource` and `Service` is semantic, not enforced by a separate type:

| | Resource | Service |
|---|---|---|
| Lifetime | Per-frame / simulation | Startup to shutdown |
| Written by | Loop or exclusive systems | Startup code only |
| Read by | Any system | Any system |
| Typical examples | `Raw_input_frame`, `Audio_command_buffer` | `Steam_api`, physics handle |

```ocaml
(* steam_api.ml *)
type t = { app_id : int; ... }

let key = `Steam_api

let fetch world =
  match World.get_service world key with
  | Some s -> s
  | None   -> failwith "Steam_api not registered"

let register world api = World.add_service world key api
```

---

## 4. Migration of Existing Modules

Modules that already have `get`/`set` or `get`/`add` functions adopt
`Resource.S` or `Service.S` by renaming or aliasing:

| Module | Current API | New API |
|--------|-------------|---------|
| `Raw_input_frame` | `get world`, `set world frame` | `fetch world`, `store world frame` |
| `Audio_command_buffer` | `get world`, `set world buf` | `fetch world`, `store world buf` |

The underlying storage (polymorphic variant key + `World.get_data` /
`World.set_data`) does not change. Only the function names and phantom-type
constraints are updated.

---

## 5. No World-Level Registry

`Resource.S` and `Service.S` are **module-level contracts**, not a
registration mechanism. The world does not maintain a list of known
resources or services. Each module self-describes — if you have the module,
you can call `fetch`; if you have a `rw` world, you can call `store` or
`register`. Discovery is a compile-time concern, not a runtime one.

The module *is* the API. No indirection:

```ocaml
(* not this *)
World.get_resource world (module Raw_input_frame)

(* this *)
Raw_input_frame.fetch world
```

---

## 6. Make_resource and Make_service Functors

When a game defines many resources or services the per-module boilerplate
becomes repetitive — `type t`, a private key, `fetch`, `store` / `register`
are identical in structure across all of them. `Make_resource` and
`Make_service` capture that invariant:

```ocaml
(* eon_engine/resource.ml *)
module Make (T : sig
  type t
  val key : [> ]
end) : S with type t = T.t = struct
  type t = T.t
  let fetch world =
    match World.get_data world T.key with
    | Some v -> v
    | None   -> failwith "resource not registered"
  let store world v = World.set_data world T.key v
end

(* eon_engine/service.ml *)
module Make (T : sig
  type t
  val key : [> ]
end) : S with type t = T.t = struct
  type t = T.t
  let fetch world =
    match World.get_service world T.key with
    | Some v -> v
    | None   -> failwith "service not registered"
  let register world v = World.add_service world T.key v
end
```

A game with many resources reduces each definition to just the two things
that actually differ — the type and the key:

```ocaml
module Delta_time    = Resource.Make(struct type t = float      let key = `Delta_time    end)
module Level_config  = Resource.Make(struct type t = Config.t   let key = `Level_config  end)
module Physics_state = Resource.Make(struct type t = Physics.t  let key = `Physics_state end)

module Steam_api     = Service.Make(struct type t = Steam.t     let key = `Steam_api     end)
module Analytics     = Service.Make(struct type t = Analytics.t let key = `Analytics     end)
```

Modules with non-trivial `fetch` logic — like `Audio_command_buffer` which
has `add`, `clear`, and `to_list` on top of `fetch`/`store` — still write
the full module manually and satisfy `Resource.S` explicitly. `Make` is for
the common case, not a requirement.

---

## 7. Composition with Namespace.S

`Resource.S` and `Service.S` are **local-store only**. `fetch` and `store`
always access the world passed directly to them — they have no knowledge of
namespace routing, no `?ns` parameter, and no awareness that other worlds
exist. This is by design: a resource module is a typed accessor for one
piece of data; where that data lives in the world graph is not its concern.

Cross-world access is the job of `Namespace.S`, described in full in
`data_service_plane_namespacing.md`. `Namespace.get_resource` resolves the
target world first, then delegates to `Resource.S.fetch` as a plain local
access:

```ocaml
(* inside Namespace *)
let get_resource (module R : Resource.S) ns_t = R.fetch (resolve ns_t)
```

`Resource.S` and `Service.S` are unmodified — the routing is transparent.

### The aggregator pattern

The recommended way to combine `Resource.S`, `Service.S`, and `Namespace.S`
is an aggregator module that centralises all resource and service definitions
for a world. It serves as the single registration point at startup and
exposes named shorthand accessors throughout the codebase:

```ocaml
(* game/world_ns.ml *)
module World_ns = struct
  include Namespace.Local

  (* Named accessors — no first-class modules at call sites *)
  let physics world = get_resource (module Physics_state)        world
  let input   world = get_resource (module Raw_input_frame)      world
  let audio   world = get_resource (module Audio_command_buffer) world
  let steam   world = get_service  (module Steam_api)            world

  (* All registration in one place *)
  let init world steam_instance =
    reg_service  (module Steam_api)            world steam_instance;
    set_resource (module Audio_command_buffer) world (Audio_command_buffer.create ());
    set_resource (module Physics_state)        world (Physics_state.create ())
end

(* In a system — call sites use module paths, nothing else *)
let update world _dt =
  let ns    = World_ns.local world in
  let input = World_ns.input ns in
  let audio = World_ns.audio ns in
  Audio_command_buffer.add audio (Play_sound { id = "hit"; volume = 1.0; ... })
```

A game that never needs multiple connected worlds can skip `Namespace.S`
entirely and call `Raw_input_frame.fetch world` directly. The aggregator
pattern is an ergonomic choice, not a requirement.

---

## 8. What NOT to Do

- **Do not call `store` from parallel systems.** `store` requires `rw` and
  parallel systems hold `ro` — the compiler prevents it. If you need to
  write a resource from a parallel context, use a command bus and handle it
  in an exclusive system.

- **Do not call `register` after the loop starts.** Services are startup
  singletons. Registering one mid-simulation is undefined behaviour in
  terms of what other systems will observe that frame.

- **Do not use `Resource.S` for component data.** Components have their own
  typed API (`add_component`, `set_component`, `get_component`). Resources
  are for world-scoped singleton data, not per-entity data.

- **Do not add `fetch_opt` unless the resource is genuinely optional.**
  Most resources are always present once the loop starts. An absent resource
  is a programming error, not a normal condition — fail loudly rather than
  returning `None` silently.

- **Do not bypass `Namespace.S` for cross-world access.** Calling
  `World.get_ns` and then passing the result to `Resource.S.fetch` manually
  is exactly what `Namespace.get_resource` does — use it directly.

---

## 9. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module as accessor | `Raw_input_frame.fetch world` not `World.get_resource world (module ...)` | Module is the API; no indirection; no World-level registry |
| Phantom types on `fetch` / `store` | `[> World.ro]` / `World.rw` | Parallel systems can read; exclusive systems can write; compiler-enforced |
| `Resource.S` vs `Service.S` | Semantic distinction, not a type-level one | `store` vs `register` signals intent; both use same storage primitives |
| No new storage layer | Polymorphic variant keys + existing `get_data`/`set_data` | `Resource.S` is a typed facade; no migration cost to storage |
| Keys are private | Not exposed in `Resource.S` / `Service.S` | Encapsulation — only the module itself can access its storage slot; routing goes through `Namespace.S` |
| `fetch` raises on absent | Fail loudly | Absent resource is a programming error; `fetch_opt` can be added per-module if genuinely optional |
| `Make_resource` / `Make_service` functors | Provided as convenience, not required | Eliminates boilerplate for simple resources; modules with richer APIs (e.g. `Audio_command_buffer`) write the full module manually |
| `Resource.S` / `Service.S` are local-only | No `?ns` parameter | Cross-world routing is `Namespace.S`'s job; mixing concerns would require every resource to know about world topology |
| Aggregator pattern | Game-specific module wrapping `Namespace.S` | Named call-site ergonomics; single registration point; `eon_engine` provides machinery, not the specific resource names |
