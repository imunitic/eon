# Prefab System — Thought Dump

## Status

**IDEA** — not a task, not a draft, just captured so it doesn't get lost.

---

## The One-Liner

```ocaml
Prefab.load world "player"  (* -> Entity_id.t with all components attached *)
```

Load a named entity definition from some data source, get back a live entity
in the world with all its components registered and populated. Completely
optional engine feature.

---

## Two Seams Needed

**Where does the data come from:**
```ocaml
module type Source.S = sig
  val load : string -> raw_data
end
```
Reuses the `Asset_lookup.S` pattern. Could be EDN files, JSON, a database,
generated data — the prefab system doesn't care.

**How do components get deserialized:**
```ocaml
module type Deserializer.S = sig
  val deserialize : World.rw World.t -> Entity_id.t -> component_name:string -> raw_data -> unit
end
```
The hard part. At load time you have `"position": { x: 0, y: 0 }` and need
to dispatch to the right component deserializer. Needs a registry populated
at startup:

```ocaml
Prefab.register_component "position" (module Position_deserializer);
Prefab.register_component "health"   (module Health_deserializer);
```

---

## Why This Is Useful (for my game specifically)

Annual content updates without recompiling. New enemy type = new EDN file,
new component values. No OCaml touched. Dream.

---

## Open Questions (not urgent, just noted)

- Prefab inheritance / composition? (`"goblin_archer"` extends `"goblin_base"`)
- Nested entities? (prefab that spawns a parent + children hierarchy)
- Hot reload during development?
- Where does the deserializer registry live — global or per-world?

---

## Mod System — Not the Engine's Problem

A full mod system is not an `eon_engine` concern. The prefab system's
`Source.S` seam is sufficient — the engine just loads named entities from
whatever source you give it. Mod support is built on top by the game:

- `eon_engine` — `Prefab.load world "goblin"` via `Source.S`
- `eon_game` — plug in a `Source.S` that reads from base game folder OR
  a Steam Workshop folder, with whatever priority and conflict rules the
  game wants

The engine is oblivious to what a mod is. Validation, versioning, load
order, conflict resolution — all game responsibility. If mods never happen,
the prefab system still pays for itself in development ergonomics alone.

---

## Not Now

Earlier than originally thought — development ergonomics alone justify it.
Want it working before serious game content starts, not after. Natural time:
right after `Resource.S` / `Service.S` are implemented.
