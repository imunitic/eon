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

## Not Now

After core engine works and the game content pipeline becomes real friction.
