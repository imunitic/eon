# Resource.S and Service.S Design — `eon_engine`

## Status

**DRAFT**. Design decisions captured for review. Implementation task to be
created after design is finalised.

---

## 1. Motivation

The raw world data and service planes use open polymorphic variants as keys:

```ocaml
World.get_data    world `Raw_input_frame
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
`World.t` throughout this document means `Eon_engine.World.t`.

---

## 2. Resource.S

A resource is per-frame mutable world data — written by the loop or by
exclusive systems, read by any system. Examples: `Raw_input_frame`,
`Audio_command_buffer`, a per-frame delta time record.

```ocaml
module type S = sig
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
`Resource.S` interface is a typed facade over the existing storage:

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
to this resource's storage slot.

---

## 3. Resource Module Helpers

The `Resource` module (which contains `module type S` and `module Make`)
also provides two convenience helpers that take a first-class `Resource.S`
module:

```ocaml
val get : [> World.ro] World.t -> (module S with type t = 'a) -> 'a
val set : World.rw World.t     -> (module S with type t = 'a) -> 'a -> unit
```

These are thin wrappers — `Resource.get world (module R)` is `R.fetch world`.
Their value is at call sites where the resource module is a variable rather
than a known name, and for cross-world access where `Namespace.named` resolves
the world first:

```ocaml
(* direct — preferred when the module is known *)
Raw_input_frame.fetch world

(* via helper — useful when composing with Namespace *)
Resource.get world (module Raw_input_frame)
Resource.get (Namespace.named "global" ns) (module Raw_input_frame)
```

The phantom type constraints are preserved: `get` accepts `[> ro]`, `set`
requires `rw`. A parallel system cannot call `set` — type error.

---

## 4. Service.S

A service is a long-lived singleton registered at startup and never mutated
by game systems. Examples: `Steam_api`, a physics world handle, a network
session context.

```ocaml
module type S = sig
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
system is wrong even if the type allows it. The naming distinction
(`store` vs `register`) signals this asymmetry:

| | Resource | Service |
|---|---|---|
| Lifetime | Per-frame / simulation | Startup to shutdown |
| Written by | Loop or exclusive systems | Startup code only |
| Read by | Any system | Any system |
| Write fn name | `store` | `register` |
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

## 5. Service Module Helpers

The `Service` module provides matching helpers:

```ocaml
val get      : [> World.ro] World.t -> (module S with type t = 'a) -> 'a
val register : World.rw World.t     -> (module S with type t = 'a) -> 'a -> unit
```

Same pattern as `Resource` — `Service.get world (module S)` is `S.fetch world`.
Composes with `Namespace.named` for cross-world access:

```ocaml
(* direct *)
Steam_api.fetch world

(* via helper — useful with Namespace *)
Service.get      world              (module Steam_api)
Service.get      (Namespace.named "global" ns) (module Steam_api)
Service.register (Namespace.named "global" ns) (module Steam_api) steam_instance
```

---

## 6. Make_resource and Make_service Functors

When a game defines many resources or services the per-module boilerplate
becomes repetitive. `Make_resource` and `Make_service` capture the common case:

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

Each definition reduces to the two things that actually differ — the type
and the key:

```ocaml
module Delta_time    = Resource.Make(struct type t = float        let key = `Delta_time    end)
module Level_config  = Resource.Make(struct type t = Config.t     let key = `Level_config  end)
module Physics_state = Resource.Make(struct type t = Physics.t    let key = `Physics_state end)

module Steam_api     = Service.Make(struct  type t = Steam.t      let key = `Steam_api     end)
module Analytics     = Service.Make(struct  type t = Analytics.t  let key = `Analytics     end)
```

Modules with non-trivial logic — like `Audio_command_buffer` which has `add`,
`clear`, and `to_list` on top of `fetch`/`store` — write the full module
manually. `Make` is for the common case, not a requirement.

---

## 7. Migration of Existing Modules

Modules that already have `get`/`set` or `get`/`add` functions adopt
`Resource.S` or `Service.S` by renaming:

| Module | Current API | New API |
|--------|-------------|---------|
| `Raw_input_frame` | `get world`, `set world frame` | `fetch world`, `store world frame` |
| `Audio_command_buffer` | `get world`, `set world buf` | `fetch world`, `store world buf` |

The underlying storage (polymorphic variant key + `World.get_data` /
`World.set_data`) does not change.

---

## 8. No World-Level Registry

`Resource.S` and `Service.S` are **module-level contracts**, not a
registration mechanism. The world does not maintain a list of known
resources or services. Each module self-describes — if you have the module,
you can call `fetch`; if you have a `rw` world, you can call `store` or
`register`. Discovery is a compile-time concern, not a runtime one.

The direct form is always available:

```ocaml
Raw_input_frame.fetch world
Steam_api.fetch world
```

`Resource.get` / `Service.get` are helpers for composing with `Namespace`,
not a replacement for the direct form.

---

## 9. Cross-World Access

`Resource.S` and `Service.S` are **local-store only**. `fetch` and `store`
always access the world passed directly — no namespace parameter, no
awareness of other worlds. This is by design: a resource module is a typed
accessor for one piece of data; where that data lives in the world topology
is not its concern.

Cross-world access is the composition of `Namespace.named` (world lookup)
with `Resource.get` / `Service.get` (typed access):

```ocaml
(* local *)
Resource.get world (module Raw_input_frame)

(* cross-world — Namespace resolves the world, Resource.get accesses it *)
Resource.get (Namespace.named "global" ns) (module Raw_input_frame)
Service.get  (Namespace.named "global" ns) (module Steam_api)
```

`Namespace` and `Resource`/`Service` have no dependency on each other.
`Namespace.named` returns a `World.t`; `Resource.get` takes a `World.t`.
The composition is the API.

### Example aggregator

Game developers who want named shorthand accessors can build an aggregator
module — their choice, not a requirement:

```ocaml
(* game/world_ns.ml *)
module World_ns = struct
  let ns = Namespace.create ()

  let init steam_instance global_world =
    Namespace.attach ns "global" global_world;
    Service.register (Namespace.named "global" ns) (module Steam_api) steam_instance

  let input world = Resource.get world (module Raw_input_frame)
  let audio world = Resource.get world (module Audio_command_buffer)
  let steam ()    = Service.get  (Namespace.named "global" ns) (module Steam_api)
end

(* in a system — no first-class modules at call sites *)
let update world _dt =
  let input = World_ns.input world in
  let steam = World_ns.steam () in
  ...
```

---

## 10. What NOT to Do

- **Do not call `store` from parallel systems.** `store` requires `rw` and
  parallel systems hold `ro` — the compiler prevents it. Route writes through
  a command bus and handle them in an exclusive system.

- **Do not call `register` after the loop starts.** Services are startup
  singletons. Registering one mid-simulation is undefined behaviour in terms
  of what other systems observe that frame.

- **Do not use `Resource.S` for component data.** Components have their own
  typed API (`add_component`, `set_component`, `get_component`). Resources
  are for world-scoped singleton data, not per-entity data.

- **Do not add `fetch_opt` unless the resource is genuinely optional.**
  Most resources are always present once the loop starts. An absent resource
  is a programming error — fail loudly. Add `fetch_opt` per-module only if
  the absence is a legitimate runtime condition.

---

## 11. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Direct form | `Raw_input_frame.fetch world` | Module is the API; no indirection; no World-level registry |
| Phantom types on `fetch` / `store` | `[> World.ro]` / `World.rw` | Parallel systems read; exclusive systems write; compiler-enforced |
| `store` vs `register` naming | `store` for Resource, `register` for Service | Signals intent: per-frame mutation vs startup singleton |
| No new storage layer | Polymorphic variant keys + `get_data`/`set_data` | Typed facade only; no migration cost to storage |
| Keys are private | Not exposed in `S` signatures | Encapsulation — only the module accesses its slot |
| `fetch` raises on absent | Fail loudly | Absent resource is a programming error; add `fetch_opt` per-module if genuinely optional |
| `Make` functors | Convenience, not required | Eliminates boilerplate for simple cases; richer modules (e.g. `Audio_command_buffer`) write manually |
| `Resource.get` / `Service.get` helpers | On `Resource` / `Service` modules, not on `Namespace` | Namespace resolves worlds; Resource/Service access data — orthogonal concerns that compose |
| No `?ns` anywhere | Namespace routing is explicit composition | `Resource.get (Namespace.named "global" ns) (module R)` — each step visible and independently useful |
| Cross-world access pattern | `Resource.get (Namespace.named "global" ns) (module R)` | Composable; no coupling between Namespace and Resource/Service |
